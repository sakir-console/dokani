<?php

namespace App\Services\Admin;

use App\Enums\BillingCycle;
use App\Enums\ShopStatus;
use App\Enums\SubscriptionStatus;
use App\Models\AuditLog;
use App\Models\Shop;
use App\Models\Subscription;
use App\Models\SubscriptionPayment;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Platform-wide numbers for the admin dashboard.
 * Reads across all shops on purpose; only reachable behind the admin guard.
 */
class DashboardStats
{
    /** @return array<string, int> */
    public function shops(): array
    {
        $byStatus = Shop::query()->selectRaw('status, count(*) as total')->groupBy('status')->pluck('total', 'status');

        return [
            'total' => (int) $byStatus->sum(),
            'active' => (int) ($byStatus[ShopStatus::Active->value] ?? 0),
            'inactive' => (int) ($byStatus[ShopStatus::Inactive->value] ?? 0),
            'suspended' => (int) ($byStatus[ShopStatus::Suspended->value] ?? 0),
        ];
    }

    /** @return array{total_users: int, today: int, last_7_days: int, last_30_days: int} */
    public function registrations(): array
    {
        return [
            'total_users' => User::query()->count(),
            'today' => Shop::query()->where('created_at', '>=', now()->startOfDay())->count(),
            'last_7_days' => Shop::query()->where('created_at', '>=', now()->subDays(7))->count(),
            'last_30_days' => Shop::query()->where('created_at', '>=', now()->subDays(30))->count(),
        ];
    }

    /**
     * @return array{free: int, paid: int, mrr: float, total_revenue: float, expiring_7_days: int, expired: int}
     */
    public function subscriptions(): array
    {
        $inForce = Subscription::query()
            ->where('status', SubscriptionStatus::Active)
            ->where(fn ($q) => $q->whereNull('ends_at')->orWhere('ends_at', '>', now()))
            ->whereHas('shop')
            ->get(['id', 'shop_id', 'billing_cycle', 'price', 'ends_at']);

        $paid = $inForce->filter(fn (Subscription $s) => $s->billing_cycle !== BillingCycle::Lifetime && (float) $s->price > 0);
        $shopsWithPaid = $paid->pluck('shop_id')->unique()->count();

        return [
            'paid' => $shopsWithPaid,
            // Shops with no paid subscription in force are on the free (default) plan.
            'free' => max(Shop::query()->count() - $shopsWithPaid, 0),
            'mrr' => round($paid->sum(fn (Subscription $s) => $s->monthlyValue()), 2),
            'total_revenue' => (float) SubscriptionPayment::query()->sum('amount'),
            'expiring_7_days' => $paid->filter(fn (Subscription $s) => $s->ends_at !== null && $s->ends_at->lte(now()->addDays(7)))->count(),
            'expired' => Subscription::query()
                ->where('status', SubscriptionStatus::Active)
                ->whereNotNull('ends_at')->where('ends_at', '<=', now())
                ->count(),
        ];
    }

    /**
     * New shops per day for the last $days days, oldest first, zero-filled.
     *
     * @return Collection<int, array{date: string, label: string, total: int}>
     */
    public function registrationSeries(int $days = 14): Collection
    {
        $since = now()->subDays($days - 1)->startOfDay();

        $counts = Shop::query()
            ->where('created_at', '>=', $since)
            ->get(['created_at'])
            ->groupBy(fn (Shop $shop) => $shop->created_at->toDateString())
            ->map->count();

        return collect(range(0, $days - 1))->map(function (int $offset) use ($since, $counts) {
            $day = Carbon::parse($since)->addDays($offset);

            return [
                'date' => $day->toDateString(),
                'label' => $day->format('j M'),
                'total' => (int) ($counts[$day->toDateString()] ?? 0),
            ];
        });
    }

    /** @return Collection<int, AuditLog> */
    public function recentActivity(int $limit = 10): Collection
    {
        return AuditLog::query()->with('shop:id,name')->latest('id')->limit($limit)->get();
    }

    /** @return Collection<int, Shop> */
    public function recentShops(int $limit = 5): Collection
    {
        return Shop::query()->with('owner:id,name,phone')->latest('id')->limit($limit)->get();
    }
}
