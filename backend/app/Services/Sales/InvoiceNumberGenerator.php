<?php

namespace App\Services\Sales;

use App\Services\Tenancy\TenantContext;
use Illuminate\Support\Facades\DB;

/**
 * Sequential, gap-free invoice numbers per shop: INV-000001, INV-000002, …
 *
 * Must be called inside the sale's transaction, after ShopLock::acquire().
 * With the shop locked, reading and advancing the counter cannot interleave
 * with another sale, so two sales never get the same number, and a
 * rolled-back sale gives its number back.
 */
class InvoiceNumberGenerator
{
    private const KEY = 'invoice';

    public function __construct(private readonly TenantContext $tenant) {}

    public function next(): string
    {
        $shopId = $this->tenant->id();

        DB::table('shop_sequences')->insertOrIgnore(['shop_id' => $shopId, 'key' => self::KEY, 'next_value' => 1]);

        $value = (int) DB::table('shop_sequences')
            ->where('shop_id', $shopId)->where('key', self::KEY)
            ->value('next_value');

        DB::table('shop_sequences')
            ->where('shop_id', $shopId)->where('key', self::KEY)
            ->update(['next_value' => $value + 1]);

        return 'INV-'.str_pad((string) $value, 6, '0', STR_PAD_LEFT);
    }
}
