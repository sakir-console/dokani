<?php

namespace App\Models;

use App\Enums\LedgerType;
use App\Models\Concerns\BelongsToShop;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use LogicException;

/**
 * Append-only. Written by LedgerService.
 */
class CustomerLedger extends Model
{
    use BelongsToShop;

    public const UPDATED_AT = null;

    protected $attributes = ['debit' => '0.00', 'credit' => '0.00'];

    protected $guarded = ['*'];

    protected function casts(): array
    {
        return [
            'type' => LedgerType::class,
            'debit' => 'decimal:2',
            'credit' => 'decimal:2',
            'balance_after' => 'decimal:2',
            'created_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::updating(fn () => throw new LogicException('Ledger entries are append-only.'));
        static::deleting(fn () => throw new LogicException('Ledger entries are append-only.'));
    }

    public function sale(): BelongsTo
    {
        return $this->belongsTo(Sale::class);
    }

    public function payment(): BelongsTo
    {
        return $this->belongsTo(Payment::class);
    }
}
