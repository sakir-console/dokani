<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\BrandResource;
use App\Models\Brand;
use App\Models\Product;
use App\Services\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class BrandController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        return BrandResource::collection(
            Brand::query()
                ->when($request->filled('q'), fn ($q) => $q->where('name', 'like', '%'.addcslashes($request->string('q')->toString(), '%_\\').'%'))
                ->orderBy('name')->get()
        );
    }

    public function store(Request $request, TenantContext $tenant): JsonResponse
    {
        $brand = Brand::create($this->validated($request, $tenant));

        return (new BrandResource($brand))->response()->setStatusCode(201);
    }

    public function update(Request $request, Brand $brand, TenantContext $tenant): BrandResource
    {
        $brand->update($this->validated($request, $tenant, $brand));

        return new BrandResource($brand);
    }

    public function destroy(Brand $brand): JsonResponse
    {
        DB::transaction(function () use ($brand) {
            // Products keep existing; they simply have no brand afterwards.
            Product::query()->where('brand_id', $brand->id)->update(['brand_id' => null]);
            $brand->delete();
        });

        return response()->json(null, 204);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, TenantContext $tenant, ?Brand $brand = null): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:100',
                Rule::unique('brands', 'name')->where('shop_id', $tenant->id())->whereNull('deleted_at')->ignore($brand?->id)],
        ]);
    }
}
