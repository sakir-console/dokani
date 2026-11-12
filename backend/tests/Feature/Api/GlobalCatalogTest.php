<?php

namespace Tests\Feature\Api;

use App\Models\GlobalCategory;
use App\Models\GlobalProduct;
use App\Models\Plan;
use App\Models\Product;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class GlobalCatalogTest extends TestCase
{
    private function globalProduct(array $attributes = [], array $variants = []): GlobalProduct
    {
        $product = GlobalProduct::factory()->create($attributes);
        foreach ($variants as $variant) {
            $product->variants()->create($variant);
        }

        return $product->fresh();
    }

    public function test_the_catalogue_needs_a_plan_that_includes_it(): void
    {
        $shop = $this->createShop(); // free
        $global = $this->globalProduct();

        $this->asOwnerOf($shop)->getJson('/api/v1/global-catalog/products')->assertForbidden()->assertJsonPath('code', 'MODULE_NOT_AVAILABLE');
        $this->asOwnerOf($shop)->postJson("/api/v1/global-catalog/products/{$global->id}/import")->assertForbidden();
    }

    public function test_shops_can_browse_and_search_active_catalogue_products(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic');
        $category = GlobalCategory::create(['name' => 'Beverages', 'name_bn' => 'পানীয়']);

        $this->globalProduct(['name' => 'Coca-Cola 250ml', 'name_bn' => 'কোকা-কোলা', 'brand' => 'Coca-Cola', 'barcode' => '5449000000996', 'global_category_id' => $category->id]);
        $this->globalProduct(['name' => 'Lux Soap']);
        $this->globalProduct(['name' => 'Hidden', 'is_active' => false]);

        $names = fn (string $query) => $this->asOwnerOf($shop)->getJson('/api/v1/global-catalog/products?'.$query)->assertOk()->json('data.*.name');

        $this->assertSame(['Coca-Cola 250ml', 'Lux Soap'], $names(''));
        $this->assertSame(['Coca-Cola 250ml'], $names('q=cola'));
        $this->assertSame(['Coca-Cola 250ml'], $names('q='.urlencode('কোকা')));
        $this->assertSame(['Coca-Cola 250ml'], $names('q=5449000000996'));
        $this->assertSame(['Coca-Cola 250ml'], $names('category_id='.$category->id));

        $this->asOwnerOf($shop)->getJson('/api/v1/global-catalog/categories')->assertOk()
            ->assertJsonPath('data.0.name', 'Beverages')->assertJsonPath('data.0.name_bn', 'পানীয়');
    }

    public function test_importing_creates_an_independent_shop_product_with_the_shops_own_prices(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic');
        $category = GlobalCategory::create(['name' => 'Beverages']);
        $global = $this->globalProduct([
            'name' => 'Coca-Cola 250ml', 'brand' => 'Coca-Cola', 'barcode' => '5449000000996',
            'default_unit' => 'Bottle', 'global_category_id' => $category->id, 'description' => 'Soft drink',
        ]);

        $response = $this->asOwnerOf($shop)->postJson("/api/v1/global-catalog/products/{$global->id}/import", [
            'purchase_price' => '18', 'selling_price' => '25', 'stock_quantity' => '48',
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.name', 'Coca-Cola 250ml')
            ->assertJsonPath('data.from_global_catalog', true)
            ->assertJsonPath('data.category.name', 'Beverages')
            ->assertJsonPath('data.brand.name', 'Coca-Cola')
            ->assertJsonPath('data.unit.name', 'Bottle')
            ->assertJsonPath('data.variants.0.purchase_price', '18.00')
            ->assertJsonPath('data.variants.0.selling_price', '25.00')
            ->assertJsonPath('data.variants.0.stock_quantity', '48.000')
            ->assertJsonPath('data.variants.0.barcodes', ['5449000000996']);

        $productId = $response->json('data.id');
        $this->asOwnerOf($shop)->getJson('/api/v1/barcodes/lookup?code=5449000000996')->assertJsonPath('data.product.id', $productId);
        $this->asOwnerOf($shop)->getJson('/api/v1/global-catalog/products')->assertJsonPath('data.0.already_imported', true);

        // The shop's copy and the global row are independent in both directions.
        $this->asOwnerOf($shop)->patchJson("/api/v1/products/{$productId}", ['name' => 'Coke (small)'])->assertOk();
        $this->assertSame('Coca-Cola 250ml', $global->fresh()->name);

        $global->update(['name' => 'Renamed by admin']);
        $this->asOwnerOf($shop)->getJson("/api/v1/products/{$productId}")->assertJsonPath('data.name', 'Coke (small)');

        // The global row never gained a price or stock.
        $this->assertArrayNotHasKey('selling_price', $global->fresh()->getAttributes());
    }

    public function test_importing_a_product_with_variants_copies_each_variant(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic');
        $global = $this->globalProduct(['name' => 'Sunsilk Shampoo'], [
            ['name' => '180ml', 'options' => ['size' => '180ml'], 'barcode' => 'SS-180'],
            ['name' => '340ml', 'options' => ['size' => '340ml'], 'barcode' => 'SS-340'],
        ]);
        [$small, $large] = $global->variants->all();

        $this->asOwnerOf($shop)->postJson("/api/v1/global-catalog/products/{$global->id}/import", [
            'purchase_price' => 150, 'selling_price' => 190,
            'variants' => [['global_variant_id' => $large->id, 'purchase_price' => 270, 'selling_price' => 330, 'stock_quantity' => 6]],
        ])->assertCreated()
            ->assertJsonPath('data.has_variants', true)
            ->assertJsonCount(2, 'data.variants')
            ->assertJsonPath('data.variants.0.name', '180ml')
            ->assertJsonPath('data.variants.0.selling_price', '190.00')
            ->assertJsonPath('data.variants.0.attributes', ['size' => '180ml'])
            ->assertJsonPath('data.variants.0.barcodes', ['SS-180'])
            ->assertJsonPath('data.variants.1.selling_price', '330.00')
            ->assertJsonPath('data.variants.1.stock_quantity', '6.000');

        $this->assertNotNull($small);
    }

    public function test_a_catalogue_barcode_the_shop_already_uses_is_not_copied(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic');
        $this->createProduct($shop, [], [['purchase_price' => 1, 'selling_price' => 2, 'barcodes' => ['TAKEN']]]);
        $global = $this->globalProduct(['barcode' => 'TAKEN']);

        $this->asOwnerOf($shop)->postJson("/api/v1/global-catalog/products/{$global->id}/import", ['selling_price' => 5])
            ->assertCreated()->assertJsonPath('data.variants.0.barcodes', []);
    }

    public function test_the_catalogue_image_is_copied_so_each_shop_owns_its_file(): void
    {
        Storage::fake('public');
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic');
        $global = $this->globalProduct();
        $global->image_path = UploadedFile::fake()->image('g.jpg', 100, 100)->store('global', 'public');
        $global->save();

        $productId = $this->asOwnerOf($shop)->postJson("/api/v1/global-catalog/products/{$global->id}/import")->assertCreated()->json('data.id');
        $copy = $this->tenant()->runFor($shop, fn () => Product::query()->findOrFail($productId)->image_path);

        $this->assertNotSame($global->image_path, $copy);
        Storage::disk('public')->assertExists($copy);

        // Removing the shop's image leaves the catalogue image alone.
        $this->asOwnerOf($shop)->deleteJson("/api/v1/products/{$productId}/image")->assertOk();
        Storage::disk('public')->assertMissing($copy);
        Storage::disk('public')->assertExists($global->image_path);
    }

    public function test_imports_count_towards_the_product_limit_and_inactive_products_cannot_be_imported(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic');
        Plan::query()->where('code', 'basic')->update(['max_products' => 1]);

        $first = $this->globalProduct();
        $second = $this->globalProduct();
        $hidden = $this->globalProduct(['is_active' => false]);

        $this->asOwnerOf($shop)->postJson("/api/v1/global-catalog/products/{$hidden->id}/import")->assertNotFound();
        $this->asOwnerOf($shop)->postJson("/api/v1/global-catalog/products/{$first->id}/import")->assertCreated();
        $this->asOwnerOf($shop)->postJson("/api/v1/global-catalog/products/{$second->id}/import")
            ->assertForbidden()->assertJsonPath('code', 'PLAN_LIMIT_REACHED');
    }

    public function test_one_shops_import_does_not_mark_the_product_as_imported_for_another(): void
    {
        $a = $this->createShop();
        $b = $this->createShop();
        $this->subscribe($a, 'basic');
        $this->subscribe($b, 'basic');
        $global = $this->globalProduct();

        $this->asOwnerOf($a)->postJson("/api/v1/global-catalog/products/{$global->id}/import")->assertCreated();

        $this->asOwnerOf($a)->getJson('/api/v1/global-catalog/products')->assertJsonPath('data.0.already_imported', true);
        $this->asOwnerOf($b)->getJson('/api/v1/global-catalog/products')->assertJsonPath('data.0.already_imported', false);
        $this->asOwnerOf($b)->getJson('/api/v1/products')->assertJsonCount(0, 'data');
    }
}
