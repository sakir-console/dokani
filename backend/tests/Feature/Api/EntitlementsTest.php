<?php

namespace Tests\Feature\Api;

use App\Enums\BillingCycle;
use App\Enums\SubscriptionStatus;
use App\Models\Module;
use App\Models\Plan;
use App\Models\Shop;
use App\Models\ShopModuleOverride;
use App\Models\Subscription;
use App\Services\Subscription\Entitlements;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

class EntitlementsTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        // A route behind a non-core module, to exercise the middleware end to end.
        Route::middleware(['api', 'auth:sanctum', 'tenant', 'shop.active', 'module:reports'])
            ->get('/api/v1/_test/reports', fn () => response()->json(['data' => 'ok']));
    }

    private function subscribe(Shop $shop, string $planCode, ?\DateTimeInterface $endsAt): Subscription
    {
        $shop->subscriptions()->update(['status' => SubscriptionStatus::Cancelled]);

        return Subscription::create([
            'shop_id' => $shop->id,
            'plan_id' => Plan::query()->where('code', $planCode)->firstOrFail()->id,
            'billing_cycle' => BillingCycle::Monthly,
            'status' => SubscriptionStatus::Active,
            'price' => 299,
            'starts_at' => now()->subDay(),
            'ends_at' => $endsAt,
        ]);
    }

    private function entitlements(): Entitlements
    {
        $this->app->forgetScopedInstances();

        return $this->app->make(Entitlements::class);
    }

    public function test_a_new_shop_is_on_the_free_plan_with_only_core_modules(): void
    {
        $shop = $this->createShop();

        $this->assertSame('free', $this->entitlements()->plan($shop)->code);
        $this->assertEqualsCanonicalizing(['products', 'pos', 'customers', 'offline'], $this->entitlements()->modules($shop));
        $this->assertSame(50, $this->entitlements()->limits($shop)['max_products']);
    }

    public function test_a_paid_plan_adds_its_modules(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic', now()->addMonth());

        $modules = $this->entitlements()->modules($shop);

        $this->assertSame('basic', $this->entitlements()->plan($shop)->code);
        $this->assertContains('reports', $modules);
        $this->assertContains('inventory', $modules);
        $this->assertNotContains('exports', $modules);
        $this->assertSame(500, $this->entitlements()->limits($shop)['max_products']);
    }

    public function test_an_expired_subscription_falls_back_to_the_free_plan(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'standard', now()->subMinute());

        $this->assertSame('free', $this->entitlements()->plan($shop)->code);
        $this->assertNull($this->entitlements()->subscription($shop));
        $this->assertNotContains('reports', $this->entitlements()->modules($shop));
    }

    public function test_modules_that_are_not_built_yet_are_never_granted(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'premium', now()->addYear());

        $modules = $this->entitlements()->modules($shop);

        $this->assertContains('exports', $modules);
        $this->assertNotContains('expenses', $modules);
        $this->assertNotContains('branches', $modules);
    }

    public function test_an_admin_override_can_enable_or_disable_a_module_for_one_shop(): void
    {
        $shop = $this->createShop();
        $other = $this->createShop();
        $reports = Module::query()->where('key', 'reports')->firstOrFail();

        ShopModuleOverride::create(['shop_id' => $shop->id, 'module_id' => $reports->id, 'is_enabled' => true]);
        $this->assertContains('reports', $this->entitlements()->modules($shop));
        $this->assertNotContains('reports', $this->entitlements()->modules($other), 'An override affects one shop only.');

        $this->subscribe($shop, 'basic', now()->addMonth());
        ShopModuleOverride::query()->where('shop_id', $shop->id)->update(['is_enabled' => false]);
        $this->assertNotContains('reports', $this->entitlements()->modules($shop));
        $this->assertContains('inventory', $this->entitlements()->modules($shop));
    }

    public function test_core_modules_cannot_be_disabled(): void
    {
        $shop = $this->createShop();
        $pos = Module::query()->where('key', 'pos')->firstOrFail();

        ShopModuleOverride::create(['shop_id' => $shop->id, 'module_id' => $pos->id, 'is_enabled' => false]);

        $this->assertContains('pos', $this->entitlements()->modules($shop));
    }

    public function test_a_route_behind_a_module_is_refused_without_it_and_allowed_with_it(): void
    {
        $shop = $this->createShop();

        $this->asOwnerOf($shop)->getJson('/api/v1/_test/reports')
            ->assertForbidden()->assertJsonPath('code', 'MODULE_NOT_AVAILABLE');

        $this->subscribe($shop, 'basic', now()->addMonth());

        $this->asOwnerOf($shop)->getJson('/api/v1/_test/reports')->assertOk();
    }

    public function test_access_ends_the_moment_the_subscription_expires(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic', now()->addDay());

        $this->asOwnerOf($shop)->getJson('/api/v1/_test/reports')->assertOk();

        $this->travel(2)->days();

        $this->asOwnerOf($shop)->getJson('/api/v1/_test/reports')
            ->assertForbidden()->assertJsonPath('code', 'MODULE_NOT_AVAILABLE');
        $this->asOwnerOf($shop)->getJson('/api/v1/me')
            ->assertJsonPath('data.subscription.plan.code', 'free')
            ->assertJsonPath('data.subscription.is_fallback', true);

        // Core features keep working: the shop is never locked out of its data.
        $this->asOwnerOf($shop)->getJson('/api/v1/categories')->assertOk();
    }

    public function test_the_session_reports_plan_modules_and_limits(): void
    {
        $shop = $this->createShop();
        $this->subscribe($shop, 'standard', now()->addMonth());

        $this->asOwnerOf($shop)->getJson('/api/v1/me')
            ->assertOk()
            ->assertJsonPath('data.subscription.plan.code', 'standard')
            ->assertJsonPath('data.subscription.is_fallback', false)
            ->assertJsonPath('data.limits.max_products', 3000)
            ->assertJsonFragment(['modules' => $this->entitlements()->modules($shop)]);
    }
}
