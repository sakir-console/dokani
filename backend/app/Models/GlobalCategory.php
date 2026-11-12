<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class GlobalCategory extends Model
{
    protected $attributes = ['sort_order' => 0];

    protected $fillable = ['name', 'name_bn', 'sort_order'];

    public function products(): HasMany
    {
        return $this->hasMany(GlobalProduct::class);
    }
}
