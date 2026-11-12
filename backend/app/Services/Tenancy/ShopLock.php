<?php

namespace App\Services\Tenancy;

use Illuminate\Support\Facades\DB;

/**
 * One lock per shop for operations that touch several rows at once
 * (a sale, a void, creating a product against the plan limit).
 *
 * Taking this first means such operations in the same shop run one after
 * another, so they can never lock variants or customers in conflicting
 * orders and deadlock. It lasts until the surrounding transaction ends.
 * Other shops are unaffected.
 */
class ShopLock
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function acquire(): void
    {
        DB::table('shops')->where('id', $this->tenant->id())->lockForUpdate()->value('id');
    }
}
