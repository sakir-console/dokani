<?php

namespace App\Http\Requests\Api\V1;

use App\Enums\PaymentMethod;
use App\Models\Customer;
use App\Rules\BangladeshPhone;
use App\Rules\ExistsInShop;
use App\Support\Phone;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Shape and types only. Every business rule — prices, stock, totals,
 * payments adding up, the customer requirement for a due — is in CreateSale.
 */
class StoreSaleRequest extends FormRequest
{
    protected function prepareForValidation(): void
    {
        $phone = $this->input('customer.phone');
        if (is_string($phone) && ($normalized = Phone::normalize($phone)) !== null) {
            $this->merge(['customer' => ['phone' => $normalized] + (array) $this->input('customer')]);
        }
    }

    public function rules(): array
    {
        $money = ProductRequest::MONEY;

        return [
            // Generated once per sale by the app; makes retries safe.
            'client_uuid' => ['required', 'uuid'],
            'sold_at' => ['sometimes', 'nullable', 'date'],

            'items' => ['required', 'array', 'min:1', 'max:200'],
            'items.*.variant_id' => ['required', 'integer'],
            'items.*.quantity' => ['required', 'numeric', 'decimal:0,3', 'gt:0', 'max:999999999.999'],
            'items.*.unit_price' => ['sometimes', 'nullable', ...$money],
            'items.*.discount_amount' => ['sometimes', 'nullable', ...$money],

            'discount_amount' => ['sometimes', 'nullable', ...$money],
            'additional_charge' => ['sometimes', 'nullable', ...$money],
            // What the app showed the cashier. Compared with the server's own figures.
            'grand_total' => ['required', ...$money],
            'due_amount' => ['required', ...$money],

            'payments' => ['sometimes', 'array', 'max:10'],
            'payments.*.method' => ['required', Rule::enum(PaymentMethod::class)],
            'payments.*.amount' => ['required', 'numeric', 'decimal:0,2', 'gt:0', 'max:999999999.99'],
            'payments.*.received_amount' => ['sometimes', 'nullable', ...$money],
            'payments.*.transaction_id' => ['sometimes', 'nullable', 'string', 'max:100'],
            'payments.*.reference' => ['sometimes', 'nullable', 'string', 'max:190'],

            'customer_id' => ['sometimes', 'nullable', 'integer', new ExistsInShop(Customer::class)],
            'customer' => ['sometimes', 'nullable', 'array'],
            'customer.phone' => ['required_with:customer', 'string', new BangladeshPhone],
            'customer.name' => ['sometimes', 'nullable', 'string', 'max:120'],

            'note' => ['sometimes', 'nullable', 'string', 'max:255'],
        ];
    }
}
