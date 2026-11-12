<?php

namespace App\Http\Controllers\Api\V1;

use App\Exceptions\ApiException;
use App\Http\Controllers\Controller;
use App\Http\Resources\ProductResource;
use App\Models\Barcode;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class BarcodeController extends Controller
{
    /**
     * Resolve a scanned code to the exact variant it belongs to, in this shop.
     * A code that exists only in another shop is "not found".
     */
    public function lookup(Request $request): JsonResponse
    {
        $data = $request->validate(['code' => ['required', 'string', 'max:64']]);

        $barcode = Barcode::query()
            ->where('code', trim($data['code']))
            ->with(['variant.product' => fn ($q) => $q->with(['variants.barcodes', 'category', 'brand', 'unit', 'vendor'])])
            ->first();

        if ($barcode === null || $barcode->variant === null || $barcode->variant->product === null) {
            throw new ApiException('BARCODE_NOT_FOUND', __('No product has this barcode.'), 404);
        }

        return response()->json(['data' => [
            'code' => $barcode->code,
            'variant_id' => $barcode->product_variant_id,
            'product' => (new ProductResource($barcode->variant->product))->resolve($request),
        ]]);
    }
}
