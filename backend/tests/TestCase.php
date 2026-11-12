<?php

namespace Tests;

use App\Enums\BillingCycle;
use App\Enums\ShopRole;
use App\Enums\SubscriptionStatus;
use App\Models\Plan;
use App\Models\Product;
use App\Models\Shop;
use App\Models\ShopUser;
use App\Models\Subscription;
use App\Models\Unit;
use App\Models\User;
use App\Services\Catalog\ProductService;
use App\Services\Tenancy\TenantContext;
use Database\Seeders\ModuleSeeder;
use Database\Seeders\PlanSeeder;
use Database\Seeders\UnitSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Str;

abstract class TestCase extends BaseTestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // Reference data every installation has.
        $this->seed([ModuleSeeder::class, PlanSeeder::class, UnitSeeder::class]);
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

    /** Puts the shop on a paid plan (replacing whatever it had). */
    protected function subscribe(Shop $shop, string $planCode, ?\DateTimeInterface $endsAt = null): Subscription
    {
        $shop->subscriptions()->update(['status' => SubscriptionStatus::Cancelled]);

        return Subscription::create([
            'shop_id' => $shop->id,
            'plan_id' => Plan::query()->where('code', $planCode)->firstOrFail()->id,
            'billing_cycle' => BillingCycle::Monthly,
            'status' => SubscriptionStatus::Active,
            'price' => 299,
            'starts_at' => now()->subDay(),
            'ends_at' => $endsAt ?? now()->addMonth(),
        ]);
    }

    protected function unitId(string $name = 'Piece'): int
    {
        return $this->tenant()->withoutTenancy(fn () => Unit::query()->whereNull('shop_id')->where('name', $name)->valueOrFail('id'));
    }

    /**
     * A product created the way the API creates it (through ProductService).
     * With no variants given it is a simple product: price 60, cost 50, stock 10.
     */
    protected function createProduct(Shop $shop, array $attributes = [], ?array $variants = null): Product
    {
        return $this->tenant()->runFor($shop, fn () => app(ProductService::class)->create(array_merge([
            'name' => 'Product '.fake()->unique()->numberBetween(1, 999999),
            'unit_id' => $this->unitId(),
            'has_variants' => $variants !== null && count($variants) > 1,
            'variants' => $variants ?? [['purchase_price' => '50', 'selling_price' => '60', 'stock_quantity' => '10']],
        ], $attributes), $shop->owner)->load('variants.barcodes'));
    }

    /**
     * A sale request as the app sends it. $lines is [[variantId, quantity], ...];
     * each line may add a third element with extra fields (unit_price, discount_amount).
     * Totals default to "paid in full in cash" unless overridden.
     */
    protected function salePayload(array $lines, string $grandTotal, array $overrides = []): array
    {
        return array_merge([
            'client_uuid' => (string) Str::uuid(),
            'items' => array_map(fn (array $line) => ['variant_id' => $line[0], 'quantity' => (string) $line[1]] + ($line[2] ?? []), $lines),
            'grand_total' => $grandTotal,
            'payments' => [['method' => 'cash', 'amount' => $grandTotal]],
            'due_amount' => '0',
        ], $overrides);
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
