<?php

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;
use Illuminate\Database\Eloquent\Model;

/**
 * The given id must be a row of this model that belongs to the current shop.
 * Relies on the model's tenant scope, so another shop's id fails exactly
 * like an id that does not exist.
 */
class ExistsInShop implements ValidationRule
{
    /** @param class-string<Model> $model */
    public function __construct(private readonly string $model) {}

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (! is_numeric($value) || ! $this->model::query()->whereKey((int) $value)->exists()) {
            $fail(__('validation.exists', ['attribute' => str_replace('_', ' ', $attribute)]));
        }
    }
}
