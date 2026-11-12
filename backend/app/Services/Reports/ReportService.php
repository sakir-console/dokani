<?php

namespace App\Services\Reports;

use App\Enums\PaymentMethod;
use App\Enums\PaymentType;
use App\Enums\SaleStatus;
use App\Models\Customer;
use App\Models\Payment;
use App\Models\ProductVariant;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Services\Tenancy\TenantContext;
use App\Support\Dec;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Business reports for one shop and one period.
 *
 * Revenue and profit are different things and are kept apart throughout:
 *
 *   sales        what was billed                       Σ grand_total
 *   revenue      goods sold after all discounts        Σ (subtotal − discount)
 *   cost         what those goods cost at sale time    Σ total_cost (frozen on each sale)
 *   gross profit revenue − cost, plus additional charges when the shop counts them as income
 *
 * Cancelled sales are excluded from all of these and counted separately.
 * Every query runs through tenant-scoped models, so figures are this shop's only.
 */
class ReportService
{
    public function __construct(private readonly TenantContext $tenant) {}

    /** @return array<string, mixed> */
    public function summary(ReportRange $range): array
    {
        $shop = $this->tenant->shop();

        $sales = $this->completed($range)
            ->selectRaw('count(*) as orders,
                coalesce(sum(grand_total), 0) as total_sales,
                coalesce(sum(subtotal), 0) as subtotal,
                coalesce(sum(discount_amount), 0) as sale_discounts,
                coalesce(sum(additional_charge), 0) as charges,
                coalesce(sum(paid_amount), 0) as paid,
                coalesce(sum(due_amount), 0) as due,
                coalesce(sum(total_cost), 0) as cost,
                coalesce(sum(total_items), 0) as items')
            ->toBase()->first();

        // Discounts given on individual lines are already inside each sale's subtotal.
        $lineDiscounts = SaleItem::query()
            ->whereIn('sale_id', $this->completed($range)->select('id'))
            ->sum('discount_amount');

        $voided = Sale::query()
            ->where('status', SaleStatus::Voided)
            ->whereBetween('sold_at', [$range->from, $range->to])
            ->selectRaw('count(*) as orders, coalesce(sum(grand_total), 0) as amount')
            ->toBase()->first();

        $dueCollected = Payment::query()
            ->where('type', PaymentType::DueCollection)
            ->whereBetween('paid_at', [$range->from, $range->to])
            ->sum('amount');

        $revenue = Dec::of($sales->subtotal)->minus($sales->sale_discounts);
        $chargesAreIncome = (bool) $shop->resolvedSettings()['charge_counts_as_income'];
        $profit = $revenue->minus($sales->cost);
        if ($chargesAreIncome) {
            $profit = $profit->plus($sales->charges);
        }

        return [
            'orders' => (int) $sales->orders,
            'items_sold' => Dec::qty($sales->items),
            'total_sales' => Dec::money($sales->total_sales),
            'total_paid' => Dec::money($sales->paid),
            'total_due' => Dec::money($sales->due),
            'total_discounts' => Dec::money(Dec::of($sales->sale_discounts)->plus($lineDiscounts)),
            'additional_charges' => Dec::money($sales->charges),
            'revenue' => Dec::money($revenue),
            'cost_of_goods' => Dec::money($sales->cost),
            'gross_profit' => Dec::money($profit),
            'charges_counted_as_income' => $chargesAreIncome,
            // Money that came in against earlier dues during this period. Not part of this period's sales.
            'due_collected' => Dec::money($dueCollected),
            'cancelled_orders' => (int) $voided->orders,
            'cancelled_amount' => Dec::money($voided->amount),
        ];
    }

    /**
     * Money in and out by payment method during the period, by the date the
     * money moved: taken at the counter, collected against dues, refunded.
     *
     * @return array{methods: list<array<string, mixed>>, totals: array<string, string>, sold_on_due: string}
     */
    public function paymentMethods(ReportRange $range): array
    {
        $rows = Payment::query()
            ->whereBetween('paid_at', [$range->from, $range->to])
            ->selectRaw('method, type, coalesce(sum(amount), 0) as amount, count(*) as payments')
            ->groupBy('method', 'type')
            ->toBase()->get();

        $methods = [];
        $totals = ['sales' => Dec::of(0), 'due_collections' => Dec::of(0), 'refunds' => Dec::of(0)];

        foreach (PaymentMethod::cases() as $method) {
            $amount = fn (PaymentType $type) => Dec::of(
                $rows->first(fn ($r) => $r->method === $method->value && $r->type === $type->value)->amount ?? 0
            );

            $sales = $amount(PaymentType::Sale);
            $collections = $amount(PaymentType::DueCollection);
            $refunds = $amount(PaymentType::Refund);

            if ($sales->isZero() && $collections->isZero() && $refunds->isZero()) {
                continue;
            }

            $totals['sales'] = $totals['sales']->plus($sales);
            $totals['due_collections'] = $totals['due_collections']->plus($collections);
            $totals['refunds'] = $totals['refunds']->plus($refunds);

            $methods[] = [
                'method' => $method->value,
                'label' => $method->label(),
                'sales' => Dec::money($sales),
                'due_collections' => Dec::money($collections),
                'refunds' => Dec::money($refunds),
                'net' => Dec::money($sales->plus($collections)->minus($refunds)),
            ];
        }

        return [
            'methods' => $methods,
            'totals' => [
                'sales' => Dec::money($totals['sales']),
                'due_collections' => Dec::money($totals['due_collections']),
                'refunds' => Dec::money($totals['refunds']),
                'net' => Dec::money($totals['sales']->plus($totals['due_collections'])->minus($totals['refunds'])),
            ],
            // Not money received: what was sold on credit in the period.
            'sold_on_due' => Dec::money($this->completed($range)->sum('due_amount')),
        ];
    }

    /**
     * Products ranked by quantity or by revenue. Names are the ones on the
     * sale lines, so a product renamed or deleted since still appears.
     * Revenue is after line discounts; bill-level discounts are not spread over lines.
     *
     * @return Collection<int, array<string, mixed>>
     */
    public function bestSellers(ReportRange $range, string $by = 'quantity', int $limit = 20): Collection
    {
        return SaleItem::query()
            ->whereIn('sale_id', $this->completed($range)->select('id'))
            ->selectRaw('product_variant_id, max(product_name) as product_name, max(variant_name) as variant_name,
                max(unit_name) as unit_name, sum(quantity) as quantity, sum(line_total) as revenue,
                sum(round(unit_cost * quantity, 2)) as cost')
            ->groupBy('product_variant_id')
            ->orderByDesc($by === 'revenue' ? 'revenue' : 'quantity')
            ->orderBy('product_name')
            ->limit(min(max($limit, 1), 100))
            ->toBase()->get()
            ->map(fn ($row) => [
                'variant_id' => (int) $row->product_variant_id,
                'product_name' => $row->product_name,
                'variant_name' => $row->variant_name,
                'unit_name' => $row->unit_name,
                'quantity' => Dec::qty($row->quantity),
                'revenue' => Dec::money($row->revenue),
                'profit' => Dec::money(Dec::of($row->revenue)->minus($row->cost)),
            ]);
    }

    /** Variants at or below their threshold, emptiest first. Not tied to a period. */
    public function lowStock(int $perPage = 50): LengthAwarePaginator
    {
        $defaultThreshold = $this->tenant->shop()->resolvedSettings()['low_stock_threshold'];

        return $this->lowStockQuery($defaultThreshold)->paginate(min($perPage, 100))
            ->through(fn (ProductVariant $variant) => $this->lowStockRow($variant, $defaultThreshold));
    }

    /** @return Collection<int, array<string, mixed>> */
    public function lowStockAll(int $limit): Collection
    {
        $defaultThreshold = $this->tenant->shop()->resolvedSettings()['low_stock_threshold'];

        return $this->lowStockQuery($defaultThreshold)->limit($limit)->get()
            ->map(fn (ProductVariant $variant) => $this->lowStockRow($variant, $defaultThreshold));
    }

    private function lowStockQuery(mixed $defaultThreshold): Builder
    {
        return ProductVariant::query()
            ->select('product_variants.*')
            ->join('products', 'products.id', '=', 'product_variants.product_id')
            ->whereNull('products.deleted_at')
            ->whereRaw('product_variants.stock_quantity <= coalesce(products.low_stock_threshold, ?)', [$defaultThreshold])
            ->with('product.unit')
            ->orderBy('product_variants.stock_quantity')
            ->orderBy('products.name');
    }

    /** @return array<string, mixed> */
    private function lowStockRow(ProductVariant $variant, mixed $defaultThreshold): array
    {
        return [
            'product_id' => $variant->product_id,
            'variant_id' => $variant->id,
            'product_name' => $variant->product->name,
            'variant_name' => $variant->name,
            'unit_name' => $variant->product->unit->name,
            'stock_quantity' => $variant->stock_quantity,
            'threshold' => Dec::qty($variant->product->low_stock_threshold ?? $defaultThreshold),
            'status' => Dec::of($variant->stock_quantity)->isNegativeOrZero() ? 'out' : 'low',
        ];
    }

    /** Customers who owe money, largest balance first. */
    public function dues(): Builder
    {
        return Customer::query()->where('current_due', '>', 0)->orderByDesc('current_due')->orderBy('name');
    }

    /** @return array{customers: int, total_due: string} */
    public function duesTotal(): array
    {
        return [
            'customers' => $this->dues()->count(),
            'total_due' => Dec::money($this->dues()->sum('current_due')),
        ];
    }

    /** Sales in the period, newest first, cancelled ones included (and marked). */
    public function sales(ReportRange $range): Builder
    {
        return Sale::query()
            ->whereBetween('sold_at', [$range->from, $range->to])
            ->with(['customer', 'invoice'])
            ->latest('sold_at')->latest('id');
    }

    /**
     * One row per calendar day of the period (in the shop's time zone), including days with no sales.
     *
     * @return list<array{date: string, orders: int, sales: string, profit: string}>
     */
    public function daily(ReportRange $range): array
    {
        $shop = $this->tenant->shop();
        $chargesAreIncome = (bool) $shop->resolvedSettings()['charge_counts_as_income'];

        // Grouped in PHP: converting each sale to the shop's day is exact for any
        // time zone, with no dependence on the database server's time zone tables.
        $days = [];
        $this->completed($range)
            ->select(['sold_at', 'grand_total', 'subtotal', 'discount_amount', 'additional_charge', 'total_cost'])
            ->toBase()->orderBy('id')
            ->each(function ($sale) use (&$days, $range, $chargesAreIncome) {
                $day = Carbon::parse($sale->sold_at, 'UTC')->timezone($range->timezone)->toDateString();
                $profit = Dec::of($sale->subtotal)->minus($sale->discount_amount)->minus($sale->total_cost);
                if ($chargesAreIncome) {
                    $profit = $profit->plus($sale->additional_charge);
                }

                $days[$day] ??= ['orders' => 0, 'sales' => Dec::of(0), 'profit' => Dec::of(0)];
                $days[$day]['orders']++;
                $days[$day]['sales'] = $days[$day]['sales']->plus($sale->grand_total);
                $days[$day]['profit'] = $days[$day]['profit']->plus($profit);
            });

        $rows = [];
        for ($day = $range->fromLocal()->startOfDay(); $day->lte($range->toLocal()); $day = $day->addDay()) {
            $key = $day->toDateString();
            $rows[] = [
                'date' => $key,
                'orders' => $days[$key]['orders'] ?? 0,
                'sales' => Dec::money($days[$key]['sales'] ?? 0),
                'profit' => Dec::money($days[$key]['profit'] ?? 0),
            ];
        }

        return $rows;
    }

    private function completed(ReportRange $range): Builder
    {
        return Sale::query()
            ->where('status', SaleStatus::Completed)
            ->whereBetween('sold_at', [$range->from, $range->to]);
    }
}
