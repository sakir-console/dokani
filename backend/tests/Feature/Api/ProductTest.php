<?php

namespace Tests\Feature\Api;

use App\Enums\ShopRole;
use App\Models\Barcode;
use App\Models\Brand;
use App\Models\Category;
use App\Models\Plan;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\StockMovement;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class ProductTest extends TestCase
{
    private function simplePayload(array $overrides = [], array $variant = []): array
    {
        return array_merge([
            'name' => 'Miniket Rice',
            'unit_id' => $this->unitId('Kilogram'),
            'variants' => [array_merge([
                'purchase_price' => '62.50', 'selling_price' => '70', 'stock_quantity' => '25.5',
                'sku' => 'RICE-01', 'barcodes' => ['8941100000017'],
            ], $variant)],
        ], $overrides);
    }

    // --- Create -------------------------------------------------------------

    public function test_a_simple_product_gets_one_default_variant_with_price_stock_and_barcode(): void
    {
        $shop = $this->createShop();

        $response = $this->asOwnerOf($shop)->postJson('/api/v1/products', $this->simplePayload());

        $response->assertCreated()
            ->assertJsonPath('data.name', 'Miniket Rice')
            ->assertJsonPath('data.has_variants', false)
            ->assertJsonPath('data.unit.name', 'Kilogram')
            ->assertJsonPath('data.total_stock', '25.500')
            ->assertJsonCount(1, 'data.variants')
            ->assertJsonPath('data.variants.0.name', null)
            ->assertJsonPath('data.variants.0.is_default', true)
            ->assertJsonPath('data.variants.0.purchase_price', '62.50')
            ->assertJsonPath('data.variants.0.selling_price', '70.00')
            ->assertJsonPath('data.variants.0.stock_quantity', '25.500')
            ->assertJsonPath('data.variants.0.sku', 'RICE-01')
            ->assertJsonPath('data.variants.0.barcodes', ['8941100000017']);

        // Opening stock is a recorded movement, not a bare number.
        $this->tenant()->runFor($shop, function () use ($response) {
            $movement = StockMovement::query()->sole();
            $this->assertSame('opening', $movement->type->value);
            $this->assertSame('25.500', $movement->quantity);
            $this->assertSame('25.500', $movement->balance_after);
            $this->assertSame('62.50', $movement->unit_cost);
            $this->assertSame($response->json('data.variants.0.id'), $movement->product_variant_id);
        });
    }

    public function test_a_product_with_variants_keeps_price_stock_and_barcode_per_variant(): void
    {
        $shop = $this->createShop();

        $response = $this->asOwnerOf($shop)->postJson('/api/v1/products', [
            'name' => 'Polo T-shirt',
            'unit_id' => $this->unitId(),
            'has_variants' => true,
            'variants' => [
                ['name' => 'S', 'attributes' => ['size' => 'S', 'color' => 'Red'], 'purchase_price' => 200, 'selling_price' => 350, 'stock_quantity' => 4, 'barcodes' => ['TS-S']],
                ['name' => 'M', 'attributes' => ['size' => 'M'], 'purchase_price' => 210, 'selling_price' => 360, 'stock_quantity' => 0, 'barcodes' => ['TS-M', 'TS-M-ALT']],
                ['name' => 'L', 'purchase_price' => 220, 'selling_price' => 370, 'stock_quantity' => 9],
            ],
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.has_variants', true)
            ->assertJsonCount(3, 'data.variants')
            ->assertJsonPath('data.total_stock', '13.000')
            ->assertJsonPath('data.out_of_stock_variants', 1)
            ->assertJsonPath('data.low_stock_variants', 1)
            ->assertJsonPath('data.variants.0.name', 'S')
            ->assertJsonPath('data.variants.0.attributes', ['size' => 'S', 'color' => 'Red'])
            ->assertJsonPath('data.variants.0.stock_status', 'low')
            ->assertJsonPath('data.variants.1.selling_price', '360.00')
            ->assertJsonPath('data.variants.1.stock_status', 'out')
            ->assertJsonPath('data.variants.1.barcodes', ['TS-M', 'TS-M-ALT'])
            ->assertJsonPath('data.variants.2.stock_status', 'in');

        // No movement for the variant that opened with zero stock.
        $this->tenant()->runFor($shop, fn () => $this->assertSame(2, StockMovement::query()->count()));
    }

    public function test_structural_rules_for_variants_are_enforced(): void
    {
        $shop = $this->createShop();
        $variant = ['purchase_price' => 1, 'selling_price' => 2];
        $post = fn (array $payload) => $this->asOwnerOf($shop)->postJson('/api/v1/products', ['name' => 'X', 'unit_id' => $this->unitId()] + $payload);

        $post([])->assertUnprocessable()->assertJsonValidationErrors('variants');
        $post(['variants' => []])->assertUnprocessable()->assertJsonValidationErrors('variants');
        $post(['has_variants' => false, 'variants' => [$variant, $variant]])->assertUnprocessable()->assertJsonValidationErrors('variants');
        $post(['has_variants' => true, 'variants' => [$variant + ['name' => 'A'], $variant + ['name' => ' ']]])
            ->assertUnprocessable()->assertJsonValidationErrors('variants.1.name');
        $post(['has_variants' => true, 'variants' => [$variant + ['name' => 'Red'], $variant + ['name' => 'red']]])
            ->assertUnprocessable()->assertJsonValidationErrors('variants.1.name');

        $this->tenant()->runFor($shop, fn () => $this->assertSame(0, Product::query()->count()));
    }

    public function test_prices_and_quantities_are_validated(): void
    {
        $shop = $this->createShop();
        $post = fn (array $variant, string $unit = 'Piece') => $this->asOwnerOf($shop)
            ->postJson('/api/v1/products', $this->simplePayload(['unit_id' => $this->unitId($unit)], $variant + ['barcodes' => []]));

        $post(['selling_price' => '-1'])->assertUnprocessable()->assertJsonValidationErrors('variants.0.selling_price');
        $post(['selling_price' => '10.999'])->assertUnprocessable()->assertJsonValidationErrors('variants.0.selling_price');
        $post(['purchase_price' => 'abc'])->assertUnprocessable()->assertJsonValidationErrors('variants.0.purchase_price');
        $post(['stock_quantity' => '-5'])->assertUnprocessable()->assertJsonValidationErrors('variants.0.stock_quantity');

        // Pieces cannot be fractional; kilograms can.
        $post(['stock_quantity' => '2.5'], 'Piece')->assertUnprocessable()->assertJsonPath('code', 'QUANTITY_MUST_BE_WHOLE');
        $post(['stock_quantity' => '2.5', 'sku' => 'K1'], 'Kilogram')->assertCreated();

        $this->tenant()->runFor($shop, fn () => $this->assertSame(1, Product::query()->count(), 'A rejected product leaves nothing behind.'));
    }

    public function test_money_is_stored_exactly(): void
    {
        $shop = $this->createShop();

        // 0.1 + 0.2 style values that floats get wrong must come back untouched.
        $this->asOwnerOf($shop)->postJson('/api/v1/products', $this->simplePayload([], [
            'purchase_price' => '0.10', 'selling_price' => '1234567.89', 'stock_quantity' => '0.300',
        ]))->assertCreated()
            ->assertJsonPath('data.variants.0.purchase_price', '0.10')
            ->assertJsonPath('data.variants.0.selling_price', '1234567.89')
            ->assertJsonPath('data.variants.0.stock_quantity', '0.300');
    }

    // --- Update -------------------------------------------------------------

    public function test_product_details_can_be_updated_without_touching_variants(): void
    {
        $shop = $this->createShop();
        $product = $this->createProduct($shop);
        [$category, $brand] = $this->tenant()->runFor($shop, fn () => [Category::factory()->create(), Brand::factory()->create()]);

        $this->asOwnerOf($shop)->patchJson("/api/v1/products/{$product->id}", [
            'name' => 'Renamed', 'category_id' => $category->id, 'brand_id' => $brand->id,
            'storage_location' => 'Rack 3', 'low_stock_threshold' => '20', 'description' => 'Good rice',
        ])->assertOk()
            ->assertJsonPath('data.name', 'Renamed')
            ->assertJsonPath('data.category.id', $category->id)
            ->assertJsonPath('data.brand.name', $brand->name)
            ->assertJsonPath('data.storage_location', 'Rack 3')
            ->assertJsonPath('data.effective_low_stock_threshold', '20.000')
            ->assertJsonPath('data.variants.0.stock_status', 'low')
            ->assertJsonPath('data.variants.0.stock_quantity', '10.000');
    }

    public function test_variants_can_be_added_changed_and_removed_in_one_update(): void
    {
        $shop = $this->createShop();
        $product = $this->createProduct($shop, ['name' => 'Shampoo'], [
            ['name' => '250ml', 'purchase_price' => 100, 'selling_price' => 150, 'stock_quantity' => 0, 'barcodes' => ['SH-250']],
            ['name' => '500ml', 'purchase_price' => 180, 'selling_price' => 260, 'stock_quantity' => 6, 'barcodes' => ['SH-500']],
        ]);
        [$small, $large] = $product->variants->all();

        $response = $this->asOwnerOf($shop)->patchJson("/api/v1/products/{$product->id}", [
            'variants' => [
                // 250ml is left out → removed (it has no stock).
                ['id' => $large->id, 'name' => '500 ml', 'purchase_price' => 185, 'selling_price' => 270, 'stock_quantity' => 999, 'barcodes' => ['SH-500', 'SH-250']],
                ['name' => '1L', 'purchase_price' => 320, 'selling_price' => 450, 'stock_quantity' => 3],
            ],
        ]);

        $response->assertOk()
            ->assertJsonCount(2, 'data.variants')
            ->assertJsonPath('data.variants.0.id', $large->id)
            ->assertJsonPath('data.variants.0.name', '500 ml')
            ->assertJsonPath('data.variants.0.selling_price', '270.00')
            // Stock of an existing variant cannot be changed through a product update.
            ->assertJsonPath('data.variants.0.stock_quantity', '6.000')
            // The freed barcode moved to the kept variant in the same request.
            ->assertJsonPath('data.variants.0.barcodes', ['SH-500', 'SH-250'])
            ->assertJsonPath('data.variants.1.name', '1L')
            ->assertJsonPath('data.variants.1.stock_quantity', '3.000');

        $this->tenant()->runFor($shop, fn () => $this->assertNull(ProductVariant::query()->find($small->id)));
    }

    public function test_a_variant_with_stock_cannot_be_removed(): void
    {
        $shop = $this->createShop();
        $product = $this->createProduct($shop, [], [
            ['name' => 'A', 'purchase_price' => 1, 'selling_price' => 2, 'stock_quantity' => 5],
            ['name' => 'B', 'purchase_price' => 1, 'selling_price' => 2, 'stock_quantity' => 0],
        ]);
        $b = $product->variants[1];

        $this->asOwnerOf($shop)->patchJson("/api/v1/products/{$product->id}", [
            'variants' => [['id' => $b->id, 'name' => 'B', 'purchase_price' => 1, 'selling_price' => 2]],
        ])->assertConflict()->assertJsonPath('code', 'VARIANT_HAS_STOCK');

        $this->tenant()->runFor($shop, fn () => $this->assertSame(2, ProductVariant::query()->count()));
    }

    public function test_a_simple_product_can_be_turned_into_one_with_variants(): void
    {
        $shop = $this->createShop();
        $product = $this->createProduct($shop);
        $default = $product->variants[0];

        $this->asOwnerOf($shop)->patchJson("/api/v1/products/{$product->id}", ['has_variants' => true])
            ->assertUnprocessable()->assertJsonPath('code', 'VARIANTS_REQUIRED');

        $this->asOwnerOf($shop)->patchJson("/api/v1/products/{$product->id}", [
            'has_variants' => true,
            'variants' => [
                ['id' => $default->id, 'name' => 'Small', 'purchase_price' => 50, 'selling_price' => 60],
                ['name' => 'Large', 'purchase_price' => 80, 'selling_price' => 100, 'stock_quantity' => 2],
            ],
        ])->assertOk()
            ->assertJsonPath('data.has_variants', true)
            ->assertJsonPath('data.variants.0.id', $default->id)
            ->assertJsonPath('data.variants.0.name', 'Small')
            ->assertJsonPath('data.variants.0.stock_quantity', '10.000')
            ->assertJsonPath('data.total_stock', '12.000');
    }

    // --- Delete -------------------------------------------------------------

    public function test_deleting_a_product_hides_it_and_frees_its_barcodes(): void
    {
        $shop = $this->createShop();
        $product = $this->createProduct($shop, [], [['purchase_price' => 1, 'selling_price' => 2, 'barcodes' => ['REUSE-ME']]]);

        $this->asOwnerOf($shop)->deleteJson("/api/v1/products/{$product->id}")->assertNoContent();

        $this->asOwnerOf($shop)->getJson("/api/v1/products/{$product->id}")->assertNotFound();
        $this->asOwnerOf($shop)->getJson('/api/v1/products')->assertJsonCount(0, 'data');
        $this->asOwnerOf($shop)->getJson('/api/v1/barcodes/lookup?code=REUSE-ME')->assertNotFound();

        // Soft-deleted: the rows survive for sales history.
        $this->assertDatabaseHas('products', ['id' => $product->id]);
        $this->assertSoftDeleted('products', ['id' => $product->id]);

        $this->asOwnerOf($shop)->postJson('/api/v1/products', $this->simplePayload([], ['barcodes' => ['REUSE-ME']]))->assertCreated();
    }

    // --- Search and filters -------------------------------------------------

    public function test_products_can_be_searched_by_name_barcode_and_sku(): void
    {
        $shop = $this->createShop();
        $this->createProduct($shop, ['name' => 'Lux Soap'], [['purchase_price' => 1, 'selling_price' => 2, 'barcodes' => ['111222'], 'sku' => 'SOAP-1']]);
        $this->createProduct($shop, ['name' => 'Lifebuoy Soap']);
        $this->createProduct($shop, ['name' => 'Sugar']);

        $names = fn (string $query) => $this->asOwnerOf($shop)->getJson('/api/v1/products?'.$query)->assertOk()->json('data.*.name');

        $this->assertSame(['Lifebuoy Soap', 'Lux Soap'], $names('q=soap'));
        $this->assertSame(['Lux Soap'], $names('q=111222'));
        $this->assertSame(['Lux Soap'], $names('q=SOAP-1'));
        $this->assertSame([], $names('q=1112'), 'Barcodes match exactly, not partially.');
        $this->assertSame([], $names('q=100%25'), 'LIKE wildcards in the search term are literal.');
        $this->assertCount(3, $names(''));
    }

    public function test_products_can_be_filtered_by_category_brand_and_stock_level(): void
    {
        $shop = $this->createShop();
        [$category, $brand] = $this->tenant()->runFor($shop, fn () => [Category::factory()->create(), Brand::factory()->create()]);

        $this->createProduct($shop, ['name' => 'Plenty', 'category_id' => $category->id]);                       // 10 in stock
        $this->createProduct($shop, ['name' => 'Low', 'brand_id' => $brand->id], [['purchase_price' => 1, 'selling_price' => 2, 'stock_quantity' => 3]]);
        $this->createProduct($shop, ['name' => 'Empty'], [['purchase_price' => 1, 'selling_price' => 2, 'stock_quantity' => 0]]);
        $this->createProduct($shop, ['name' => 'Own threshold', 'low_stock_threshold' => '50'], [['purchase_price' => 1, 'selling_price' => 2, 'stock_quantity' => 40]]);

        $names = fn (string $query) => $this->asOwnerOf($shop)->getJson('/api/v1/products?'.$query)->assertOk()->json('data.*.name');

        $this->assertSame(['Plenty'], $names('category_id='.$category->id));
        $this->assertSame(['Low'], $names('brand_id='.$brand->id));
        $this->assertSame(['Low', 'Own threshold'], $names('stock=low'));
        $this->assertSame(['Empty'], $names('stock=out'));
        $this->assertSame(['Low', 'Own threshold', 'Plenty'], $names('stock=in'));

        $this->asOwnerOf($shop)->getJson('/api/v1/stock/summary')->assertOk()
            ->assertJsonPath('data.total_products', 4)
            ->assertJsonPath('data.low_stock_products', 2)
            ->assertJsonPath('data.out_of_stock_products', 1);
    }

    public function test_the_product_list_is_paginated(): void
    {
        $shop = $this->createShop();
        foreach (range(1, 5) as $i) {
            $this->createProduct($shop, ['name' => "Item {$i}"]);
        }

        $this->asOwnerOf($shop)->getJson('/api/v1/products?per_page=2&page=3')->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('meta.total', 5)
            ->assertJsonPath('meta.last_page', 3);
    }

    // --- Image --------------------------------------------------------------

    public function test_a_product_image_is_re_encoded_and_can_be_replaced_and_removed(): void
    {
        Storage::fake('public');
        $shop = $this->createShop();
        $product = $this->createProduct($shop);
        $upload = fn (UploadedFile $file) => $this->asOwnerOf($shop)->post("/api/v1/products/{$product->id}/image", ['image' => $file], ['Accept' => 'application/json']);

        $upload(UploadedFile::fake()->image('p.png', 1600, 1200))->assertOk();
        $path = $product->fresh()->image_path;
        $this->assertStringStartsWith("shops/{$shop->id}/products/", $path);
        $this->assertSame([800, 600], array_slice(getimagesizefromstring(Storage::disk('public')->get($path)), 0, 2));

        $upload(UploadedFile::fake()->image('p2.jpg', 50, 50))->assertOk();
        Storage::disk('public')->assertMissing($path);

        $upload(UploadedFile::fake()->createWithContent('x.jpg', 'not an image'))->assertUnprocessable();

        $this->asOwnerOf($shop)->deleteJson("/api/v1/products/{$product->id}/image")->assertOk()->assertJsonPath('data.image_url', null);
        $this->assertSame([], Storage::disk('public')->allFiles());
    }

    // --- Plan limit and permissions -----------------------------------------

    public function test_the_plans_product_limit_is_enforced_by_the_server(): void
    {
        $shop = $this->createShop();
        Plan::query()->where('code', 'free')->update(['max_products' => 2]);

        $this->createProduct($shop);
        $second = $this->createProduct($shop);

        $this->asOwnerOf($shop)->postJson('/api/v1/products', $this->simplePayload())
            ->assertForbidden()->assertJsonPath('code', 'PLAN_LIMIT_REACHED');

        // Deleting one frees a slot; upgrading lifts the limit.
        $this->asOwnerOf($shop)->deleteJson("/api/v1/products/{$second->id}")->assertNoContent();
        $this->asOwnerOf($shop)->postJson('/api/v1/products', $this->simplePayload())->assertCreated();

        $this->asOwnerOf($shop)->postJson('/api/v1/products', $this->simplePayload([], ['barcodes' => [], 'sku' => null]))->assertForbidden();
        $this->subscribe($shop, 'premium');
        $this->asOwnerOf($shop)->postJson('/api/v1/products', $this->simplePayload([], ['barcodes' => [], 'sku' => null]))->assertCreated();
    }

    public function test_a_cashier_can_view_products_but_not_change_them(): void
    {
        $shop = $this->createShop();
        $product = $this->createProduct($shop);
        $cashier = $this->addMember($shop, ShopRole::Cashier);

        $this->asUser($cashier)->getJson('/api/v1/products')->assertOk()->assertJsonCount(1, 'data');
        $this->asUser($cashier)->getJson("/api/v1/products/{$product->id}")->assertOk();

        $this->asUser($cashier)->postJson('/api/v1/products', $this->simplePayload())->assertForbidden();
        $this->asUser($cashier)->patchJson("/api/v1/products/{$product->id}", ['name' => 'x'])->assertForbidden();
        $this->asUser($cashier)->deleteJson("/api/v1/products/{$product->id}")->assertForbidden();
        $this->asUser($cashier)->postJson('/api/v1/stock/in', ['variant_id' => $product->variants[0]->id, 'quantity' => 1])->assertForbidden();
    }

    // --- Barcodes -----------------------------------------------------------

    public function test_a_scanned_barcode_resolves_to_the_exact_variant(): void
    {
        $shop = $this->createShop();
        $product = $this->createProduct($shop, ['name' => 'Phone'], [
            ['name' => '64GB', 'purchase_price' => 1, 'selling_price' => 2, 'barcodes' => ['PH-64']],
            ['name' => '128GB', 'purchase_price' => 1, 'selling_price' => 2, 'barcodes' => ['PH-128']],
        ]);

        $this->asOwnerOf($shop)->getJson('/api/v1/barcodes/lookup?code=PH-128')->assertOk()
            ->assertJsonPath('data.variant_id', $product->variants[1]->id)
            ->assertJsonPath('data.product.id', $product->id)
            ->assertJsonPath('data.product.name', 'Phone');

        $this->asOwnerOf($shop)->getJson('/api/v1/barcodes/lookup?code=%20PH-64%20')->assertOk()
            ->assertJsonPath('data.variant_id', $product->variants[0]->id);

        $this->asOwnerOf($shop)->getJson('/api/v1/barcodes/lookup?code=UNKNOWN')
            ->assertNotFound()->assertJsonPath('code', 'BARCODE_NOT_FOUND');
        $this->asOwnerOf($shop)->getJson('/api/v1/barcodes/lookup')->assertUnprocessable();
    }

    public function test_a_barcode_can_belong_to_only_one_variant_in_a_shop(): void
    {
        $shop = $this->createShop();
        $existing = $this->createProduct($shop, [], [['purchase_price' => 1, 'selling_price' => 2, 'barcodes' => ['DUP']]]);

        // On another product.
        $this->asOwnerOf($shop)->postJson('/api/v1/products', $this->simplePayload([], ['barcodes' => ['DUP']]))
            ->assertUnprocessable()->assertJsonPath('code', 'BARCODE_TAKEN')->assertJsonValidationErrors('variants.0.barcodes');

        // Twice inside one request.
        $this->asOwnerOf($shop)->postJson('/api/v1/products', [
            'name' => 'Two', 'unit_id' => $this->unitId(), 'has_variants' => true,
            'variants' => [
                ['name' => 'A', 'purchase_price' => 1, 'selling_price' => 2, 'barcodes' => ['SAME']],
                ['name' => 'B', 'purchase_price' => 1, 'selling_price' => 2, 'barcodes' => ['SAME']],
            ],
        ])->assertUnprocessable()->assertJsonPath('code', 'BARCODE_TAKEN');

        // Re-saving a variant with its own barcode is fine.
        $this->asOwnerOf($shop)->patchJson("/api/v1/products/{$existing->id}", [
            'variants' => [['id' => $existing->variants[0]->id, 'purchase_price' => 1, 'selling_price' => 3, 'barcodes' => ['DUP']]],
        ])->assertOk()->assertJsonPath('data.variants.0.barcodes', ['DUP']);

        $this->tenant()->runFor($shop, fn () => $this->assertSame(1, Barcode::query()->where('code', 'DUP')->count()));
    }

    public function test_the_database_itself_rejects_a_duplicate_barcode(): void
    {
        $shop = $this->createShop();
        $product = $this->createProduct($shop, [], [['purchase_price' => 1, 'selling_price' => 2, 'barcodes' => ['RACE']]]);

        $this->expectException(UniqueConstraintViolationException::class);

        // Bypasses the service's check, as two racing requests would.
        $this->tenant()->runFor($shop, function () use ($product) {
            $barcode = new Barcode(['code' => 'RACE']);
            $barcode->product_variant_id = $product->variants[0]->id;
            $barcode->save();
        });
    }
}
