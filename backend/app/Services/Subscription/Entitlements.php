<?php

namespace App\Services\Subscription;

use App\Models\Module;
use App\Models\Plan;
use App\Models\Shop;
use App\Models\Subscription;

/**
 * What a shop is allowed to use right now.
 *
 * Plan: the subscription in force, otherwise the default (free) plan.
 * Modules: core modules + the plan's modules, then per-shop admin overrides.
 * Modules that are not built yet (is_available = false) are never granted.
 */
class Entitlements
{
    /** @var array<int, array{plan: Plan, subscription: ?Subscription, modules: list<string>}> */
    private array $cache = [];

    public function plan(Shop $shop): Plan
    {
        return $this->resolve($shop)['plan'];
    }

    public function subscription(Shop $shop): ?Subscription
    {
        return $this->resolve($shop)['subscription'];
    }

    /** @return list<string> */
    public function modules(Shop $shop): array
    {
        return $this->resolve($shop)['modules'];
    }

    public function hasModule(Shop $shop, string $key): bool
    {
        return in_array($key, $this->modules($shop), true);
    }

    /** @return array{max_products: ?int, max_users: ?int, max_monthly_sales: ?int} */
    public function limits(Shop $shop): array
    {
        $plan = $this->plan($shop);

        return [
            'max_products' => $plan->max_products,
            'max_users' => $plan->max_users,
            'max_monthly_sales' => $plan->max_monthly_sales,
        ];
    }

    public function forget(Shop $shop): void
    {
        unset($this->cache[$shop->id]);
    }

    /** @return array{plan: Plan, subscription: ?Subscription, modules: list<string>} */
    private function resolve(Shop $shop): array
    {
        if (isset($this->cache[$shop->id])) {
            return $this->cache[$shop->id];
        }

        $subscription = $shop->activeSubscription()->with('plan.modules')->first();
        $plan = $subscription?->plan ?? Plan::default()->load('modules');

        $enabled = Module::query()->where('is_core', true)->pluck('key', 'id')->all()
            + $plan->modules->pluck('key', 'id')->all();

        foreach ($shop->moduleOverrides()->with('module')->get() as $override) {
            if ($override->module === null || $override->module->is_core) {
                continue;
            }
            if ($override->is_enabled) {
                $enabled[$override->module_id] = $override->module->key;
            } else {
                unset($enabled[$override->module_id]);
            }
        }

        $available = Module::query()->where('is_available', true)->pluck('key')->all();
        $modules = array_values(array_intersect($available, $enabled));

        return $this->cache[$shop->id] = [
            'plan' => $plan,
            'subscription' => $subscription,
            'modules' => $modules,
        ];
    }
}
