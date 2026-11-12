<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\StockMovementType;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\VendorRequest;
use App\Http\Resources\ProductResource;
use App\Http\Resources\StockMovementResource;
use App\Http\Resources\VendorResource;
use App\Models\Product;
use App\Models\StockMovement;
use App\Models\Vendor;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;

class VendorController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $term = trim($request->string('q')->toString());
        $like = '%'.addcslashes($term, '%_\\').'%';

        $vendors = Vendor::query()
            ->withCount('products')
            ->when($term !== '', fn ($q) => $q->where(fn ($q) => $q
                ->where('name', 'like', $like)->orWhere('phone', 'like', $like)->orWhere('company_name', 'like', $like)))
            ->orderBy('name')
            ->paginate(min($request->integer('per_page', 30), 100));

        return VendorResource::collection($vendors);
    }

    public function store(VendorRequest $request): JsonResponse
    {
        $vendor = Vendor::create($request->validated());

        return (new VendorResource($vendor))->response()->setStatusCode(201);
    }

    public function show(Vendor $vendor): VendorResource
    {
        return new VendorResource($vendor->loadCount('products'));
    }

    public function update(VendorRequest $request, Vendor $vendor): VendorResource
    {
        $vendor->update($request->validated());

        return new VendorResource($vendor);
    }

    public function destroy(Vendor $vendor): JsonResponse
    {
        DB::transaction(function () use ($vendor) {
            // Products stay; they are just no longer linked to a vendor.
            Product::query()->where('vendor_id', $vendor->id)->update(['vendor_id' => null]);
            $vendor->delete();
        });

        return response()->json(null, 204);
    }

    public function products(Request $request, Vendor $vendor): AnonymousResourceCollection
    {
        return ProductResource::collection(
            Product::query()->where('vendor_id', $vendor->id)
                ->with(['variants.barcodes', 'category', 'brand', 'unit', 'vendor'])
                ->orderBy('name')
                ->paginate(min($request->integer('per_page', 30), 100))
        );
    }

    /** Goods received from this vendor (stock-in entries that named the vendor), newest first. */
    public function purchases(Request $request, Vendor $vendor): AnonymousResourceCollection
    {
        return StockMovementResource::collection(
            StockMovement::query()
                ->where('vendor_id', $vendor->id)
                ->where('type', StockMovementType::StockIn)
                ->with(['variant.product'])
                ->latest('id')
                ->paginate(min($request->integer('per_page', 30), 100))
        );
    }
}
