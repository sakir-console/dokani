<?php

namespace App\Models\Concerns;

use App\Services\Tenancy\MissingTenantException;
use App\Services\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

/**
 * For tables that mix built-in rows (shop_id NULL, visible to everyone) with
 * a shop's own rows: a shop sees the built-ins plus its own, never another shop's.
 */
class ShopOrSystemScope implements Scope
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

        $column = $model->qualifyColumn('shop_id');
        $builder->where(fn (Builder $q) => $q->whereNull($column)->orWhere($column, $tenant->id()));
    }
}
