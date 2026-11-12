<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class GlobalProductVariant extends Model
{
    protected $attributes = ['sort_order' => 0];

    protected $fillable = ['name', 'options', 'barcode', 'sort_order'];

    protected function casts(): array
    {
        return ['options' => 'array'];
    }
}
