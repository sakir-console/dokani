<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class LedgerEntryResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'type' => $this->type->value,
            'debit' => $this->debit,
            'credit' => $this->credit,
            'balance_after' => $this->balance_after,
            'note' => $this->note,
            'created_at' => $this->created_at?->toIso8601String(),
            'sale_id' => $this->sale_id,
            'invoice_no' => $this->whenLoaded('sale', fn () => $this->sale?->invoice_no),
            'payment_method' => $this->whenLoaded('payment', fn () => $this->payment?->method->value),
        ];
    }
}
