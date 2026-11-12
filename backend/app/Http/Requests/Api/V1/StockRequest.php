<?php

namespace App\Http\Requests\Api\V1;

use App\Models\ProductVariant;
use App\Models\Vendor;
use App\Rules\ExistsInShop;
use Illuminate\Foundation\Http\FormRequest;

/** Shared by stock in, stock out and adjust; the route decides which fields matter. */
class StockRequest extends FormRequest
{
    public function rules(): array
    {
        $action = $this->route()->getActionMethod();
        $positive = ['required', 'numeric', 'decimal:0,3', 'gt:0', 'max:999999999.999'];

        return [
            'variant_id' => ['required', 'integer', new ExistsInShop(ProductVariant::class)],
            ...match ($action) {
                'stockIn' => [
                    'quantity' => $positive,
                    'unit_cost' => ['sometimes', 'nullable', ...ProductRequest::MONEY],
                    'vendor_id' => ['sometimes', 'nullable', 'integer', new ExistsInShop(Vendor::class)],
                    'note' => ['sometimes', 'nullable', 'string', 'max:255'],
                ],
                'stockOut' => [
                    'quantity' => $positive,
                    // A reason is mandatory when stock leaves without a sale.
                    'note' => ['required', 'string', 'max:255'],
                ],
                default => [
                    'new_quantity' => ['required', ...ProductRequest::QUANTITY],
                    'note' => ['sometimes', 'nullable', 'string', 'max:255'],
                ],
            },
        ];
    }
}
