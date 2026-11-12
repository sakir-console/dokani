<?php

namespace App\Models;

use App\Models\Concerns\BelongsToShop;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Invoice extends Model
{
    use BelongsToShop;

    protected $guarded = ['*'];

    protected $hidden = ['public_token'];

    protected function casts(): array
    {
        return ['shop_snapshot' => 'array', 'issued_at' => 'datetime'];
    }

    public function sale(): BelongsTo
    {
        return $this->belongsTo(Sale::class);
    }

    /** The link printed as a QR code. Whoever has it can read this one invoice. */
    public function publicUrl(): string
    {
        return url('/i/'.$this->public_token);
    }
}
