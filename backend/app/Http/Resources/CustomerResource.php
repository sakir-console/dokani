<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class CustomerResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'phone' => $this->phone,
            'address' => $this->address,
            'notes' => $this->notes,
            'credit_limit' => $this->credit_limit,
            'current_due' => $this->current_due,
            'total_purchases' => $this->total_purchases,
            'total_paid' => $this->total_paid,
            'last_purchase_at' => $this->last_purchase_at?->toIso8601String(),
        ];
    }
}
