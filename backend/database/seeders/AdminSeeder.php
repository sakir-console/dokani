<?php

namespace Database\Seeders;

use App\Models\Admin;
use Illuminate\Database\Seeder;

class AdminSeeder extends Seeder
{
    /**
     * Creates the first admin from ADMIN_EMAIL / ADMIN_PASSWORD when both are
     * set. There is no built-in default password. You can also run:
     *   php artisan dokani:create-admin
     */
    public function run(): void
    {
        $email = env('ADMIN_EMAIL');
        $password = env('ADMIN_PASSWORD');

        if (! $email || ! $password) {
            $this->command?->warn('ADMIN_EMAIL / ADMIN_PASSWORD not set — no admin created. Run: php artisan dokani:create-admin');

            return;
        }

        Admin::firstOrCreate(['email' => $email], [
            'name' => env('ADMIN_NAME', 'Administrator'),
            'password' => $password,
            'role' => 'super_admin',
        ]);
    }
}
