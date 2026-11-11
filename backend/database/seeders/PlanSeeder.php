<?php

namespace Database\Seeders;

use App\Models\Module;
use App\Models\Plan;
use Illuminate\Database\Seeder;

class PlanSeeder extends Seeder
{
    /**
     * Starting plans. Prices and limits are placeholders for the admin to
     * change in the panel; existing plans are never overwritten by this seeder.
     */
    public const PLANS = [
        'free' => [
            'name' => 'Free', 'price_monthly' => 0, 'price_yearly' => 0,
            'max_products' => 50, 'max_users' => 1, 'max_monthly_sales' => 300,
            'modules' => [], 'is_default' => true,
        ],
        'basic' => [
            'name' => 'Basic', 'price_monthly' => 299, 'price_yearly' => 2990,
            'max_products' => 500, 'max_users' => 2, 'max_monthly_sales' => null,
            'modules' => ['inventory', 'vendors', 'reports', 'global_catalog'],
        ],
        'standard' => [
            'name' => 'Standard', 'price_monthly' => 599, 'price_yearly' => 5990,
            'max_products' => 3000, 'max_users' => 5, 'max_monthly_sales' => null,
            'modules' => ['inventory', 'vendors', 'reports', 'global_catalog', 'exports'],
        ],
        'premium' => [
            'name' => 'Premium', 'price_monthly' => 999, 'price_yearly' => 9990,
            'max_products' => null, 'max_users' => null, 'max_monthly_sales' => null,
            'modules' => ['inventory', 'vendors', 'reports', 'global_catalog', 'exports', 'expenses', 'purchases', 'employees', 'branches', 'loyalty', 'analytics'],
        ],
    ];

    public function run(): void
    {
        $moduleIds = Module::query()->pluck('id', 'key');
        $order = 0;

        foreach (self::PLANS as $code => $attributes) {
            $modules = $attributes['modules'];
            unset($attributes['modules']);

            $plan = Plan::firstOrCreate(['code' => $code], $attributes + ['is_default' => false, 'sort_order' => $order]);
            $order++;

            if ($plan->wasRecentlyCreated) {
                $plan->modules()->sync($moduleIds->only($modules)->values());
            }
        }
    }
}
