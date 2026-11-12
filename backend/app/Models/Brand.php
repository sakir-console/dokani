<?php

namespace App\Models;

use App\Models\Concerns\BelongsToShop;
use Database\Factories\BrandFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Brand extends Model
{
    /** @use HasFactory<BrandFactory> */
    use BelongsToShop, HasFactory, SoftDeletes;

    protected $fillable = ['name'];
}
