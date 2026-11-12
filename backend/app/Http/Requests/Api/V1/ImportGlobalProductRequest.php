<?php

namespace App\Http\Requests\Api\V1;

use App\Models\Vendor;
use App\Rules\ExistsInShop;
use Illuminate\Foundation\Http\FormRequest;

class ImportGlobalProductRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'purchase_price' => ['sometimes', 'nullable', ...ProductRequest::MONEY],
            'selling_price' => ['sometimes', 'nullable', ...ProductRequest::MONEY],
            'stock_quantity' => ['sometimes', 'nullable', ...ProductRequest::QUANTITY],
            'vendor_id' => ['sometimes', 'nullable', 'integer', new ExistsInShop(Vendor::class)],
            'variants' => ['sometimes', 'array', 'max:100'],
            'variants.*.global_variant_id' => ['required', 'integer'],
            'variants.*.purchase_price' => ['sometimes', 'nullable', ...ProductRequest::MONEY],
            'variants.*.selling_price' => ['sometimes', 'nullable', ...ProductRequest::MONEY],
            'variants.*.stock_quantity' => ['sometimes', 'nullable', ...ProductRequest::QUANTITY],
        ];
    }
}
