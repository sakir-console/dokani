<?php

namespace App\Models;

use App\Models\Concerns\BelongsToShop;
use Database\Factories\CustomerFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * current_due, total_purchases and total_paid are not fillable: they change
 * only through LedgerService and the sale services, in the same transaction
 * as the rows they summarise.
 */
class Customer extends Model
{
    /** @use HasFactory<CustomerFactory> */
    use BelongsToShop, HasFactory, SoftDeletes;

    protected $attributes = ['current_due' => '0.00', 'total_purchases' => '0.00', 'total_paid' => '0.00'];

    protected $fillable = ['name', 'phone', 'address', 'notes', 'credit_limit'];

    protected function casts(): array
    {
        return [
            'credit_limit' => 'decimal:2',
            'current_due' => 'decimal:2',
            'total_purchases' => 'decimal:2',
            'total_paid' => 'decimal:2',
            'last_purchase_at' => 'datetime',
        ];
    }

    public function ledger(): HasMany
    {
        return $this->hasMany(CustomerLedger::class);
    }

    public function sales(): HasMany
    {
        return $this->hasMany(Sale::class);
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class);
    }
}
