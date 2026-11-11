<?php

namespace App\Models\Concerns;

use App\Services\Tenancy\MissingTenantException;
use App\Services\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

/**
 * Restricts every query on a shop-owned model to the current shop.
 * Fail-closed: with no shop in context the query throws.
 */
class ShopScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        $tenant = app(TenantContext::class);

        if ($tenant->isBypassed()) {
            return;
        }

        if (! $tenant->has()) {
            throw MissingTenantException::forModel($model::class);
        }

        $builder->where($model->qualifyColumn('shop_id'), $tenant->id());
    }
}
