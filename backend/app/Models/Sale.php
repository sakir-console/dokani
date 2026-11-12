<?php

namespace App\Models;

use App\Enums\SaleStatus;
use App\Models\Concerns\BelongsToShop;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

/**
 * Written once by CreateSale. Afterwards only its status changes (VoidSale).
 */
class Sale extends Model
{
    use BelongsToShop;

    protected $attributes = [
        'status' => 'completed', 'source' => 'online', 'has_stock_conflict' => false,
        'discount_amount' => '0.00', 'additional_charge' => '0.00', 'change_amount' => '0.00',
    ];

    // Nothing is mass-assignable: every column is set explicitly by the sale services.
    protected $guarded = ['*'];

    protected function casts(): array
    {
        return [
            'status' => SaleStatus::class,
            'subtotal' => 'decimal:2',
            'discount_amount' => 'decimal:2',
            'additional_charge' => 'decimal:2',
            'grand_total' => 'decimal:2',
            'paid_amount' => 'decimal:2',
            'due_amount' => 'decimal:2',
            'change_amount' => 'decimal:2',
            'total_cost' => 'decimal:2',
            'total_items' => 'decimal:3',
            'has_stock_conflict' => 'boolean',
            'sold_at' => 'datetime',
            'received_at' => 'datetime',
            'voided_at' => 'datetime',
        ];
    }

    public function items(): HasMany
    {
        return $this->hasMany(SaleItem::class)->orderBy('id');
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class)->orderBy('id');
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class)->withTrashed();
    }

    public function invoice(): HasOne
    {
        return $this->hasOne(Invoice::class);
    }

    public function isVoided(): bool
    {
        return $this->status === SaleStatus::Voided;
    }
}
