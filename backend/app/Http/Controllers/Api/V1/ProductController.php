<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\ProductRequest;
use App\Http\Resources\ProductResource;
use App\Models\Product;
use App\Services\Catalog\ProductService;
use App\Services\Media\ImageStore;
use App\Services\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class ProductController extends Controller
{
    private const RELATIONS = ['variants.barcodes', 'category', 'brand', 'unit', 'vendor'];

    public function index(Request $request, TenantContext $tenant): AnonymousResourceCollection
    {
        $term = trim($request->string('q')->toString());
        $like = '%'.addcslashes($term, '%_\\').'%';
        $defaultThreshold = $tenant->shop()->resolvedSettings()['low_stock_threshold'];

        // A variant is low when it has some stock but no more than the product's
        // threshold (or the shop's default); out when it has none.
        $stockFilter = fn (string $state) => function (Builder $q) use ($state, $defaultThreshold) {
            $q->join('products as p', 'p.id', '=', 'product_variants.product_id');
            $state === 'out'
                ? $q->where('product_variants.stock_quantity', '<=', 0)
                : $q->where('product_variants.stock_quantity', '>', 0)
                    ->whereRaw('product_variants.stock_quantity <= coalesce(p.low_stock_threshold, ?)', [$defaultThreshold]);
        };

        $products = Product::query()
            ->with(self::RELATIONS)
            ->when($term !== '', fn ($q) => $q->where(fn ($q) => $q
                ->where('products.name', 'like', $like)
                // An exact barcode or SKU also finds the product.
                ->orWhereHas('variants', fn ($v) => $v->where('sku', $term)->orWhereHas('barcodes', fn ($b) => $b->where('code', $term)))))
            ->when($request->filled('category_id'), fn ($q) => $q->where('category_id', $request->integer('category_id')))
            ->when($request->filled('brand_id'), fn ($q) => $q->where('brand_id', $request->integer('brand_id')))
            ->when($request->filled('vendor_id'), fn ($q) => $q->where('vendor_id', $request->integer('vendor_id')))
            ->when(in_array($request->input('stock'), ['low', 'out'], true), fn ($q) => $q->whereHas('variants', $stockFilter($request->input('stock'))))
            ->when($request->input('stock') === 'in', fn ($q) => $q->whereDoesntHave('variants', fn ($v) => $v->where('stock_quantity', '<=', 0)))
            ->orderBy('products.name')
            ->paginate(min($request->integer('per_page', 30), 100));

        return ProductResource::collection($products);
    }

    public function store(ProductRequest $request, ProductService $service): JsonResponse
    {
        $product = $service->create($request->validated(), $request->user());

        return (new ProductResource($product->load(self::RELATIONS)))->response()->setStatusCode(201);
    }

    public function show(Product $product): ProductResource
    {
        return new ProductResource($product->load(self::RELATIONS));
    }

    public function update(ProductRequest $request, Product $product, ProductService $service): ProductResource
    {
        $service->update($product, $request->validated(), $request->user());

        return new ProductResource($product->refresh()->load(self::RELATIONS));
    }

    public function destroy(Product $product, ProductService $service): JsonResponse
    {
        $service->delete($product);

        return response()->json(null, 204);
    }

    public function uploadImage(Request $request, Product $product, ImageStore $images): ProductResource
    {
        $request->validate([
            'image' => ['required', 'file', 'mimes:jpg,jpeg,png,webp', 'max:'.config('dokani.uploads.product_image_max_kb')],
        ]);

        $previous = $product->image_path;
        $product->image_path = $images->store($request->file('image'), "shops/{$product->shop_id}/products", config('dokani.uploads.product_image_max_px'));
        $product->save();
        $images->delete($previous);

        return new ProductResource($product->load(self::RELATIONS));
    }

    public function deleteImage(Product $product, ImageStore $images): ProductResource
    {
        $previous = $product->image_path;
        $product->image_path = null;
        $product->save();
        $images->delete($previous);

        return new ProductResource($product->load(self::RELATIONS));
    }
}
