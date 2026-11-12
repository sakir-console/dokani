<?php

namespace App\Http\Requests\Api\V1;

use App\Models\Brand;
use App\Models\Category;
use App\Models\Unit;
use App\Models\Vendor;
use App\Rules\ExistsInShop;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Shape and type checks for creating or updating a product.
 * Structural rules (variant names, barcode ownership, plan limit) live in ProductService.
 */
class ProductRequest extends FormRequest
{
    public const MONEY = ['numeric', 'decimal:0,2', 'min:0', 'max:999999999.99'];

    public const QUANTITY = ['numeric', 'decimal:0,3', 'min:0', 'max:999999999.999'];

    public function rules(): array
    {
        $creating = $this->isMethod('POST');
        $required = $creating ? 'required' : 'sometimes';

        return [
            'name' => [$required, 'string', 'max:190'],
            'category_id' => ['sometimes', 'nullable', 'integer', new ExistsInShop(Category::class)],
            'brand_id' => ['sometimes', 'nullable', 'integer', new ExistsInShop(Brand::class)],
            'unit_id' => [$required, 'integer', new ExistsInShop(Unit::class)],
            'vendor_id' => ['sometimes', 'nullable', 'integer', new ExistsInShop(Vendor::class)],
            'description' => ['sometimes', 'nullable', 'string', 'max:2000'],
            'storage_location' => ['sometimes', 'nullable', 'string', 'max:100'],
            'low_stock_threshold' => ['sometimes', 'nullable', ...self::QUANTITY],
            'has_variants' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],

            'variants' => [$required, 'array', 'min:1', 'max:100'],
            'variants.*' => ['array'],
            'variants.*.id' => ['sometimes', 'nullable', 'integer'],
            'variants.*.name' => ['sometimes', 'nullable', 'string', 'max:120'],
            'variants.*.attributes' => ['sometimes', 'nullable', 'array', 'max:10'],
            'variants.*.attributes.*' => ['string', 'max:60'],
            'variants.*.sku' => ['sometimes', 'nullable', 'string', 'max:64'],
            'variants.*.purchase_price' => ['required', ...self::MONEY],
            'variants.*.selling_price' => ['required', ...self::MONEY],
            // Opening stock. Only applied to variants being created.
            'variants.*.stock_quantity' => ['sometimes', 'nullable', ...self::QUANTITY],
            'variants.*.barcodes' => ['sometimes', 'nullable', 'array', 'max:10'],
            'variants.*.barcodes.*' => ['string', 'max:64', 'regex:/^[^\x00-\x1F\x7F]+$/'],
        ];
    }
}
