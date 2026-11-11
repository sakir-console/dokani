<?php

namespace App\Http\Requests\Api\V1;

use App\Rules\BangladeshPhone;
use Illuminate\Foundation\Http\FormRequest;

class ForgotPasswordRequest extends FormRequest
{
    public function rules(): array
    {
        return ['phone' => ['required', 'string', new BangladeshPhone]];
    }
}
