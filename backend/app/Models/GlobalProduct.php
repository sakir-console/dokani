<?php

namespace App\Models;

use Database\Factories\GlobalProductFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Storage;

/**
 * A product template managed by the platform admin. It has no price and no
 * stock; shops import a copy and own that copy completely.
 */
class GlobalProduct extends Model
{
    /** @use HasFactory<GlobalProductFactory> */
    use HasFactory, SoftDeletes;

    protected $attributes = ['default_unit' => 'Piece', 'is_active' => true];

    protected $fillable = ['global_category_id', 'name', 'name_bn', 'brand', 'description', 'default_unit', 'barcode', 'is_active'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(GlobalCategory::class, 'global_category_id');
    }

    public function variants(): HasMany
    {
        return $this->hasMany(GlobalProductVariant::class)->orderBy('sort_order')->orderBy('id');
    }

    public function imageUrl(): ?string
    {
        return $this->image_path ? Storage::disk('public')->url($this->image_path) : null;
    }
}
