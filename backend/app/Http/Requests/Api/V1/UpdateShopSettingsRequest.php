<?php

namespace App\Http\Requests\Api\V1;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateShopSettingsRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'allow_negative_stock' => ['sometimes', 'boolean'],
            'low_stock_threshold' => ['sometimes', 'numeric', 'min:0', 'max:100000'],
            'receipt_width' => ['sometimes', Rule::in(['58', '80'])],
            'invoice_footer' => ['sometimes', 'nullable', 'string', 'max:200'],
            'charge_counts_as_income' => ['sometimes', 'boolean'],
        ];
    }
}
