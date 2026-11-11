<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

class Module extends Model
{
    // Mirrors the column defaults, so a freshly created model is complete without a reload.
    protected $attributes = ['is_core' => false, 'is_available' => true, 'sort_order' => 0];

    protected $fillable = ['key', 'name', 'description', 'is_core', 'is_available', 'sort_order'];

    protected function casts(): array
    {
        return ['is_core' => 'boolean', 'is_available' => 'boolean'];
    }

    public function plans(): BelongsToMany
    {
        return $this->belongsToMany(Plan::class, 'plan_module');
    }
}
