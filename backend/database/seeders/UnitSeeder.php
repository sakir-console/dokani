<?php

namespace Database\Seeders;

use App\Models\Unit;
use App\Services\Tenancy\TenantContext;
use Illuminate\Database\Seeder;

class UnitSeeder extends Seeder
{
    /** name => [Bangla name, short name, allows decimal quantities] */
    public const UNITS = [
        'Piece' => ['পিস', 'pc', false],
        'Kilogram' => ['কেজি', 'kg', true],
        'Gram' => ['গ্রাম', 'g', true],
        'Liter' => ['লিটার', 'L', true],
        'Milliliter' => ['মিলিলিটার', 'ml', true],
        'Packet' => ['প্যাকেট', 'pkt', false],
        'Box' => ['বক্স', 'box', false],
        'Dozen' => ['ডজন', 'dz', false],
        'Meter' => ['মিটার', 'm', true],
        'Feet' => ['ফুট', 'ft', true],
        'Bottle' => ['বোতল', 'btl', false],
        'Pair' => ['জোড়া', 'pr', false],
        'Carton' => ['কার্টন', 'ctn', false],
    ];

    /** Built-in units, shared by every shop (shop_id NULL). Safe to run repeatedly. */
    public function run(): void
    {
        app(TenantContext::class)->withoutTenancy(function () {
            foreach (self::UNITS as $name => [$nameBn, $short, $decimal]) {
                Unit::query()->whereNull('shop_id')->updateOrCreate(
                    ['name' => $name],
                    ['name_bn' => $nameBn, 'short_name' => $short, 'allows_decimal' => $decimal],
                );
            }
        });
    }
}
