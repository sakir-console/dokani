<?php

namespace App\Models;

use Database\Factories\PlanFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Plan extends Model
{
    /** @use HasFactory<PlanFactory> */
    use HasFactory;

    // Mirrors the column defaults, so a freshly created model is complete without a reload.
    protected $attributes = ['is_active' => true, 'is_default' => false, 'sort_order' => 0];

    protected $fillable = [
        'code', 'name', 'description', 'price_monthly', 'price_yearly',
        'max_products', 'max_users', 'max_monthly_sales', 'features',
        'is_active', 'is_default', 'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'price_monthly' => 'decimal:2',
            'price_yearly' => 'decimal:2',
            'features' => 'array',
            'is_active' => 'boolean',
            'is_default' => 'boolean',
        ];
    }

    public function modules(): BelongsToMany
    {
        return $this->belongsToMany(Module::class, 'plan_module');
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(Subscription::class);
    }

    public function isFree(): bool
    {
        return (float) $this->price_monthly === 0.0 && (float) $this->price_yearly === 0.0;
    }

    public static function default(): self
    {
        return static::query()->where('is_default', true)->firstOrFail();
    }
}
