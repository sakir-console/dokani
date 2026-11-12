<?php

namespace App\Services\Sales;

use App\Enums\PaymentType;
use App\Models\Sale;
use App\Models\Shop;
use App\Support\Phone;
use Illuminate\Support\Facades\Storage;

/**
 * Everything an invoice shows, in one array — used by the public page, the
 * PDF and the public JSON endpoint, so all three always agree.
 *
 * Deliberately contains no internal ids and never the customer's full phone.
 */
class InvoicePresenter
{
    /** @return array<string, mixed> */
    public function present(Sale $sale): array
    {
        $sale->loadMissing(['items', 'payments', 'customer', 'invoice']);

        $snapshot = $sale->invoice->shop_snapshot;
        $shop = Shop::query()->withTrashed()->find($sale->shop_id);
        $timezone = $shop?->timezone ?? 'Asia/Dhaka';
        $logo = $snapshot['logo_path'] ?? null;

        return [
            'shop' => [
                'name' => $snapshot['name'],
                'address' => $snapshot['address'] ?? null,
                'phone' => $snapshot['phone'] ?? null,
                'logo_url' => $logo && Storage::disk('public')->exists($logo) ? Storage::disk('public')->url($logo) : null,
                'footer' => $snapshot['footer'] ?? null,
            ],
            'invoice_no' => $sale->invoice_no,
            'status' => $sale->status->value,
            'sold_at' => $sale->sold_at->copy()->timezone($timezone),
            'customer' => $sale->customer ? [
                'name' => $sale->customer->name,
                'phone_masked' => Phone::mask($sale->customer->phone),
            ] : null,
            'items' => $sale->items->map(fn ($item) => [
                'name' => trim($item->product_name.($item->variant_name ? ' — '.$item->variant_name : '')),
                'unit' => $item->unit_name,
                'quantity' => rtrim(rtrim($item->quantity, '0'), '.'),
                'unit_price' => $item->unit_price,
                'discount_amount' => $item->discount_amount,
                'line_total' => $item->line_total,
            ])->all(),
            'subtotal' => $sale->subtotal,
            'discount_amount' => $sale->discount_amount,
            'additional_charge' => $sale->additional_charge,
            'grand_total' => $sale->grand_total,
            'paid_amount' => $sale->paid_amount,
            'due_amount' => $sale->due_amount,
            'change_amount' => $sale->change_amount,
            'payments' => $sale->payments->where('type', PaymentType::Sale)->map(fn ($payment) => [
                'method' => $payment->method->value,
                'label' => $payment->method->label(),
                'amount' => $payment->amount,
            ])->values()->all(),
            'url' => $sale->invoice->publicUrl(),
        ];
    }
}
