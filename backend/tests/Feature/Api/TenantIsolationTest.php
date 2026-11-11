<?php

namespace Tests\Feature\Api;

use App\Enums\ShopRole;
use App\Models\Category;
use App\Models\Shop;
use App\Models\ShopUser;
use App\Services\Tenancy\MissingTenantException;
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
