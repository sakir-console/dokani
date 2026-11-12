<?php

namespace App\Http\Resources;

use App\Support\Dec;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class VariantResource extends JsonResource
{
    /** Threshold in force for this variant's product; set by ProductResource. */
    public ?string $lowStockThreshold = null;

    public function toArray(Request $request): array
    {
        $stock = Dec::of($this->stock_quantity);

        return [
            'id' => $this->id,
            'name' => $this->name,
            'attributes' => $this->options,
            'sku' => $this->sku,
            'purchase_price' => $this->purchase_price,
            'selling_price' => $this->selling_price,
            'stock_quantity' => $this->stock_quantity,
            'stock_status' => match (true) {
                $stock->isNegativeOrZero() => 'out',
                $this->lowStockThreshold !== null && $stock->isLessThanOrEqualTo($this->lowStockThreshold) => 'low',
                default => 'in',
            },
            'is_default' => $this->is_default,
            'barcodes' => $this->barcodes->pluck('code')->all(),
        ];
    }
}
