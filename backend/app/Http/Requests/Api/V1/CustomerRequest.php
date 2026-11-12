<?php

namespace App\Http\Requests\Api\V1;

use App\Rules\BangladeshPhone;
use App\Services\Tenancy\TenantContext;
use App\Support\Phone;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class CustomerRequest extends FormRequest
{
    protected function prepareForValidation(): void
    {
        if (is_string($this->phone) && ($normalized = Phone::normalize($this->phone)) !== null) {
            $this->merge(['phone' => $normalized]);
        }
    }

    public function rules(): array
    {
        $creating = $this->isMethod('POST');
        $required = $creating ? 'required' : 'sometimes';

        return [
            'name' => [$required, 'string', 'max:120'],
            'phone' => [$required, 'string', new BangladeshPhone,
                // On update, the number must not belong to another customer of this shop.
                ...($creating ? [] : [Rule::unique('customers', 'phone')
                    ->where('shop_id', app(TenantContext::class)->id())->ignore($this->route('customer')?->id)]),
            ],
            'address' => ['sometimes', 'nullable', 'string', 'max:255'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
            'credit_limit' => ['sometimes', 'nullable', ...ProductRequest::MONEY],
            // Only when creating: what the customer already owed before using the app.
            ...($creating ? ['opening_due' => ['sometimes', 'nullable', ...ProductRequest::MONEY]] : []),
        ];
    }
}
