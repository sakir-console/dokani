<?php

namespace App\Models;

use App\Enums\ShopRole;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Membership of a user in a shop, with the role held there.
 */
class ShopUser extends Model
{
    // Mirrors the column defaults, so a freshly created model is complete without a reload.
    protected $attributes = ['is_active' => true];

    protected $fillable = ['shop_id', 'user_id', 'role', 'is_active'];

    protected function casts(): array
    {
        return [
            'role' => ShopRole::class,
            'is_active' => 'boolean',
        ];
    }

    public function shop(): BelongsTo
    {
        return $this->belongsTo(Shop::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
