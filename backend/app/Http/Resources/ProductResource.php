<?php

namespace App\Http\Resources;

use App\Services\Tenancy\TenantContext;
use App\Support\Dec;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Expects: variants.barcodes, category, brand, unit, vendor to be loaded.
 */
class ProductResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $threshold = Dec::qty($this->low_stock_threshold
            ?? app(TenantContext::class)->shop()->resolvedSettings()['low_stock_threshold']);

        $variants = $this->variants->map(function ($variant) use ($threshold) {
            $resource = new VariantResource($variant);
            $resource->lowStockThreshold = $threshold;

            return $resource;
        });

        $total = $this->variants->reduce(fn ($sum, $v) => $sum->plus(Dec::of($v->stock_quantity)), Dec::of(0));
        $statuses = $variants->map(fn (VariantResource $v) => $v->toArray($request)['stock_status']);

        return [
            'id' => $this->id,
            'name' => $this->name,
            'description' => $this->description,
            'image_url' => $this->imageUrl(),
            'storage_location' => $this->storage_location,
            'has_variants' => $this->has_variants,
            'is_active' => $this->is_active,
            'low_stock_threshold' => $this->low_stock_threshold,
            'effective_low_stock_threshold' => $threshold,
            'category' => $this->category ? ['id' => $this->category->id, 'name' => $this->category->name] : null,
            'brand' => $this->brand ? ['id' => $this->brand->id, 'name' => $this->brand->name] : null,
            'unit' => new UnitResource($this->unit),
            'vendor' => $this->vendor ? ['id' => $this->vendor->id, 'name' => $this->vendor->name] : null,
            'total_stock' => Dec::qty($total),
            'low_stock_variants' => $statuses->filter(fn ($s) => $s === 'low')->count(),
            'out_of_stock_variants' => $statuses->filter(fn ($s) => $s === 'out')->count(),
            'variants' => $variants,
            'from_global_catalog' => $this->global_product_id !== null,
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}
