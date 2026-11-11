<?php

namespace App\Http\Requests\Api\V1;

use App\Rules\BangladeshPhone;
use Illuminate\Foundation\Http\FormRequest;

class ResetPasswordRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'phone' => ['required', 'string', new BangladeshPhone],
            'otp' => ['required', 'string', 'digits:'.config('dokani.otp.length')],
            'password' => ['required', 'string', 'min:'.config('dokani.password_min_length'), 'max:72'],
        ];
    }
}
