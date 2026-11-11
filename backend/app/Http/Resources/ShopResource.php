<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ShopResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'shop_type' => $this->shop_type->value,
            'phone' => $this->phone,
            'address' => $this->address,
            'logo_url' => $this->logoUrl(),
            'status' => $this->status->value,
            'currency' => $this->currency,
            'timezone' => $this->timezone,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
