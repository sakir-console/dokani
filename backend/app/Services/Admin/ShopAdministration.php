<?php

namespace App\Services\Admin;

use App\Enums\ShopStatus;
use App\Models\Shop;
use App\Services\Audit\AuditLogger;
use Illuminate\Support\Facades\DB;

/**
 * Admin actions on a shop. Every change is written to the audit log.
 */
class ShopAdministration
{
    public function __construct(private readonly AuditLogger $audit) {}

    public function changeStatus(Shop $shop, ShopStatus $status, ?string $reason = null): Shop
    {
        if ($shop->status === $status) {
            return $shop;
        }

        return DB::transaction(function () use ($shop, $status, $reason) {
            $old = ['status' => $shop->status->value, 'suspended_reason' => $shop->suspended_reason];

            $shop->status = $status;
            $shop->suspended_reason = $status === ShopStatus::Suspended ? ($reason ?: null) : null;
            $shop->save();

            $this->audit->log(
                'shop.status_changed',
                $shop,
                $old,
                ['status' => $status->value, 'suspended_reason' => $shop->suspended_reason],
                $shop->id,
            );

            return $shop;
        });
    }
}
