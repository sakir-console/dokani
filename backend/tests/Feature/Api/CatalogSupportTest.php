<?php

namespace Tests\Feature\Api;

use App\Models\Brand;
use App\Models\Product;
use App\Models\Vendor;
use Tests\TestCase;

/** Units, brands and vendors: the lists a product form picks from. */
class CatalogSupportTest extends TestCase
{
    // --- Units --------------------------------------------------------------

    public function test_every_shop_sees_the_built_in_units_with_bangla_names(): void
    {
        $shop = $this->createShop();

        $units = $this->asOwnerOf($shop)->getJson('/api/v1/units')->assertOk()->json('data');

        $this->assertCount(13, $units);
        $this->assertSame('Piece', $units[0]['name']);
        $this->assertSame('পিস', $units[0]['name_bn']);
        $this->assertTrue($units[0]['is_built_in']);
        $this->assertTrue(collect($units)->firstWhere('name', 'Kilogram')['allows_decimal']);
        $this->assertFalse(collect($units)->firstWhere('name', 'Dozen')['allows_decimal']);
    }

    public function test_a_shop_can_add_change_and_delete_its_own_units_only(): void
    {
        $shop = $this->createShop();

        $id = $this->asOwnerOf($shop)->postJson('/api/v1/units', ['name' => 'Bundle', 'short_name' => 'bdl'])
            ->assertCreated()->assertJsonPath('data.is_built_in', false)->json('data.id');

        $this->asOwnerOf($shop)->postJson('/api/v1/units', ['name' => 'Bundle', 'short_name' => 'b'])->assertUnprocessable();
        $this->asOwnerOf($shop)->postJson('/api/v1/units', ['name' => 'Piece', 'short_name' => 'p'])
            ->assertUnprocessable()->assertJsonValidationErrors('name');

        $this->asOwnerOf($shop)->patchJson("/api/v1/units/{$id}", ['allows_decimal' => true])->assertOk()->assertJsonPath('data.allows_decimal', true);

        $piece = $this->unitId();
        $this->asOwnerOf($shop)->patchJson("/api/v1/units/{$piece}", ['name' => 'Hacked'])->assertForbidden()->assertJsonPath('code', 'UNIT_BUILT_IN');
        $this->asOwnerOf($shop)->deleteJson("/api/v1/units/{$piece}")->assertForbidden();

        $this->createProduct($shop, ['unit_id' => $id]);
        $this->asOwnerOf($shop)->deleteJson("/api/v1/units/{$id}")->assertConflict()->assertJsonPath('code', 'UNIT_IN_USE');
    }

    // --- Brands -------------------------------------------------------------

    public function test_brands_can_be_managed_and_deleting_one_keeps_its_products(): void
    {
        $shop = $this->createShop();

        $id = $this->asOwnerOf($shop)->postJson('/api/v1/brands', ['name' => 'Pran'])->assertCreated()->json('data.id');
        $this->asOwnerOf($shop)->postJson('/api/v1/brands', ['name' => 'Pran'])->assertUnprocessable();
        $this->asOwnerOf($shop)->patchJson("/api/v1/brands/{$id}", ['name' => 'PRAN Foods'])->assertOk()->assertJsonPath('data.name', 'PRAN Foods');
        $this->asOwnerOf($shop)->getJson('/api/v1/brands?q=foods')->assertJsonCount(1, 'data');

        $product = $this->createProduct($shop, ['brand_id' => $id]);
        $this->asOwnerOf($shop)->deleteJson("/api/v1/brands/{$id}")->assertNoContent();

        $this->asOwnerOf($shop)->getJson("/api/v1/products/{$product->id}")->assertOk()->assertJsonPath('data.brand', null);
        $this->asOwnerOf($shop)->postJson('/api/v1/brands', ['name' => 'PRAN Foods'])->assertCreated();
    }

    // --- Vendors ------------------------------------------------------------

    public function test_vendors_need_a_plan_that_includes_them(): void
    {
        $shop = $this->createShop(); // free plan

        $this->asOwnerOf($shop)->getJson('/api/v1/vendors')->assertForbidden()->assertJsonPath('code', 'MODULE_NOT_AVAILABLE');
        $this->asOwnerOf($shop)->postJson('/api/v1/vendors', ['name' => 'X'])->assertForbidden();
    }

    public function test_vendors_can_be_created_searched_updated_and_deleted(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic');

        $id = $this->asOwnerOf($shop)->postJson('/api/v1/vendors', [
            'name' => 'Jamal Traders', 'phone' => '+8801912345678', 'company_name' => 'Jamal & Sons', 'address' => 'Chawkbazar', 'notes' => 'Delivers on Sunday',
        ])->assertCreated()->assertJsonPath('data.phone', '01912345678')->json('data.id');

        $this->asOwnerOf($shop)->postJson('/api/v1/vendors', ['name' => 'No Phone'])->assertCreated()->assertJsonPath('data.phone', null);
        $this->asOwnerOf($shop)->postJson('/api/v1/vendors', ['name' => 'Bad', 'phone' => '123'])->assertUnprocessable()->assertJsonValidationErrors('phone');
        $this->asOwnerOf($shop)->postJson('/api/v1/vendors', [])->assertUnprocessable()->assertJsonValidationErrors('name');

        $this->asOwnerOf($shop)->getJson('/api/v1/vendors?q=jamal')->assertJsonCount(1, 'data');
        $this->asOwnerOf($shop)->getJson('/api/v1/vendors?q=0191234')->assertJsonCount(1, 'data');
        $this->asOwnerOf($shop)->getJson('/api/v1/vendors?q=sons')->assertJsonCount(1, 'data');
        $this->asOwnerOf($shop)->getJson('/api/v1/vendors')->assertJsonCount(2, 'data');

        $this->asOwnerOf($shop)->patchJson("/api/v1/vendors/{$id}", ['name' => 'Jamal Enterprise', 'phone' => ''])
            ->assertOk()->assertJsonPath('data.name', 'Jamal Enterprise')->assertJsonPath('data.phone', null);

        $this->asOwnerOf($shop)->deleteJson("/api/v1/vendors/{$id}")->assertNoContent();
        $this->asOwnerOf($shop)->getJson("/api/v1/vendors/{$id}")->assertNotFound();
    }

    public function test_one_vendor_can_supply_many_products_and_deleting_it_keeps_them(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic');
        $vendor = $this->tenant()->runFor($shop, fn () => Vendor::factory()->create());

        $a = $this->createProduct($shop, ['name' => 'Apple', 'vendor_id' => $vendor->id]);
        $this->createProduct($shop, ['name' => 'Banana', 'vendor_id' => $vendor->id]);
        $this->createProduct($shop, ['name' => 'Unrelated']);

        $this->asOwnerOf($shop)->getJson("/api/v1/vendors/{$vendor->id}")->assertJsonPath('data.products_count', 2);
        $this->assertSame(['Apple', 'Banana'], $this->asOwnerOf($shop)->getJson("/api/v1/vendors/{$vendor->id}/products")->json('data.*.name'));
        $this->assertSame(['Apple', 'Banana'], $this->asOwnerOf($shop)->getJson("/api/v1/products?vendor_id={$vendor->id}")->json('data.*.name'));

        $this->asOwnerOf($shop)->deleteJson("/api/v1/vendors/{$vendor->id}")->assertNoContent();

        $this->asOwnerOf($shop)->getJson("/api/v1/products/{$a->id}")->assertOk()->assertJsonPath('data.vendor', null);
        $this->tenant()->runFor($shop, fn () => $this->assertSame(3, Product::query()->count()));
    }

    public function test_deleting_a_category_keeps_its_products(): void
    {
        $shop = $this->createShop();
        $categoryId = $this->asOwnerOf($shop)->postJson('/api/v1/categories', ['name' => 'Snacks'])->json('data.id');
        $product = $this->createProduct($shop, ['category_id' => $categoryId]);

        $this->asOwnerOf($shop)->deleteJson("/api/v1/categories/{$categoryId}")->assertNoContent();

        $this->asOwnerOf($shop)->getJson("/api/v1/products/{$product->id}")->assertOk()->assertJsonPath('data.category', null);
        $this->tenant()->runFor($shop, fn () => $this->assertSame(0, Brand::query()->count()));
    }
}
