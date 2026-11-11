<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\ShopType;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;

class MetaController extends Controller
{
    /** Public reference data the app needs before anyone is logged in. */
    public function __invoke(): JsonResponse
    {
        return response()->json(['data' => [
            'api_version' => 'v1',
            'min_app_version' => config('dokani.app.min_version'),
            'password_min_length' => config('dokani.password_min_length'),
            'otp_length' => config('dokani.otp.length'),
            'shop_types' => array_map(fn (ShopType $type) => [
                'value' => $type->value,
                'label_en' => $type->label(),
                'label_bn' => $type->labelBn(),
            ], ShopType::cases()),
        ]]);
    }
}
