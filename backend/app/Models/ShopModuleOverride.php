<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ShopModuleOverride extends Model
{
    protected $fillable = ['shop_id', 'module_id', 'is_enabled', 'admin_id'];

    protected function casts(): array
    {
        return ['is_enabled' => 'boolean'];
    }

    public function module(): BelongsTo
    {
        return $this->belongsTo(Module::class);
    }
}
