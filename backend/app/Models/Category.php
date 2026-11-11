<?php

namespace App\Models;

use App\Models\Concerns\BelongsToShop;
use Database\Factories\CategoryFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Category extends Model
{
    /** @use HasFactory<CategoryFactory> */
    use BelongsToShop, HasFactory, SoftDeletes;

    // Mirrors the column defaults, so a freshly created model is complete without a reload.
    protected $attributes = ['sort_order' => 0];

    // shop_id is deliberately not fillable: it comes from the tenant context.
    protected $fillable = ['parent_id', 'name', 'sort_order'];

    public function parent(): BelongsTo
    {
        return $this->belongsTo(self::class, 'parent_id');
    }

    public function children(): HasMany
    {
        return $this->hasMany(self::class, 'parent_id');
    }
}
