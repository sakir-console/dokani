<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    /** Reference data every installation needs. Safe to run repeatedly. */
    public function run(): void
    {
        $this->call([
            ModuleSeeder::class,
            PlanSeeder::class,
            AdminSeeder::class,
        ]);
    }
}
