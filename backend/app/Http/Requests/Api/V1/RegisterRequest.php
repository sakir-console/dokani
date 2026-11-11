<?php

namespace App\Http\Requests\Api\V1;

use App\Enums\ShopType;
use App\Rules\BangladeshPhone;
use App\Support\Phone;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class RegisterRequest extends FormRequest
{
    protected function prepareForValidation(): void
    {
        // Compare and store the canonical form so 017… and +88017… are one account.
        if (is_string($this->phone) && ($normalized = Phone::normalize($this->phone)) !== null) {
            $this->merge(['phone' => $normalized]);
        }
    }

    public function rules(): array
    {
        return [
            'shop_name' => ['required', 'string', 'max:150'],
            'owner_name' => ['required', 'string', 'max:120'],
            'phone' => ['required', 'string', new BangladeshPhone, Rule::unique('users', 'phone')],
            'password' => ['required', 'string', 'min:'.config('dokani.password_min_length'), 'max:72'],
            'shop_type' => ['required', Rule::enum(ShopType::class)],
            'address' => ['nullable', 'string', 'max:255'],
            'locale' => ['nullable', Rule::in(['bn', 'en'])],
            'logo' => ['nullable', 'file', 'mimes:jpg,jpeg,png,webp', 'max:'.config('dokani.uploads.logo_max_kb')],
            'device_name' => ['required', 'string', 'max:100'],
        ];
    }
}
