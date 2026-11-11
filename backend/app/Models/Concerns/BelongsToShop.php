<?php

namespace App\Models\Concerns;

use App\Models\Shop;
use App\Services\Tenancy\MissingTenantException;
use App\Services\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use LogicException;

/**
 * Add to every shop-owned model.
 *
 *  - reads are scoped to the current shop (ShopScope)
 *  - shop_id is set from the tenant context on create, never from input
 *  - shop_id cannot be changed afterwards
 */
trait BelongsToShop
{
    public static function bootBelongsToShop(): void
    {
        static::addGlobalScope(new ShopScope);

        static::creating(function ($model) {
            $tenant = app(TenantContext::class);

            if ($tenant->has()) {
                // The context always wins over anything that was filled in.
                $model->shop_id = $tenant->id();
            } elseif (! $tenant->isBypassed() || $model->shop_id === null) {
                throw MissingTenantException::forModel($model::class);
            }
        });

        static::updating(function ($model) {
            if ($model->isDirty('shop_id')) {
                throw new LogicException('shop_id cannot be changed on '.$model::class.'.');
            }
        });
    }

    public function shop(): BelongsTo
    {
        return $this->belongsTo(Shop::class);
    }
}
