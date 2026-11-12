<?php

namespace App\Http\Requests\Api\V1;

use App\Rules\BangladeshPhone;
use App\Support\Phone;
use Illuminate\Foundation\Http\FormRequest;

class VendorRequest extends FormRequest
{
    protected function prepareForValidation(): void
    {
        if (is_string($this->phone) && ($normalized = Phone::normalize($this->phone)) !== null) {
            $this->merge(['phone' => $normalized]);
        } elseif ($this->phone === '') {
            $this->merge(['phone' => null]);
        }
    }

    public function rules(): array
    {
        return [
            'name' => [$this->isMethod('POST') ? 'required' : 'sometimes', 'string', 'max:120'],
            'phone' => ['sometimes', 'nullable', 'string', new BangladeshPhone],
            'company_name' => ['sometimes', 'nullable', 'string', 'max:150'],
            'address' => ['sometimes', 'nullable', 'string', 'max:255'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
        ];
    }
}
