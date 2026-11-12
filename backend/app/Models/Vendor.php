<?php

namespace App\Models;

use App\Models\Concerns\BelongsToShop;
use Database\Factories\VendorFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Vendor extends Model
{
    /** @use HasFactory<VendorFactory> */
    use BelongsToShop, HasFactory, SoftDeletes;

    protected $fillable = ['name', 'phone', 'company_name', 'address', 'notes'];

    public function products(): HasMany
    {
        return $this->hasMany(Product::class);
    }
}
