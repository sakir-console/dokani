<?php

namespace Database\Seeders;

use App\Models\Module;
use Illuminate\Database\Seeder;

class ModuleSeeder extends Seeder
{
    /**
     * key => [name, description, is_core, is_available]
     * Modules marked unavailable are on the roadmap; they can be assigned to
     * plans now but are not granted to shops until they are built.
     */
    public const MODULES = [
        'products' => ['Products', 'Products, categories, variants, barcodes and stock', true, true],
        'pos' => ['Point of sale', 'Sales, payments and invoices', true, true],
        'customers' => ['Customers & due', 'Customer accounts, due ledger and due collection', true, true],
        'offline' => ['Offline mode', 'Sell without internet and sync later', true, true],
        'inventory' => ['Inventory history', 'Full stock movement history', false, true],
        'vendors' => ['Vendors', 'Vendor list and vendor products', false, true],
        'reports' => ['Reports', 'Sales, profit and stock reports', false, true],
        'exports' => ['Exports', 'Excel, CSV and PDF export', false, true],
        'global_catalog' => ['Global catalogue', 'Import products from the shared catalogue', false, true],
        'expenses' => ['Expenses', 'Expense tracking', false, false],
        'purchases' => ['Purchases', 'Purchase orders and supplier due', false, false],
        'employees' => ['Employees', 'Staff accounts and roles', false, false],
        'branches' => ['Branches', 'Multiple branches', false, false],
        'loyalty' => ['Loyalty', 'Customer loyalty points', false, false],
        'analytics' => ['Advanced analytics', 'Trends and forecasts', false, false],
    ];

    public function run(): void
    {
        $order = 0;
        foreach (self::MODULES as $key => [$name, $description, $isCore, $isAvailable]) {
            Module::updateOrCreate(['key' => $key], [
                'name' => $name,
                'description' => $description,
                'is_core' => $isCore,
                'is_available' => $isAvailable,
                'sort_order' => $order++,
            ]);
        }
    }
}
