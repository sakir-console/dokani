<?php

namespace App\Services\Sales;

use App\Enums\LedgerType;
use App\Enums\PaymentMethod;
use App\Enums\PaymentType;
use App\Enums\StockMovementType;
use App\Exceptions\ApiException;
use App\Models\Customer;
use App\Models\Invoice;
use App\Models\Payment;
use App\Models\ProductVariant;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Models\User;
use App\Services\Audit\AuditLogger;
use App\Services\Customers\CustomerService;
use App\Services\Customers\LedgerService;
use App\Services\Inventory\StockService;
use App\Services\Subscription\Entitlements;
use App\Services\Tenancy\ShopLock;
use App\Services\Tenancy\TenantContext;
use App\Support\Dec;
use Brick\Math\BigDecimal;
use Brick\Math\RoundingMode;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Records a sale. Everything happens in one database transaction:
 *
 *   invoice number → prices and costs from the database → stock check →
 *   totals → payments → customer (when there is a due) → sale, items,
 *   payments, stock movements, ledger entry, invoice.
 *
 * Nothing the app calculated is trusted. The app sends what was sold and
 * what was paid; the totals it sends are only compared with the server's,
 * and a difference rejects the sale.
 */
class CreateSale
{
    public function __construct(
        private readonly TenantContext $tenant,
        private readonly ShopLock $shopLock,
        private readonly InvoiceNumberGenerator $numbers,
        private readonly StockService $stock,
        private readonly LedgerService $ledger,
        private readonly CustomerService $customers,
        private readonly Entitlements $entitlements,
        private readonly AuditLogger $audit,
    ) {}

    /**
     * @param  array<string, mixed>  $data  validated by StoreSaleRequest
     * @return array{0: Sale, 1: bool} the sale, and whether this call created it
     */
    public function handle(array $data, User $actor, bool $canOverridePrice): array
    {
        // The same sale sent again (a retry, a double tap) returns the original.
        if ($existing = $this->find($data['client_uuid'])) {
            return [$existing, false];
        }

        try {
            // attempts: if the database ever reports a deadlock, the whole sale is retried from scratch.
            return DB::transaction(fn () => $this->create($data, $actor, $canOverridePrice), attempts: 3);
        } catch (UniqueConstraintViolationException $e) {
            if ($existing = $this->find($data['client_uuid'])) {
                return [$existing, false];
            }

            throw $e;
        }
    }

    private function find(string $clientUuid): ?Sale
    {
        return Sale::query()->where('client_uuid', $clientUuid)->first();
    }

    /** @return array{0: Sale, 1: bool} */
    private function create(array $data, User $actor, bool $canOverridePrice): array
    {
        $shop = $this->tenant->shop();

        // From here on, sales in this shop run one at a time.
        $this->shopLock->acquire();

        if ($existing = $this->find($data['client_uuid'])) {
            // The identical request finished while this one waited for the lock.
            return [$existing, false];
        }

        $invoiceNo = $this->numbers->next();

        $soldAt = $this->soldAt($data['sold_at'] ?? null);
        $this->assertWithinMonthlyLimit($soldAt);

        // --- Lines: price and cost come from the locked variant rows -------------
        $variantIds = array_values(array_unique(array_column($data['items'], 'variant_id')));
        sort($variantIds);

        $variants = ProductVariant::query()
            ->whereIn('id', $variantIds)
            ->with('product.unit')
            ->orderBy('id')
            ->lockForUpdate()
            ->get()
            ->keyBy('id');

        $lines = [];
        $needed = [];
        $overrides = [];
        $subtotal = Dec::of(0);
        $totalCost = Dec::of(0);
        $totalItems = Dec::of(0);

        foreach ($data['items'] as $index => $item) {
            $variant = $variants->get($item['variant_id']);

            if ($variant === null || $variant->product === null || ! $variant->product->is_active) {
                throw $this->invalid("items.$index.variant_id", 'PRODUCT_UNAVAILABLE', __('This product is no longer available.'));
            }

            $quantity = Dec::of($item['quantity']);
            if (! $variant->product->unit->allows_decimal && ! Dec::isWhole($quantity)) {
                throw $this->invalid("items.$index.quantity", 'QUANTITY_MUST_BE_WHOLE', __('This product is counted in whole units.'));
            }

            $catalogPrice = Dec::of($variant->selling_price);
            $unitPrice = isset($item['unit_price']) ? Dec::of($item['unit_price']) : $catalogPrice;

            if (! $unitPrice->isEqualTo($catalogPrice)) {
                if (! $canOverridePrice) {
                    throw new ApiException('PRICE_OVERRIDE_NOT_ALLOWED', __('The price of ":name" has changed or you are not allowed to change it. Refresh and try again.', ['name' => $variant->product->name]), 403);
                }
                $overrides[] = ['variant_id' => $variant->id, 'catalog_price' => Dec::money($catalogPrice), 'sold_at_price' => Dec::money($unitPrice)];
            }

            $gross = $unitPrice->multipliedBy($quantity)->toScale(2, RoundingMode::HalfUp);
            $lineDiscount = Dec::of($item['discount_amount'] ?? 0);

            if ($lineDiscount->isGreaterThan($gross)) {
                throw $this->invalid("items.$index.discount_amount", 'DISCOUNT_TOO_LARGE', __('The discount is larger than the amount.'));
            }

            $unitCost = Dec::of($variant->purchase_price);
            $lineTotal = $gross->minus($lineDiscount);

            $subtotal = $subtotal->plus($lineTotal);
            $totalCost = $totalCost->plus($unitCost->multipliedBy($quantity)->toScale(2, RoundingMode::HalfUp));
            $totalItems = $totalItems->plus($quantity);
            $needed[$variant->id] = ($needed[$variant->id] ?? Dec::of(0))->plus($quantity);

            $lines[] = compact('variant', 'quantity', 'unitPrice', 'unitCost', 'lineDiscount', 'lineTotal');
        }

        // --- Stock: checked across the whole cart, before anything is written ----
        if (! $shop->resolvedSettings()['allow_negative_stock']) {
            $short = [];
            foreach ($data['items'] as $index => $item) {
                $variant = $variants[$item['variant_id']];
                if ($needed[$variant->id]->isGreaterThan(Dec::of($variant->stock_quantity))) {
                    $short["items.$index.quantity"] = [__('Only :available left of ":name".', [
                        'available' => rtrim(rtrim(Dec::qty($variant->stock_quantity), '0'), '.'),
                        'name' => trim($variant->product->name.' '.($variant->name ?? '')),
                    ])];
                }
            }
            if ($short !== []) {
                throw new ApiException('INSUFFICIENT_STOCK', reset($short)[0], 409, $short);
            }
        }

        // --- Totals ---------------------------------------------------------------
        $discount = Dec::of($data['discount_amount'] ?? 0);
        $charge = Dec::of($data['additional_charge'] ?? 0);

        if ($discount->isGreaterThan($subtotal)) {
            throw $this->invalid('discount_amount', 'DISCOUNT_TOO_LARGE', __('The discount is larger than the amount.'));
        }

        $grandTotal = $subtotal->minus($discount)->plus($charge);

        if (! $grandTotal->isEqualTo(Dec::of($data['grand_total']))) {
            throw new ApiException('TOTALS_MISMATCH', __('The total has changed to :total. Check the bill and try again.', ['total' => Dec::money($grandTotal)]), 422, [
                'grand_total' => [Dec::money($grandTotal)],
            ]);
        }

        // --- Payments ---------------------------------------------------------------
        $paid = Dec::of(0);
        $change = Dec::of(0);

        foreach ($data['payments'] ?? [] as $index => $payment) {
            $amount = Dec::of($payment['amount']);
            $paid = $paid->plus($amount);

            if ($payment['method'] === PaymentMethod::Cash->value && isset($payment['received_amount'])) {
                $received = Dec::of($payment['received_amount']);
                if ($received->isLessThan($amount)) {
                    throw $this->invalid("payments.$index.received_amount", 'RECEIVED_LESS_THAN_AMOUNT', __('The cash received is less than the amount.'));
                }
                $change = $change->plus($received->minus($amount));
            }
        }

        $due = Dec::of($data['due_amount']);

        // Total = Paid + Due, exactly. An overpayment is change, not a payment.
        if (! $paid->plus($due)->isEqualTo($grandTotal)) {
            throw new ApiException('PAYMENT_MISMATCH', __('Payments (:paid) plus due (:due) must equal the total (:total).', [
                'paid' => Dec::money($paid), 'due' => Dec::money($due), 'total' => Dec::money($grandTotal),
            ]), 422, ['payments' => [__('The payments do not add up to the total.')]]);
        }

        // --- Customer: mandatory when anything is left unpaid ------------------------
        $customer = $this->resolveCustomer($data, $actor, $due);

        if ($customer !== null && $due->isPositive() && $customer->credit_limit !== null
            && Dec::of($customer->current_due)->plus($due)->isGreaterThan(Dec::of($customer->credit_limit))) {
            throw $this->invalid('due_amount', 'CREDIT_LIMIT_EXCEEDED', __(':name\'s credit limit is :limit and they already owe :due.', [
                'name' => $customer->name, 'limit' => $customer->credit_limit, 'due' => $customer->current_due,
            ]));
        }

        // --- Write ----------------------------------------------------------------
        $sale = new Sale;
        $sale->client_uuid = $data['client_uuid'];
        $sale->invoice_no = $invoiceNo;
        $sale->customer_id = $customer?->id;
        $sale->subtotal = Dec::money($subtotal);
        $sale->discount_amount = Dec::money($discount);
        $sale->additional_charge = Dec::money($charge);
        $sale->grand_total = Dec::money($grandTotal);
        $sale->paid_amount = Dec::money($paid);
        $sale->due_amount = Dec::money($due);
        $sale->change_amount = Dec::money($change);
        $sale->total_cost = Dec::money($totalCost);
        $sale->total_items = Dec::qty($totalItems);
        $sale->note = $data['note'] ?? null;
        $sale->sold_at = $soldAt;
        $sale->received_at = now();
        $sale->created_by = $actor->id;
        $sale->save();

        foreach ($lines as $line) {
            /** @var ProductVariant $variant */
            $variant = $line['variant'];

            $row = new SaleItem;
            $row->sale_id = $sale->id;
            $row->product_id = $variant->product_id;
            $row->product_variant_id = $variant->id;
            $row->product_name = $variant->product->name;
            $row->variant_name = $variant->name;
            $row->unit_name = $variant->product->unit->name;
            $row->quantity = Dec::qty($line['quantity']);
            $row->unit_price = Dec::money($line['unitPrice']);
            // The cost today, frozen on the line: later price changes never alter past profit.
            $row->unit_cost = Dec::money($line['unitCost']);
            $row->discount_amount = Dec::money($line['lineDiscount']);
            $row->line_total = Dec::money($line['lineTotal']);
            $row->save();

            $this->stock->change($variant->id, StockMovementType::Sale, $line['quantity']->negated(), $actor, [
                'unit_cost' => Dec::money($line['unitCost']),
                'reference' => $sale,
            ]);
        }

        foreach ($data['payments'] ?? [] as $payment) {
            $row = new Payment;
            $row->sale_id = $sale->id;
            $row->customer_id = $customer?->id;
            $row->type = PaymentType::Sale;
            $row->method = PaymentMethod::from($payment['method']);
            $row->amount = Dec::money($payment['amount']);
            $row->received_amount = $payment['method'] === PaymentMethod::Cash->value && isset($payment['received_amount'])
                ? Dec::money($payment['received_amount']) : null;
            $row->transaction_id = $payment['transaction_id'] ?? null;
            $row->reference = $payment['reference'] ?? null;
            // Entered by the cashier. Only a payment gateway callback may ever mark a payment verified.
            $row->verification = 'unverified';
            $row->paid_at = $soldAt;
            $row->created_by = $actor->id;
            $row->save();
        }

        if ($customer !== null) {
            if ($due->isPositive()) {
                $this->ledger->debit($customer->id, $due, LedgerType::SaleDue, $actor, $sale);
            }

            Customer::query()->whereKey($customer->id)->update([
                'total_purchases' => Dec::money(Dec::of($customer->total_purchases)->plus($grandTotal)),
                'total_paid' => Dec::money(Dec::of($customer->total_paid)->plus($paid)),
                'last_purchase_at' => $soldAt,
            ]);
        }

        $invoice = new Invoice;
        $invoice->sale_id = $sale->id;
        $invoice->invoice_no = $invoiceNo;
        $invoice->public_token = rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
        $invoice->shop_snapshot = [
            'name' => $shop->name, 'address' => $shop->address, 'phone' => $shop->phone,
            'logo_path' => $shop->logo_path, 'footer' => $shop->resolvedSettings()['invoice_footer'],
        ];
        $invoice->issued_at = $soldAt;
        $invoice->save();

        if ($overrides !== []) {
            $this->audit->log('sale.price_overridden', $sale, null, ['invoice_no' => $invoiceNo, 'lines' => $overrides]);
        }

        return [$sale, true];
    }

    private function resolveCustomer(array $data, User $actor, BigDecimal $due): ?Customer
    {
        $customerId = $data['customer_id'] ?? null;
        $phone = $data['customer']['phone'] ?? null;

        if ($customerId === null && $phone === null) {
            if ($due->isPositive()) {
                // The core rule: an unpaid amount must belong to someone.
                throw $this->invalid('customer.phone', 'DUE_REQUIRES_CUSTOMER', __('Enter the customer\'s mobile number to sell on due.'));
            }

            return null; // An ordinary, fully paid walk-in sale needs no customer.
        }

        $id = $customerId ?? $this->customers->findOrCreate($phone, $data['customer']['name'] ?? null, $actor)->id;

        // Locked so the balance and totals cannot change under this sale.
        $customer = Customer::query()->lockForUpdate()->find($id);

        if ($customer === null) {
            throw $this->invalid('customer_id', 'VALIDATION_FAILED', __('The selected customer is invalid.'));
        }

        return $customer;
    }

    /** The app's time is used when plausible; otherwise the server's. */
    private function soldAt(?string $value): Carbon
    {
        if ($value === null) {
            return now();
        }

        $time = Carbon::parse($value);

        return $time->isBetween(now()->subDays(7), now()->addMinutes(5)) ? $time : now();
    }

    private function assertWithinMonthlyLimit(Carbon $soldAt): void
    {
        $shop = $this->tenant->shop();
        $limit = $this->entitlements->limits($shop)['max_monthly_sales'];

        if ($limit === null) {
            return;
        }

        $monthStart = $soldAt->copy()->timezone($shop->timezone)->startOfMonth()->utc();
        $count = Sale::query()->where('sold_at', '>=', $monthStart)->count();

        if ($count >= $limit) {
            throw ApiException::forbidden('PLAN_LIMIT_REACHED', __('Your plan allows :limit sales a month. Upgrade to keep selling.', ['limit' => $limit]));
        }
    }

    private function invalid(string $field, string $code, string $message): ApiException
    {
        return new ApiException($code, $message, 422, [$field => [$message]]);
    }
}
