<?php

namespace App\Models;

use App\Models\Concerns\BelongsToShop;
use Illuminate\Database\Eloquent\Model;

class ShopNotification extends Model
{
    use BelongsToShop;

    protected $fillable = ['type', 'title', 'body', 'data'];

    protected function casts(): array
    {
        return ['data' => 'array', 'read_at' => 'datetime'];
    }
}
