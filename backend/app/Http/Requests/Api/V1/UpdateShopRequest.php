<?php

namespace App\Http\Requests\Api\V1;

use App\Enums\ShopType;
use App\Rules\BangladeshPhone;
use App\Support\Phone;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateShopRequest extends FormRequest
{
    protected function prepareForValidation(): void
    {
        if (is_string($this->phone) && ($normalized = Phone::normalize($this->phone)) !== null) {
            $this->merge(['phone' => $normalized]);
        }
    }

    public function rules(): array
    {
        return [
            'name' => ['sometimes', 'required', 'string', 'max:150'],
            'shop_type' => ['sometimes', 'required', Rule::enum(ShopType::class)],
            'phone' => ['sometimes', 'required', 'string', new BangladeshPhone],
            'address' => ['sometimes', 'nullable', 'string', 'max:255'],
        ];
    }
}
