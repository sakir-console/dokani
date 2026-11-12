<?php

namespace App\Models;

use App\Models\Concerns\BelongsToShop;
use Illuminate\Database\Eloquent\Model;

class Device extends Model
{
    use BelongsToShop;

    protected $fillable = ['device_uuid', 'name', 'platform', 'app_version'];

    protected function casts(): array
    {
        return ['last_seen_at' => 'datetime', 'last_synced_at' => 'datetime'];
    }
}
