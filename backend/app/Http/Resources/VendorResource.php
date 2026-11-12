<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class VendorResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'phone' => $this->phone,
            'company_name' => $this->company_name,
            'address' => $this->address,
            'notes' => $this->notes,
            'products_count' => $this->whenCounted('products'),
        ];
    }
}
