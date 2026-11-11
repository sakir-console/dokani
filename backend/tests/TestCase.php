<?php

namespace Tests;

use App\Enums\ShopRole;
use App\Models\Shop;
use App\Models\ShopUser;
use App\Models\User;
use App\Services\Tenancy\TenantContext;
use Database\Seeders\ModuleSeeder;
use Database\Seeders\PlanSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;

abstract class TestCase extends BaseTestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // Reference data every installation has.
        $this->seed([ModuleSeeder::class, PlanSeeder::class]);
    }

    /** A shop with its owner, exactly as registration leaves it. */
    protected function createShop(array $attributes = []): Shop
    {
        return Shop::factory()->create($attributes);
    }

    protected function addMember(Shop $shop, ShopRole $role, bool $active = true): User
    {
        $user = User::factory()->create();
        ShopUser::create(['shop_id' => $shop->id, 'user_id' => $user->id, 'role' => $role, 'is_active' => $active]);

        return $user;
    }

    /** Authorization header for a real Sanctum token, as the mobile app sends it. */
    protected function tokenFor(User $user): array
    {
        return ['Authorization' => 'Bearer '.$user->createToken('test-device')->plainTextToken];
    }

    /**
     * Make API calls as this user. Uses a real bearer token and clears state
     * left by the previous request, so each call is authenticated from scratch.
     */
    protected function asUser(User $user): static
    {
        $this->resetRequestState();

        return $this->withHeaders($this->tokenFor($user));
    }

    protected function asOwnerOf(Shop $shop): static
    {
        return $this->asUser($shop->owner);
    }

    /** In production every request starts clean; in a test the app instance is reused. */
    protected function resetRequestState(): void
    {
        $this->app['auth']->forgetGuards();
        $this->app->forgetScopedInstances();
        $this->flushHeaders();
    }

    protected function tenant(): TenantContext
    {
        return $this->app->make(TenantContext::class);
    }
}
