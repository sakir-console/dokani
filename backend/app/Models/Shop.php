<?php

namespace App\Models;

use App\Enums\ShopStatus;
use App\Enums\ShopType;
use App\Enums\SubscriptionStatus;
use Database\Factories\ShopFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Storage;

/**
 * A tenant. Every shop-owned record points here through shop_id.
 */
class Shop extends Model
{
    /** @use HasFactory<ShopFactory> */
    use HasFactory, SoftDeletes;

    /** Settings a shop may change, with their defaults. */
    public const DEFAULT_SETTINGS = [
        'allow_negative_stock' => false,
        'low_stock_threshold' => 5,
        'receipt_width' => '58',
        'invoice_footer' => null,
        'charge_counts_as_income' => true,
    ];

    // Mirrors the column defaults, so a freshly created model is complete without a reload.
    protected $attributes = ['status' => 'active', 'currency' => 'BDT', 'timezone' => 'Asia/Dhaka'];

    protected $fillable = ['name', 'shop_type', 'phone', 'address'];

    protected function casts(): array
    {
        return [
            'status' => ShopStatus::class,
            'shop_type' => ShopType::class,
            'settings' => 'array',
        ];
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_id')->withTrashed();
    }

    public function memberships(): HasMany
    {
        return $this->hasMany(ShopUser::class);
    }

    public function users(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'shop_users')->withPivot(['role', 'is_active'])->withTimestamps();
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(Subscription::class);
    }

    /** The subscription currently in force, if any (not expired, not cancelled). */
    public function activeSubscription(): HasOne
    {
        return $this->hasOne(Subscription::class)
            ->where('status', SubscriptionStatus::Active)
            ->where(fn ($q) => $q->whereNull('ends_at')->orWhere('ends_at', '>', now()))
            ->latestOfMany();
    }

    public function moduleOverrides(): HasMany
    {
        return $this->hasMany(ShopModuleOverride::class);
    }

    /** @return array<string, mixed> */
    public function resolvedSettings(): array
    {
        return array_merge(self::DEFAULT_SETTINGS, array_intersect_key($this->settings ?? [], self::DEFAULT_SETTINGS));
    }

    public function logoUrl(): ?string
    {
        return $this->logo_path ? Storage::disk('public')->url($this->logo_path) : null;
    }

    public function isUsable(): bool
    {
        return $this->status === ShopStatus::Active;
    }
}
