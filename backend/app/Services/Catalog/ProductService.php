<?php

namespace App\Services\Catalog;

use App\Enums\StockMovementType;
use App\Exceptions\ApiException;
use App\Models\Barcode;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use App\Services\Inventory\StockService;
use App\Services\Subscription\Entitlements;
use App\Services\Tenancy\ShopLock;
use App\Services\Tenancy\TenantContext;
use App\Support\Dec;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;

/**
 * Creates and updates products together with their variants and barcodes.
 *
 * Rules enforced here (not in the app):
 *  - the plan's product limit
 *  - a product without variants has exactly one, unnamed, default variant
 *  - a product with variants has uniquely named variants
 *  - a barcode belongs to one variant per shop
 *  - stock is never set directly: opening stock goes through StockService
 */
class ProductService
{
    private const PRODUCT_FIELDS = [
        'category_id', 'brand_id', 'unit_id', 'vendor_id', 'name', 'description',
        'storage_location', 'has_variants', 'low_stock_threshold', 'is_active',
    ];

    public function __construct(
        private readonly StockService $stock,
        private readonly Entitlements $entitlements,
    ) {}

    /** @param array<string, mixed> $data */
    public function create(array $data, ?User $actor, ?int $globalProductId = null): Product
    {
        try {
            return DB::transaction(function () use ($data, $actor, $globalProductId) {
                $this->assertWithinProductLimit();

                $hasVariants = (bool) ($data['has_variants'] ?? false);
                $variants = $this->normalizeVariants($data['variants'] ?? [], $hasVariants);
                $this->assertBarcodesFree($variants);

                $product = new Product(array_intersect_key($data, array_flip(self::PRODUCT_FIELDS)));
                $product->has_variants = $hasVariants;
                $product->global_product_id = $globalProductId;
                $product->save();

                foreach ($variants as $row) {
                    $this->createVariant($product, $row, $actor);
                }

                return $product;
            });
        } catch (UniqueConstraintViolationException) {
            // Two requests raced for the same barcode; the unique index decided.
            throw $this->barcodeTaken();
        }
    }

    /** @param array<string, mixed> $data */
    public function update(Product $product, array $data, ?User $actor): Product
    {
        try {
            return DB::transaction(function () use ($product, $data, $actor) {
                $product->fill(array_intersect_key($data, array_flip(self::PRODUCT_FIELDS)));

                if (array_key_exists('variants', $data)) {
                    $this->syncVariants($product, $data['variants'], $actor);
                } elseif ($product->isDirty('has_variants')) {
                    throw new ApiException('VARIANTS_REQUIRED', __('Send the variants when switching variants on or off.'), 422);
                }

                $product->save();
                // Always move updated_at, even when only a barcode changed, so phones pick the change up on their next sync.
                $product->touch();

                return $product;
            });
        } catch (UniqueConstraintViolationException) {
            throw $this->barcodeTaken();
        }
    }

    public function delete(Product $product): void
    {
        DB::transaction(function () use ($product) {
            $variantIds = $product->variants()->pluck('id');

            // Free the barcodes so they can be used on another product.
            Barcode::query()->whereIn('product_variant_id', $variantIds)->delete();
            ProductVariant::query()->whereIn('id', $variantIds)->delete();
            $product->delete();
        });
    }

    // ---------------------------------------------------------------------

    /**
     * The submitted list is the complete set: rows with an id are updated,
     * rows without are created, existing variants left out are removed.
     *
     * @param  list<array<string, mixed>>  $rows
     */
    private function syncVariants(Product $product, array $rows, ?User $actor): void
    {
        $rows = $this->normalizeVariants($rows, (bool) $product->has_variants);
        $existing = $product->variants()->lockForUpdate()->get()->keyBy('id');

        $keptIds = [];
        foreach ($rows as $index => $row) {
            if (isset($row['id']) && ! $existing->has($row['id'])) {
                // Covers ids from another product and from another shop alike.
                throw new ApiException('VALIDATION_FAILED', __('The selected variant is invalid.'), 422, [
                    "variants.$index.id" => [__('The selected variant is invalid.')],
                ]);
            }
            if (isset($row['id'])) {
                $keptIds[] = $row['id'];
            }
        }

        foreach ($existing->except($keptIds) as $removed) {
            if (! Dec::of($removed->stock_quantity)->isZero()) {
                throw ApiException::conflict('VARIANT_HAS_STOCK', __('":name" still has stock. Adjust its stock to zero before removing it.', [
                    'name' => $removed->name ?? $product->name,
                ]));
            }
            $removed->barcodes()->delete();
            $removed->delete();
        }

        // Checked after removals, so a barcode can move from a removed variant to a kept one.
        $this->assertBarcodesFree($rows);

        foreach ($rows as $row) {
            if (isset($row['id'])) {
                $variant = $existing[$row['id']];
                $variant->fill([
                    'name' => $row['name'],
                    'options' => $row['attributes'],
                    'sku' => $row['sku'],
                    'purchase_price' => $row['purchase_price'],
                    'selling_price' => $row['selling_price'],
                    'is_default' => $row['is_default'],
                ])->save();
                // Stock of an existing variant is not touched here; use the stock endpoints.
                $this->syncBarcodes($variant, $row['barcodes']);
            } else {
                $this->createVariant($product, $row, $actor);
            }
        }
    }

    /** @param array<string, mixed> $row */
    private function createVariant(Product $product, array $row, ?User $actor): ProductVariant
    {
        $variant = new ProductVariant([
            'name' => $row['name'],
            'options' => $row['attributes'],
            'sku' => $row['sku'],
            'purchase_price' => $row['purchase_price'],
            'selling_price' => $row['selling_price'],
            'is_default' => $row['is_default'],
        ]);
        $variant->product_id = $product->id;
        $variant->save();

        $this->syncBarcodes($variant, $row['barcodes']);

        if (Dec::of($row['stock_quantity'])->isPositive()) {
            $this->stock->change($variant->id, StockMovementType::Opening, Dec::of($row['stock_quantity']), $actor, [
                'unit_cost' => $row['purchase_price'],
            ]);
        }

        return $variant;
    }

    /** @param list<string> $codes */
    private function syncBarcodes(ProductVariant $variant, array $codes): void
    {
        $current = $variant->barcodes()->pluck('code')->all();

        $variant->barcodes()->whereIn('code', array_diff($current, $codes))->delete();

        foreach (array_diff($codes, $current) as $code) {
            $barcode = new Barcode(['code' => $code]);
            $barcode->product_variant_id = $variant->id;
            $barcode->save();
        }
    }

    /**
     * Cleans the submitted variants and applies the structural rules.
     *
     * @param  list<array<string, mixed>>  $rows
     * @return list<array<string, mixed>>
     */
    private function normalizeVariants(array $rows, bool $hasVariants): array
    {
        $rows = array_values($rows);

        if ($rows === []) {
            throw new ApiException('VALIDATION_FAILED', __('A product needs at least one variant.'), 422, [
                'variants' => [__('A product needs at least one variant.')],
            ]);
        }

        if (! $hasVariants && count($rows) !== 1) {
            throw new ApiException('VALIDATION_FAILED', __('A product without variants can only have one price and stock.'), 422, [
                'variants' => [__('A product without variants can only have one price and stock.')],
            ]);
        }

        $seenNames = [];
        $seenCodes = [];
        $clean = [];

        foreach ($rows as $index => $row) {
            $name = $hasVariants ? trim((string) ($row['name'] ?? '')) : null;

            if ($hasVariants) {
                if ($name === '') {
                    throw new ApiException('VALIDATION_FAILED', __('Each variant needs a name.'), 422, [
                        "variants.$index.name" => [__('Each variant needs a name.')],
                    ]);
                }
                $key = mb_strtolower($name);
                if (isset($seenNames[$key])) {
                    throw new ApiException('VALIDATION_FAILED', __('Variant names must be different.'), 422, [
                        "variants.$index.name" => [__('Variant names must be different.')],
                    ]);
                }
                $seenNames[$key] = true;
            }

            $codes = [];
            foreach ($row['barcodes'] ?? [] as $code) {
                $code = trim((string) $code);
                if ($code === '') {
                    continue;
                }
                if (isset($seenCodes[$code])) {
                    throw new ApiException('BARCODE_TAKEN', __('The same barcode is used more than once.'), 422, [
                        "variants.$index.barcodes" => [__('The same barcode is used more than once.')],
                    ]);
                }
                $seenCodes[$code] = true;
                $codes[] = $code;
            }

            $sku = trim((string) ($row['sku'] ?? ''));

            $clean[] = [
                'id' => isset($row['id']) ? (int) $row['id'] : null,
                'name' => $name,
                'attributes' => $hasVariants && ! empty($row['attributes']) ? $row['attributes'] : null,
                'sku' => $sku === '' ? null : $sku,
                'purchase_price' => Dec::money($row['purchase_price'] ?? 0),
                'selling_price' => Dec::money($row['selling_price'] ?? 0),
                'stock_quantity' => Dec::qty($row['stock_quantity'] ?? 0),
                'is_default' => ! $hasVariants || $index === 0,
                'barcodes' => $codes,
            ];
        }

        return $clean;
    }

    /**
     * No submitted barcode may already belong to a different variant in this shop.
     *
     * @param  list<array<string, mixed>>  $rows
     */
    private function assertBarcodesFree(array $rows): void
    {
        foreach ($rows as $index => $row) {
            if ($row['barcodes'] === []) {
                continue;
            }

            $taken = Barcode::query()
                ->whereIn('code', $row['barcodes'])
                ->when($row['id'], fn ($q, $id) => $q->where('product_variant_id', '!=', $id))
                ->value('code');

            if ($taken !== null) {
                throw $this->barcodeTaken($taken, "variants.$index.barcodes");
            }
        }
    }

    private function barcodeTaken(?string $code = null, string $field = 'variants'): ApiException
    {
        $message = $code === null
            ? __('This barcode is already used by another product.')
            : __('Barcode :code is already used by another product.', ['code' => $code]);

        return new ApiException('BARCODE_TAKEN', $message, 422, [$field => [$message]]);
    }

    private function assertWithinProductLimit(): void
    {
        $shop = app(TenantContext::class)->shop();
        $limit = $this->entitlements->limits($shop)['max_products'];

        if ($limit === null) {
            return;
        }

        // Serialise product creation per shop, so two requests cannot both take the last slot.
        app(ShopLock::class)->acquire();

        if (Product::query()->count() >= $limit) {
            throw ApiException::forbidden('PLAN_LIMIT_REACHED', __('Your plan allows :limit products. Upgrade to add more.', ['limit' => $limit]));
        }
    }
}
