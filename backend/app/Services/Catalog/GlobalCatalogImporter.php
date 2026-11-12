<?php

namespace App\Services\Catalog;

use App\Models\Barcode;
use App\Models\Brand;
use App\Models\Category;
use App\Models\GlobalProduct;
use App\Models\Product;
use App\Models\Unit;
use App\Models\User;
use App\Services\Media\ImageStore;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

/**
 * Copies a global catalogue product into the current shop.
 *
 * The copy is independent: the shop sets its own prices, stock, vendor and
 * barcodes, and later edits on either side never affect the other.
 */
class GlobalCatalogImporter
{
    public function __construct(private readonly ProductService $products, private readonly ImageStore $images) {}

    /**
     * @param  array{purchase_price?: mixed, selling_price?: mixed, stock_quantity?: mixed, vendor_id?: ?int, variants?: list<array<string, mixed>>}  $data
     */
    public function import(GlobalProduct $global, array $data, ?User $actor): Product
    {
        $global->loadMissing(['variants', 'category']);
        $imagePath = null;

        try {
            return DB::transaction(function () use ($global, $data, $actor, &$imagePath) {
                $hasVariants = $global->variants->isNotEmpty();

                if ($hasVariants) {
                    // Prices can be given per variant (by global variant id) or once for all.
                    $overrides = collect($data['variants'] ?? [])->keyBy('global_variant_id');
                    $variants = $global->variants->map(fn ($variant) => [
                        'name' => $variant->name,
                        'attributes' => $variant->options,
                        'purchase_price' => $overrides[$variant->id]['purchase_price'] ?? $data['purchase_price'] ?? 0,
                        'selling_price' => $overrides[$variant->id]['selling_price'] ?? $data['selling_price'] ?? 0,
                        'stock_quantity' => $overrides[$variant->id]['stock_quantity'] ?? 0,
                        'barcodes' => $this->freeCodes([$variant->barcode]),
                    ])->all();
                } else {
                    $variants = [[
                        'purchase_price' => $data['purchase_price'] ?? 0,
                        'selling_price' => $data['selling_price'] ?? 0,
                        'stock_quantity' => $data['stock_quantity'] ?? 0,
                        'barcodes' => $this->freeCodes([$global->barcode]),
                    ]];
                }

                $product = $this->products->create([
                    'name' => $global->name,
                    'description' => $global->description,
                    'category_id' => $this->categoryId($global),
                    'brand_id' => $this->brandId($global),
                    'unit_id' => $this->unitId($global),
                    'vendor_id' => $data['vendor_id'] ?? null,
                    'has_variants' => $hasVariants,
                    'variants' => $variants,
                ], $actor, $global->id);

                if ($global->image_path && Storage::disk('public')->exists($global->image_path)) {
                    // The shop gets its own copy of the file, so it can replace or delete it freely.
                    $imagePath = "shops/{$product->shop_id}/products/".Str::random(40).'.jpg';
                    Storage::disk('public')->copy($global->image_path, $imagePath);
                    $product->image_path = $imagePath;
                    $product->save();
                }

                return $product;
            });
        } catch (\Throwable $e) {
            $this->images->delete($imagePath);

            throw $e;
        }
    }

    /**
     * A catalogue barcode is only copied when the shop is not already using it.
     *
     * @param  list<?string>  $codes
     * @return list<string>
     */
    private function freeCodes(array $codes): array
    {
        $codes = array_values(array_filter($codes));

        if ($codes === []) {
            return [];
        }

        $taken = Barcode::query()->whereIn('code', $codes)->pluck('code')->all();

        return array_values(array_diff($codes, $taken));
    }

    private function categoryId(GlobalProduct $global): ?int
    {
        if ($global->category === null) {
            return null;
        }

        return Category::query()->whereNull('parent_id')->where('name', $global->category->name)->value('id')
            ?? Category::create(['name' => $global->category->name])->id;
    }

    private function brandId(GlobalProduct $global): ?int
    {
        if (! $global->brand) {
            return null;
        }

        return Brand::query()->where('name', $global->brand)->value('id')
            ?? Brand::create(['name' => $global->brand])->id;
    }

    private function unitId(GlobalProduct $global): int
    {
        return Unit::query()->where('name', $global->default_unit)->orderByRaw('shop_id is null')->value('id')
            ?? Unit::query()->whereNull('shop_id')->where('name', 'Piece')->valueOrFail('id');
    }
}
