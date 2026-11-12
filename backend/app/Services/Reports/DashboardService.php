<?php

namespace App\Services\Reports;

use App\Enums\SaleStatus;
use App\Models\Customer;
use App\Models\Product;
use App\Models\Sale;
use App\Services\Tenancy\TenantContext;
use App\Support\Dec;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;

/**
 * Figures for the shop's home screen. "Today" is the shop's own calendar day.
 */
class DashboardService
{
    public function __construct(private readonly TenantContext $tenant) {}

    /**
     * Sales is what was billed. Profit is a different number:
     *   revenue (items after discounts) − cost of those items at the time of sale,
     *   plus additional charges when the shop counts them as income.
     * Cancelled sales are left out of both.
     *
     * @return array{sales: string, profit: string, orders: int, items_sold: string, paid: string, due: string}
     */
    public function today(): array
    {
        $shop = $this->tenant->shop();
        $start = now($shop->timezone)->startOfDay()->utc();

        $row = Sale::query()
            ->where('status', SaleStatus::Completed)
            ->where('sold_at', '>=', $start)
            ->selectRaw('count(*) as orders, coalesce(sum(grand_total), 0) as sales, coalesce(sum(subtotal - discount_amount), 0) as revenue,
                coalesce(sum(total_cost), 0) as cost, coalesce(sum(additional_charge), 0) as charges,
                coalesce(sum(total_items), 0) as items, coalesce(sum(paid_amount), 0) as paid, coalesce(sum(due_amount), 0) as due')
            ->toBase()->first();

        $profit = Dec::of($row->revenue)->minus($row->cost);
        if ($shop->resolvedSettings()['charge_counts_as_income']) {
            $profit = $profit->plus($row->charges);
        }

        return [
            'sales' => Dec::money($row->sales),
            'profit' => Dec::money($profit),
            'orders' => (int) $row->orders,
            'items_sold' => Dec::qty($row->items),
            'paid' => Dec::money($row->paid),
            'due' => Dec::money($row->due),
        ];
    }

    /** @return array{total_products: int, low_stock_products: int, out_of_stock_products: int} */
    public function stock(): array
    {
        $defaultThreshold = $this->tenant->shop()->resolvedSettings()['low_stock_threshold'];

        $having = fn (string $state) => Product::query()->whereHas('variants', function (Builder $q) use ($state, $defaultThreshold) {
            $q->join('products as p', 'p.id', '=', 'product_variants.product_id');
            $state === 'out'
                ? $q->where('product_variants.stock_quantity', '<=', 0)
                : $q->where('product_variants.stock_quantity', '>', 0)
                    ->whereRaw('product_variants.stock_quantity <= coalesce(p.low_stock_threshold, ?)', [$defaultThreshold]);
        })->count();

        return [
            'total_products' => Product::query()->count(),
            'low_stock_products' => $having('low'),
            'out_of_stock_products' => $having('out'),
        ];
    }

    public function totalCustomerDue(): string
    {
        return Dec::money(Customer::query()->where('current_due', '>', 0)->sum('current_due'));
    }

    public function customersWithDue(): int
    {
        return Customer::query()->where('current_due', '>', 0)->count();
    }

    /** @return Collection<int, Sale> */
    public function recentSales(int $limit = 5): Collection
    {
        return Sale::query()->with(['customer', 'invoice'])->latest('sold_at')->latest('id')->limit($limit)->get();
    }
}
