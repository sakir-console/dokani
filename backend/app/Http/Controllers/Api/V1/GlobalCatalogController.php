<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\ImportGlobalProductRequest;
use App\Http\Resources\GlobalProductResource;
use App\Http\Resources\ProductResource;
use App\Models\GlobalCategory;
use App\Models\GlobalProduct;
use App\Models\Product;
use App\Services\Catalog\GlobalCatalogImporter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * The shared product catalogue. Global rows are not shop-owned, so they are
 * the same for every shop; importing creates a shop-owned copy.
 */
class GlobalCatalogController extends Controller
{
    public function categories(): JsonResponse
    {
        return response()->json(['data' => GlobalCategory::query()
            ->orderBy('sort_order')->orderBy('name')
            ->get(['id', 'name', 'name_bn'])]);
    }

    public function products(Request $request): AnonymousResourceCollection
    {
        $term = trim($request->string('q')->toString());
        $like = '%'.addcslashes($term, '%_\\').'%';

        $products = GlobalProduct::query()
            ->where('is_active', true)
            ->with(['variants', 'category'])
            ->when($term !== '', fn ($q) => $q->where(fn ($q) => $q
                ->where('name', 'like', $like)->orWhere('name_bn', 'like', $like)
                ->orWhere('brand', 'like', $like)->orWhere('barcode', $term)))
            ->when($request->filled('category_id'), fn ($q) => $q->where('global_category_id', $request->integer('category_id')))
            ->orderBy('name')
            ->paginate(min($request->integer('per_page', 30), 100));

        // Scoped to the current shop by Product's tenant scope.
        $imported = Product::query()
            ->whereIn('global_product_id', $products->pluck('id'))
            ->pluck('global_product_id')->flip();

        $products->each(fn (GlobalProduct $p) => $p->setAttribute('already_imported', $imported->has($p->id)));

        return GlobalProductResource::collection($products);
    }

    public function import(ImportGlobalProductRequest $request, int $globalProduct, GlobalCatalogImporter $importer): JsonResponse
    {
        $global = GlobalProduct::query()->where('is_active', true)->findOrFail($globalProduct);
        $product = $importer->import($global, $request->validated(), $request->user());

        return (new ProductResource($product->load(['variants.barcodes', 'category', 'brand', 'unit', 'vendor'])))
            ->response()->setStatusCode(201);
    }
}
