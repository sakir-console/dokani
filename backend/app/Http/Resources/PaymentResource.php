<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PaymentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'type' => $this->type->value,
            'method' => $this->method->value,
            'amount' => $this->amount,
            'received_amount' => $this->received_amount,
            'transaction_id' => $this->transaction_id,
            'reference' => $this->reference,
            // "unverified" = entered by hand. The app must not present it as confirmed by bKash/Nagad.
            'verification' => $this->verification,
            'paid_at' => $this->paid_at?->toIso8601String(),
            'sale_id' => $this->sale_id,
            'invoice_no' => $this->whenLoaded('sale', fn () => $this->sale?->invoice_no),
        ];
    }
}
