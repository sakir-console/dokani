<?php

namespace App\Http\Requests\Api\V1;

use Illuminate\Foundation\Http\FormRequest;

class ChangePasswordRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'current_password' => ['required', 'string', 'max:72'],
            'password' => ['required', 'string', 'min:'.config('dokani.password_min_length'), 'max:72', 'different:current_password'],
        ];
    }
}
