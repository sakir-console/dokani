<?php

namespace App\Models;

use App\Models\Concerns\BelongsToShop;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * The thing that is actually sold and counted: "T-shirt / M", "Shampoo / 500ml",
 * or the single hidden variant of a product that has no variants.
 *
 * stock_quantity is not fillable. It changes only through StockService, which
 * writes the matching stock_movements row in the same transaction.
 */
class ProductVariant extends Model
{
    use BelongsToShop, SoftDeletes;

    protected $attributes = [
        'purchase_price' => '0.00', 'selling_price' => '0.00', 'stock_quantity' => '0.000',
        'is_default' => false, 'is_active' => true,
    ];

    protected $fillable = ['name', 'options', 'sku', 'purchase_price', 'selling_price', 'is_default', 'is_active'];

    protected function casts(): array
    {
        return [
            'options' => 'array',
            'purchase_price' => 'decimal:2',
            'selling_price' => 'decimal:2',
            'stock_quantity' => 'decimal:3',
            'is_default' => 'boolean',
            'is_active' => 'boolean',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function barcodes(): HasMany
    {
        return $this->hasMany(Barcode::class)->orderBy('id');
    }

    public function movements(): HasMany
    {
        return $this->hasMany(StockMovement::class);
    }
}
