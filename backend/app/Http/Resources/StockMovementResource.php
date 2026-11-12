<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class StockMovementResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'type' => $this->type->value,
            'quantity' => $this->quantity,
            'balance_after' => $this->balance_after,
            'unit_cost' => $this->unit_cost,
            'note' => $this->note,
            'created_at' => $this->created_at?->toIso8601String(),
            'variant' => $this->whenLoaded('variant', fn () => [
                'id' => $this->variant->id,
                'name' => $this->variant->name,
                'product_id' => $this->variant->product_id,
                'product_name' => $this->variant->product?->name,
            ]),
            'vendor' => $this->whenLoaded('vendor', fn () => $this->vendor ? ['id' => $this->vendor->id, 'name' => $this->vendor->name] : null),
        ];
    }
}
