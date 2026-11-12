<?php

namespace App\Models;

use App\Models\Concerns\ShopOrSystemScope;
use App\Services\Tenancy\MissingTenantException;
use App\Services\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Model;
use LogicException;

/**
 * A unit of measure. Built-in units have no shop; shops may add their own.
 */
class Unit extends Model
{
    protected $attributes = ['allows_decimal' => false];

    protected $fillable = ['name', 'name_bn', 'short_name', 'allows_decimal'];

    protected function casts(): array
    {
        return ['allows_decimal' => 'boolean'];
    }

    protected static function booted(): void
    {
        static::addGlobalScope(new ShopOrSystemScope);

        // Inside a shop, a new unit always belongs to that shop.
        // Built-in units are created only by the seeder, outside any shop.
        static::creating(function (Unit $unit) {
            $tenant = app(TenantContext::class);

            if ($tenant->has()) {
                $unit->shop_id = $tenant->id();
            } elseif (! $tenant->isBypassed()) {
                throw MissingTenantException::forModel(self::class);
            }
        });

        static::updating(function (Unit $unit) {
            if ($unit->isDirty('shop_id')) {
                throw new LogicException('shop_id cannot be changed on a unit.');
            }
        });
    }

    public function isBuiltIn(): bool
    {
        return $this->shop_id === null;
    }
}
