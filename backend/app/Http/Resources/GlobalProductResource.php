<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class GlobalProductResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'name_bn' => $this->name_bn,
            'brand' => $this->brand,
            'description' => $this->description,
            'default_unit' => $this->default_unit,
            'barcode' => $this->barcode,
            'image_url' => $this->imageUrl(),
            'category' => $this->category ? [
                'id' => $this->category->id, 'name' => $this->category->name, 'name_bn' => $this->category->name_bn,
            ] : null,
            'variants' => $this->variants->map(fn ($variant) => [
                'id' => $variant->id,
                'name' => $variant->name,
                'attributes' => $variant->options,
                'barcode' => $variant->barcode,
            ]),
            // Lets the app show "already in your shop" instead of importing twice.
            'already_imported' => (bool) ($this->already_imported ?? false),
        ];
    }
}
