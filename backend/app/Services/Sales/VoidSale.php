<?php

namespace App\Services\Sales;

use App\Enums\LedgerType;
use App\Enums\PaymentType;
use App\Enums\SaleStatus;
use App\Enums\StockMovementType;
use App\Exceptions\ApiException;
use App\Models\Customer;
use App\Models\Payment;
use App\Models\Sale;
use App\Models\User;
use App\Services\Audit\AuditLogger;
use App\Services\Customers\LedgerService;
use App\Services\Inventory\StockService;
use App\Services\Tenancy\ShopLock;
use App\Support\Dec;
use Illuminate\Support\Facades\DB;

/**
 * Cancels a whole sale. Nothing is deleted; every effect is reversed by a
 * new row, so the history shows both the sale and its cancellation:
 *
 *   stock comes back (movement "sale_void"), the due is taken off the
 *   customer's ledger, money that was paid is recorded as refunded.
 */
class VoidSale
{
    public function __construct(
        private readonly ShopLock $shopLock,
        private readonly StockService $stock,
        private readonly LedgerService $ledger,
        private readonly AuditLogger $audit,
    ) {}

    public function handle(Sale $sale, string $reason, User $actor): Sale
    {
        return DB::transaction(function () use ($sale, $reason, $actor) {
            // Same lock as a sale: voids and sales in one shop never interleave.
            $this->shopLock->acquire();

            $sale = Sale::query()->lockForUpdate()->findOrFail($sale->id);

            if ($sale->isVoided()) {
                throw ApiException::conflict('SALE_ALREADY_VOIDED', __('This sale has already been cancelled.'));
            }

            foreach ($sale->items as $item) {
                $this->stock->change($item->product_variant_id, StockMovementType::SaleVoid, Dec::of($item->quantity), $actor, [
                    'unit_cost' => $item->unit_cost,
                    'reference' => $sale,
                    'include_deleted' => true,
                ]);
            }

            // Money taken at the counter goes back to the customer, by the same methods.
            foreach ($sale->payments()->where('type', PaymentType::Sale)->get() as $payment) {
                $refund = new Payment;
                $refund->sale_id = $sale->id;
                $refund->customer_id = $sale->customer_id;
                $refund->type = PaymentType::Refund;
                $refund->method = $payment->method;
                $refund->amount = $payment->amount;
                $refund->reference = $payment->transaction_id;
                $refund->paid_at = now();
                $refund->created_by = $actor->id;
                $refund->save();
            }

            if ($sale->customer_id !== null) {
                if (Dec::of($sale->due_amount)->isPositive()) {
                    // If the customer already paid this due off, their balance goes below zero:
                    // the shop now owes them, which is exactly the truth.
                    $this->ledger->credit($sale->customer_id, $sale->due_amount, LedgerType::SaleVoid, $actor, $sale);
                }

                $customer = Customer::query()->withTrashed()->lockForUpdate()->findOrFail($sale->customer_id);
                $customer->total_purchases = Dec::money(Dec::of($customer->total_purchases)->minus($sale->grand_total));
                $customer->total_paid = Dec::money(Dec::of($customer->total_paid)->minus($sale->paid_amount));
                $customer->save();
            }

            $sale->status = SaleStatus::Voided;
            $sale->voided_at = now();
            $sale->voided_by = $actor->id;
            $sale->void_reason = $reason;
            $sale->save();

            $this->audit->log('sale.voided', $sale, ['status' => 'completed'], [
                'status' => 'voided', 'invoice_no' => $sale->invoice_no, 'grand_total' => $sale->grand_total, 'reason' => $reason,
            ]);

            return $sale;
        }, attempts: 3);
    }
}
