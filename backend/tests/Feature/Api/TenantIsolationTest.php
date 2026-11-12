<?php

namespace Tests\Feature\Api;

use App\Enums\ShopRole;
use App\Models\Brand;
use App\Models\Category;
use App\Models\Customer;
use App\Models\Plan;
use App\Models\ProductVariant;
use App\Models\Sale;
use App\Models\Shop;
use App\Models\ShopUser;
use App\Models\Unit;
use App\Models\Vendor;
use App\Services\Tenancy\MissingTenantException;
use Illuminate\Support\Str;
use LogicException;
use Tests\TestCase;

/**
 * Two shops, A and B. Nothing shop A does may read or change shop B's data.
 *
 * Every tenant-owned endpoint added to the API gets a case in this file.
 */
class TenantIsolationTest extends TestCase
{
    private Shop $shopA;

    private Shop $shopB;

    private Category $categoryA;

    private Category $categoryB;

    protected function setUp(): void
    {
        parent::setUp();

        $this->shopA = $this->createShop(['name' => 'Shop A']);
        $this->shopB = $this->createShop(['name' => 'Shop B']);

        $this->categoryA = $this->tenant()->runFor($this->shopA, fn () => Category::factory()->create(['name' => 'Rice']));
        $this->categoryB = $this->tenant()->runFor($this->shopB, fn () => Category::factory()->create(['name' => 'Medicine']));
    }

    // --- Which shop does a request act for? ---------------------------------

    public function test_the_shop_comes_from_the_users_membership(): void
    {
        $this->asOwnerOf($this->shopA)->getJson('/api/v1/me')->assertOk()->assertJsonPath('data.shop.id', $this->shopA->id);
        $this->asOwnerOf($this->shopB)->getJson('/api/v1/me')->assertOk()->assertJsonPath('data.shop.id', $this->shopB->id);
    }

    public function test_the_shop_header_cannot_select_a_shop_the_user_does_not_belong_to(): void
    {
        $this->asOwnerOf($this->shopA)
            ->withHeaders(['X-Shop-Id' => (string) $this->shopB->id])
            ->getJson('/api/v1/categories')
            ->assertForbidden()->assertJsonPath('code', 'SHOP_ACCESS_DENIED');

        $this->asOwnerOf($this->shopA)
            ->withHeaders(['X-Shop-Id' => $this->shopB->id.' OR 1=1'])
            ->getJson('/api/v1/categories')
            ->assertForbidden();
    }

    public function test_the_shop_header_selects_between_the_users_own_shops(): void
    {
        // The owner of A is also a manager in B.
        ShopUser::create(['shop_id' => $this->shopB->id, 'user_id' => $this->shopA->owner_id, 'role' => ShopRole::Manager, 'is_active' => true]);

        $this->asOwnerOf($this->shopA)->getJson('/api/v1/me')
            ->assertJsonPath('data.shop.id', $this->shopA->id)->assertJsonPath('data.role', 'owner');

        $this->asOwnerOf($this->shopA)->withHeaders(['X-Shop-Id' => (string) $this->shopB->id])->getJson('/api/v1/me')
            ->assertJsonPath('data.shop.id', $this->shopB->id)->assertJsonPath('data.role', 'manager');
    }

    public function test_a_deactivated_membership_gives_no_access(): void
    {
        $cashier = $this->addMember($this->shopA, ShopRole::Cashier, active: false);

        $this->asUser($cashier)->getJson('/api/v1/me')->assertForbidden()->assertJsonPath('code', 'NO_SHOP');
    }

    public function test_a_shop_id_in_the_request_body_or_query_is_ignored(): void
    {
        $this->asOwnerOf($this->shopA)
            ->postJson('/api/v1/categories?shop_id='.$this->shopB->id, ['name' => 'Snacks', 'shop_id' => $this->shopB->id])
            ->assertCreated();

        $created = $this->tenant()->withoutTenancy(fn () => Category::query()->where('name', 'Snacks')->firstOrFail());
        $this->assertSame($this->shopA->id, $created->shop_id);
    }

    // --- Categories ---------------------------------------------------------

    public function test_listing_returns_only_the_current_shops_categories(): void
    {
        $this->asOwnerOf($this->shopA)->getJson('/api/v1/categories')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $this->categoryA->id);

        $this->asOwnerOf($this->shopB)->getJson('/api/v1/categories')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $this->categoryB->id);
    }

    public function test_another_shops_category_looks_like_it_does_not_exist(): void
    {
        $missing = $this->asOwnerOf($this->shopA)->getJson('/api/v1/categories/999999');
        $foreign = $this->asOwnerOf($this->shopA)->getJson('/api/v1/categories/'.$this->categoryB->id);

        $foreign->assertNotFound();
        $this->assertSame($missing->json(), $foreign->json(), 'A foreign id must be indistinguishable from a missing one.');
    }

    public function test_another_shops_category_cannot_be_updated_or_deleted(): void
    {
        $this->asOwnerOf($this->shopA)->patchJson('/api/v1/categories/'.$this->categoryB->id, ['name' => 'Hacked'])->assertNotFound();
        $this->asOwnerOf($this->shopA)->deleteJson('/api/v1/categories/'.$this->categoryB->id)->assertNotFound();

        $fresh = $this->tenant()->withoutTenancy(fn () => Category::query()->findOrFail($this->categoryB->id));
        $this->assertSame('Medicine', $fresh->name);
        $this->assertNull($fresh->deleted_at);
    }

    public function test_another_shops_category_cannot_be_used_as_a_parent(): void
    {
        $this->asOwnerOf($this->shopA)
            ->postJson('/api/v1/categories', ['name' => 'Child', 'parent_id' => $this->categoryB->id])
            ->assertUnprocessable()->assertJsonValidationErrors('parent_id');

        $this->asOwnerOf($this->shopA)
            ->patchJson('/api/v1/categories/'.$this->categoryA->id, ['parent_id' => $this->categoryB->id])
            ->assertUnprocessable()->assertJsonValidationErrors('parent_id');
    }

    public function test_two_shops_can_use_the_same_category_name(): void
    {
        $this->asOwnerOf($this->shopA)->postJson('/api/v1/categories', ['name' => 'Medicine'])->assertCreated();
    }

    // --- Catalogue: products, variants, barcodes, brands, units, vendors ------

    public function test_products_of_another_shop_are_invisible_and_untouchable(): void
    {
        $mine = $this->createProduct($this->shopA, ['name' => 'Mine']);
        $theirs = $this->createProduct($this->shopB, ['name' => 'Theirs'], [['purchase_price' => 1, 'selling_price' => 2, 'stock_quantity' => 5, 'barcodes' => ['B-CODE'], 'sku' => 'B-SKU']]);

        $this->assertSame(['Mine'], $this->asOwnerOf($this->shopA)->getJson('/api/v1/products')->json('data.*.name'));
        $this->assertSame([], $this->asOwnerOf($this->shopA)->getJson('/api/v1/products?q=Theirs')->json('data'));
        $this->assertSame([], $this->asOwnerOf($this->shopA)->getJson('/api/v1/products?q=B-CODE')->json('data'));
        $this->assertSame([], $this->asOwnerOf($this->shopA)->getJson('/api/v1/products?q=B-SKU')->json('data'));

        $this->asOwnerOf($this->shopA)->getJson("/api/v1/products/{$theirs->id}")->assertNotFound();
        $this->asOwnerOf($this->shopA)->patchJson("/api/v1/products/{$theirs->id}", ['name' => 'Hacked'])->assertNotFound();
        $this->asOwnerOf($this->shopA)->deleteJson("/api/v1/products/{$theirs->id}")->assertNotFound();
        $this->asOwnerOf($this->shopA)->postJson("/api/v1/products/{$theirs->id}/image")->assertNotFound();
        $this->asOwnerOf($this->shopA)->deleteJson("/api/v1/products/{$theirs->id}/image")->assertNotFound();

        $this->asOwnerOf($this->shopB)->getJson("/api/v1/products/{$theirs->id}")->assertOk()->assertJsonPath('data.name', 'Theirs');
        $this->asOwnerOf($this->shopA)->getJson('/api/v1/stock/summary')->assertJsonPath('data.total_products', 1);
        $this->assertNotNull($mine);
    }

    public function test_a_barcode_resolves_only_inside_its_own_shop_and_can_be_reused_by_another(): void
    {
        $theirs = $this->createProduct($this->shopB, [], [['purchase_price' => 1, 'selling_price' => 2, 'barcodes' => ['8901234567890']]]);

        $this->asOwnerOf($this->shopA)->getJson('/api/v1/barcodes/lookup?code=8901234567890')
            ->assertNotFound()->assertJsonPath('code', 'BARCODE_NOT_FOUND');

        // The same printed barcode is a different product in each shop.
        $mine = $this->createProduct($this->shopA, [], [['purchase_price' => 1, 'selling_price' => 2, 'barcodes' => ['8901234567890']]]);

        $this->asOwnerOf($this->shopA)->getJson('/api/v1/barcodes/lookup?code=8901234567890')->assertJsonPath('data.product.id', $mine->id);
        $this->asOwnerOf($this->shopB)->getJson('/api/v1/barcodes/lookup?code=8901234567890')->assertJsonPath('data.product.id', $theirs->id);
    }

    public function test_a_product_cannot_reference_another_shops_category_brand_unit_or_vendor(): void
    {
        $this->subscribe($this->shopA, 'basic');
        [$brandB, $vendorB, $unitB] = $this->tenant()->runFor($this->shopB, fn () => [
            Brand::factory()->create(),
            Vendor::factory()->create(),
            Unit::create(['name' => 'Sack', 'short_name' => 'sk']),
        ]);

        $base = ['name' => 'X', 'unit_id' => $this->unitId(), 'variants' => [['purchase_price' => 1, 'selling_price' => 2]]];
        $post = fn (array $extra) => $this->asOwnerOf($this->shopA)->postJson('/api/v1/products', array_merge($base, $extra));

        $post(['category_id' => $this->categoryB->id])->assertUnprocessable()->assertJsonValidationErrors('category_id');
        $post(['brand_id' => $brandB->id])->assertUnprocessable()->assertJsonValidationErrors('brand_id');
        $post(['vendor_id' => $vendorB->id])->assertUnprocessable()->assertJsonValidationErrors('vendor_id');
        $post(['unit_id' => $unitB->id])->assertUnprocessable()->assertJsonValidationErrors('unit_id');

        $post(['category_id' => $this->categoryA->id])->assertCreated();
    }

    public function test_another_shops_variant_cannot_be_edited_through_my_product(): void
    {
        $mine = $this->createProduct($this->shopA);
        $theirs = $this->createProduct($this->shopB);
        $foreignVariant = $theirs->variants[0];

        $this->asOwnerOf($this->shopA)->patchJson("/api/v1/products/{$mine->id}", [
            'variants' => [['id' => $foreignVariant->id, 'purchase_price' => 0, 'selling_price' => 0]],
        ])->assertUnprocessable()->assertJsonValidationErrors('variants.0.id');

        $fresh = $this->tenant()->withoutTenancy(fn () => ProductVariant::query()->findOrFail($foreignVariant->id));
        $this->assertSame('60.00', $fresh->selling_price);
        $this->assertSame($theirs->id, $fresh->product_id);
    }

    public function test_stock_of_another_shops_variant_cannot_be_changed_or_read(): void
    {
        $this->subscribe($this->shopA, 'basic');
        $foreign = $this->createProduct($this->shopB)->variants[0];
        $as = fn () => $this->asOwnerOf($this->shopA);

        $as()->postJson('/api/v1/stock/in', ['variant_id' => $foreign->id, 'quantity' => 100])->assertUnprocessable()->assertJsonValidationErrors('variant_id');
        $as()->postJson('/api/v1/stock/out', ['variant_id' => $foreign->id, 'quantity' => 1, 'note' => 'x'])->assertUnprocessable();
        $as()->postJson('/api/v1/stock/adjust', ['variant_id' => $foreign->id, 'new_quantity' => 0])->assertUnprocessable();
        $as()->getJson('/api/v1/stock/movements?variant_id='.$foreign->id)->assertOk()->assertJsonCount(0, 'data');
        $as()->getJson('/api/v1/stock/movements')->assertOk()->assertJsonCount(0, 'data');

        $stock = $this->tenant()->withoutTenancy(fn () => ProductVariant::query()->whereKey($foreign->id)->value('stock_quantity'));
        $this->assertSame('10.000', $stock);
    }

    public function test_brands_units_and_vendors_are_per_shop(): void
    {
        $this->subscribe($this->shopA, 'basic');
        $this->subscribe($this->shopB, 'basic');
        [$brandB, $vendorB, $unitB] = $this->tenant()->runFor($this->shopB, fn () => [
            Brand::factory()->create(['name' => 'B-Brand']),
            Vendor::factory()->create(['name' => 'B-Vendor']),
            Unit::create(['name' => 'Sack', 'short_name' => 'sk']),
        ]);
        $as = fn () => $this->asOwnerOf($this->shopA);

        $as()->getJson('/api/v1/brands')->assertOk()->assertJsonCount(0, 'data');
        $as()->patchJson("/api/v1/brands/{$brandB->id}", ['name' => 'x'])->assertNotFound();
        $as()->deleteJson("/api/v1/brands/{$brandB->id}")->assertNotFound();

        $as()->getJson('/api/v1/vendors')->assertOk()->assertJsonCount(0, 'data');
        $as()->getJson('/api/v1/vendors?q=B-Vendor')->assertJsonCount(0, 'data');
        $as()->getJson("/api/v1/vendors/{$vendorB->id}")->assertNotFound();
        $as()->getJson("/api/v1/vendors/{$vendorB->id}/products")->assertNotFound();
        $as()->getJson("/api/v1/vendors/{$vendorB->id}/purchases")->assertNotFound();
        $as()->patchJson("/api/v1/vendors/{$vendorB->id}", ['name' => 'x'])->assertNotFound();
        $as()->deleteJson("/api/v1/vendors/{$vendorB->id}")->assertNotFound();

        // Built-in units are shared; another shop's custom unit is not.
        $names = $as()->getJson('/api/v1/units')->json('data.*.name');
        $this->assertContains('Piece', $names);
        $this->assertNotContains('Sack', $names);
        $as()->patchJson("/api/v1/units/{$unitB->id}", ['name' => 'x'])->assertNotFound();
        $as()->deleteJson("/api/v1/units/{$unitB->id}")->assertNotFound();

        // Both shops may use the same names.
        $as()->postJson('/api/v1/brands', ['name' => 'B-Brand'])->assertCreated();
        $as()->postJson('/api/v1/units', ['name' => 'Sack', 'short_name' => 'sk'])->assertCreated();
    }

    public function test_each_shops_product_limit_counts_only_its_own_products(): void
    {
        Plan::query()->where('code', 'free')->update(['max_products' => 1]);
        $this->createProduct($this->shopB);

        $this->asOwnerOf($this->shopA)->postJson('/api/v1/products', [
            'name' => 'First', 'unit_id' => $this->unitId(), 'variants' => [['purchase_price' => 1, 'selling_price' => 2]],
        ])->assertCreated();
    }

    // --- Sales, customers, dues, invoices ------------------------------------------

    public function test_customers_are_per_shop_even_with_the_same_phone_number(): void
    {
        $theirs = $this->tenant()->runFor($this->shopB, fn () => Customer::factory()->create(['name' => 'B Customer', 'phone' => '01712345678']));
        $as = fn () => $this->asOwnerOf($this->shopA);

        $as()->getJson('/api/v1/customers')->assertOk()->assertJsonCount(0, 'data');
        $as()->getJson('/api/v1/customers?q=B+Customer')->assertJsonCount(0, 'data');
        $as()->getJson('/api/v1/customers/lookup?phone=01712345678')->assertNotFound()->assertJsonPath('code', 'CUSTOMER_NOT_FOUND');
        $as()->getJson("/api/v1/customers/{$theirs->id}")->assertNotFound();
        $as()->getJson("/api/v1/customers/{$theirs->id}/ledger")->assertNotFound();
        $as()->getJson("/api/v1/customers/{$theirs->id}/sales")->assertNotFound();
        $as()->getJson("/api/v1/customers/{$theirs->id}/payments")->assertNotFound();
        $as()->patchJson("/api/v1/customers/{$theirs->id}", ['name' => 'Hacked'])->assertNotFound();
        $as()->deleteJson("/api/v1/customers/{$theirs->id}")->assertNotFound();
        $as()->postJson("/api/v1/customers/{$theirs->id}/collect-due", ['client_uuid' => (string) Str::uuid(), 'amount' => '1', 'method' => 'cash'])->assertNotFound();

        // The same number in shop A is a separate person with a separate balance.
        $mine = $as()->postJson('/api/v1/customers', ['name' => 'A Customer', 'phone' => '01712345678', 'opening_due' => '50'])->assertCreated()->json('data.id');
        $this->assertNotSame($theirs->id, $mine);
        $this->assertSame('0.00', $this->tenant()->withoutTenancy(fn () => Customer::query()->whereKey($theirs->id)->value('current_due')));
    }

    public function test_a_sale_cannot_use_another_shops_products_or_customers(): void
    {
        $mine = $this->createProduct($this->shopA)->variants[0];
        $foreignVariant = $this->createProduct($this->shopB)->variants[0];
        $foreignCustomer = $this->tenant()->runFor($this->shopB, fn () => Customer::factory()->create());

        $this->asOwnerOf($this->shopA)->postJson('/api/v1/sales', $this->salePayload([[$foreignVariant->id, 1]], '60'))
            ->assertUnprocessable()->assertJsonPath('code', 'PRODUCT_UNAVAILABLE');

        $this->asOwnerOf($this->shopA)->postJson('/api/v1/sales', $this->salePayload([[$mine->id, 1]], '60', [
            'payments' => [], 'due_amount' => '60', 'customer_id' => $foreignCustomer->id,
        ]))->assertUnprocessable()->assertJsonValidationErrors('customer_id');

        $this->tenant()->withoutTenancy(function () use ($foreignVariant, $foreignCustomer) {
            $this->assertSame('10.000', ProductVariant::query()->whereKey($foreignVariant->id)->value('stock_quantity'));
            $this->assertSame('0.00', Customer::query()->whereKey($foreignCustomer->id)->value('current_due'));
            $this->assertSame(0, Sale::query()->count());
        });
    }

    public function test_sales_and_the_dashboard_show_only_the_current_shops_figures(): void
    {
        $variantB = $this->createProduct($this->shopB)->variants[0];
        $saleB = $this->asOwnerOf($this->shopB)->postJson('/api/v1/sales', $this->salePayload([[$variantB->id, 2]], '120', [
            'payments' => [], 'due_amount' => '120', 'customer' => ['name' => 'B Buyer', 'phone' => '01912345678'],
        ]))->assertCreated()->json('data');
        $as = fn () => $this->asOwnerOf($this->shopA);

        $as()->getJson('/api/v1/sales')->assertOk()->assertJsonCount(0, 'data');
        $as()->getJson('/api/v1/sales?q=INV-000001')->assertJsonCount(0, 'data');
        $as()->getJson("/api/v1/sales/{$saleB['id']}")->assertNotFound();
        $as()->get("/api/v1/sales/{$saleB['id']}/invoice.pdf", ['Accept' => 'application/json'])->assertNotFound();
        $as()->postJson("/api/v1/sales/{$saleB['id']}/void", ['reason' => 'sabotage'])->assertNotFound();

        $as()->getJson('/api/v1/dashboard')->assertOk()
            ->assertJsonPath('data.today.sales', '0.00')
            ->assertJsonPath('data.today.orders', 0)
            ->assertJsonPath('data.total_customer_due', '0.00')
            ->assertJsonCount(0, 'data.recent_sales');

        $this->asOwnerOf($this->shopB)->getJson("/api/v1/sales/{$saleB['id']}")->assertOk()->assertJsonPath('data.status', 'completed');
        $this->asOwnerOf($this->shopB)->getJson('/api/v1/dashboard')->assertJsonPath('data.today.sales', '120.00')->assertJsonPath('data.total_customer_due', '120.00');
    }

    // --- The model layer itself ---------------------------------------------

    public function test_a_tenant_model_cannot_be_queried_without_a_shop(): void
    {
        $this->tenant()->clear();

        $this->expectException(MissingTenantException::class);
        Category::query()->count();
    }

    public function test_a_tenant_model_cannot_be_created_without_a_shop(): void
    {
        $this->tenant()->clear();

        $this->expectException(MissingTenantException::class);
        Category::query()->withoutGlobalScopes()->create(['name' => 'Orphan']);
    }

    public function test_the_tenant_context_overrides_a_shop_id_set_by_hand(): void
    {
        $category = $this->tenant()->runFor($this->shopA, function () {
            $category = new Category(['name' => 'Forced']);
            $category->shop_id = $this->shopB->id;
            $category->save();

            return $category;
        });

        $this->assertSame($this->shopA->id, $category->shop_id);
    }

    public function test_a_record_cannot_be_moved_to_another_shop(): void
    {
        $this->expectException(LogicException::class);

        $this->tenant()->runFor($this->shopA, function () {
            $this->categoryA->shop_id = $this->shopB->id;
            $this->categoryA->save();
        });
    }

    public function test_queries_inside_a_shop_never_see_other_shops_rows(): void
    {
        $this->tenant()->runFor($this->shopA, function () {
            $this->assertSame([$this->categoryA->id], Category::query()->pluck('id')->all());
            $this->assertNull(Category::query()->find($this->categoryB->id));
            $this->assertSame(0, Category::query()->whereKey($this->categoryB->id)->update(['name' => 'x']));
            $this->assertSame(0, Category::query()->whereKey($this->categoryB->id)->delete());
        });
    }

    public function test_run_for_restores_the_previous_shop_even_after_an_exception(): void
    {
        $this->tenant()->set($this->shopA);

        try {
            $this->tenant()->runFor($this->shopB, fn () => throw new \RuntimeException('boom'));
        } catch (\RuntimeException) {
        }

        $this->assertSame($this->shopA->id, $this->tenant()->id());
    }

    public function test_cross_shop_reads_need_an_explicit_bypass(): void
    {
        $this->tenant()->clear();

        $all = $this->tenant()->withoutTenancy(fn () => Category::query()->count());

        $this->assertSame(2, $all);
        $this->assertFalse($this->tenant()->isBypassed(), 'The bypass must end with the callback.');
    }
}
