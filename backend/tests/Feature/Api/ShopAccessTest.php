<?php

namespace Tests\Feature\Api;

use App\Enums\ShopRole;
use Tests\TestCase;

class ShopAccessTest extends TestCase
{
    public function test_a_suspended_shop_is_blocked_but_can_still_see_why(): void
    {
        $shop = $this->createShop(['status' => 'suspended', 'suspended_reason' => 'Payment overdue']);

        $this->asOwnerOf($shop)->getJson('/api/v1/me')
            ->assertOk()->assertJsonPath('data.shop.status', 'suspended');

        $this->asOwnerOf($shop)->getJson('/api/v1/shop')->assertForbidden()->assertJsonPath('code', 'SHOP_SUSPENDED');
        $this->asOwnerOf($shop)->getJson('/api/v1/categories')->assertForbidden()->assertJsonPath('code', 'SHOP_SUSPENDED');
        $this->asOwnerOf($shop)->postJson('/api/v1/categories', ['name' => 'x'])->assertForbidden()->assertJsonPath('code', 'SHOP_SUSPENDED');
    }

    public function test_an_inactive_shop_is_blocked(): void
    {
        $shop = $this->createShop(['status' => 'inactive']);

        $this->asOwnerOf($shop)->getJson('/api/v1/categories')->assertForbidden()->assertJsonPath('code', 'SHOP_INACTIVE');
    }

    public function test_a_soft_deleted_shop_gives_no_access(): void
    {
        $shop = $this->createShop();
        $owner = $shop->owner;
        $shop->delete();

        $this->asUser($owner)->getJson('/api/v1/me')->assertForbidden()->assertJsonPath('code', 'NO_SHOP');
    }

    public function test_a_cashier_cannot_change_shop_details_or_manage_the_catalogue(): void
    {
        $shop = $this->createShop();
        $cashier = $this->addMember($shop, ShopRole::Cashier);

        $this->asUser($cashier)->getJson('/api/v1/shop')->assertOk();
        $this->asUser($cashier)->getJson('/api/v1/categories')->assertOk();

        $this->asUser($cashier)->patchJson('/api/v1/shop', ['name' => 'Mine now'])->assertForbidden()->assertJsonPath('code', 'FORBIDDEN');
        $this->asUser($cashier)->patchJson('/api/v1/shop/settings', ['allow_negative_stock' => true])->assertForbidden();
        $this->asUser($cashier)->postJson('/api/v1/categories', ['name' => 'Snacks'])->assertForbidden();

        $this->assertNotSame('Mine now', $shop->fresh()->name);
    }

    public function test_a_manager_can_manage_the_catalogue_but_not_shop_settings(): void
    {
        $shop = $this->createShop();
        $manager = $this->addMember($shop, ShopRole::Manager);

        $this->asUser($manager)->postJson('/api/v1/categories', ['name' => 'Snacks'])->assertCreated();
        $this->asUser($manager)->patchJson('/api/v1/shop', ['name' => 'Mine now'])->assertForbidden();
    }

    public function test_the_session_lists_the_roles_permissions(): void
    {
        $shop = $this->createShop();
        $cashier = $this->addMember($shop, ShopRole::Cashier);

        $this->asOwnerOf($shop)->getJson('/api/v1/me')->assertJsonPath('data.permissions', ['*']);
        $this->asUser($cashier)->getJson('/api/v1/me')
            ->assertJsonPath('data.role', 'cashier')
            ->assertJsonPath('data.permissions', config('dokani.roles.cashier'));
    }
}
