<?php

namespace App\Http\Resources;

use App\Services\Tenancy\TenantContext;
use App\Support\Dec;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Expects customer and invoice to be loaded; items and payments when present.
 */
class SaleResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        // Cost and profit are the owner's figures; a cashier's token does not get them.
        $seesProfit = app(TenantContext::class)->membership()?->role->can('reports.view') ?? false;

        return [
            'id' => $this->id,
            'client_uuid' => $this->client_uuid,
            'invoice_no' => $this->invoice_no,
            'status' => $this->status->value,
            // 'offline' when it was recorded on a phone without a connection and synced later.
            'source' => $this->source,
            'offline_ref' => $this->offline_ref,
            'has_stock_conflict' => $this->has_stock_conflict,
            'sold_at' => $this->sold_at->toIso8601String(),
            'subtotal' => $this->subtotal,
            'discount_amount' => $this->discount_amount,
            'additional_charge' => $this->additional_charge,
            'grand_total' => $this->grand_total,
            'paid_amount' => $this->paid_amount,
            'due_amount' => $this->due_amount,
            'change_amount' => $this->change_amount,
            'total_items' => $this->total_items,
            'note' => $this->note,
            'void_reason' => $this->void_reason,
            'voided_at' => $this->voided_at?->toIso8601String(),
            $this->mergeWhen($seesProfit, fn () => [
                'total_cost' => $this->total_cost,
                'gross_profit' => Dec::money(Dec::of($this->subtotal)->minus($this->discount_amount)->minus($this->total_cost)),
            ]),
            'customer' => $this->customer ? [
                'id' => $this->customer->id,
                'name' => $this->customer->name,
                'phone' => $this->customer->phone,
                'current_due' => $this->customer->current_due,
            ] : null,
            'items' => $this->whenLoaded('items', fn () => $this->items->map(fn ($item) => [
                'id' => $item->id,
                'product_id' => $item->product_id,
                'variant_id' => $item->product_variant_id,
                'product_name' => $item->product_name,
                'variant_name' => $item->variant_name,
                'unit_name' => $item->unit_name,
                'quantity' => $item->quantity,
                'unit_price' => $item->unit_price,
                'discount_amount' => $item->discount_amount,
                'line_total' => $item->line_total,
            ])),
            'payments' => PaymentResource::collection($this->whenLoaded('payments')),
            // The link behind the receipt's QR code.
            'invoice_url' => $this->invoice?->publicUrl(),
        ];
    }
}
