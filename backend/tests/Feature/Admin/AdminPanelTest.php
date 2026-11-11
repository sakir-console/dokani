<?php

namespace Tests\Feature\Admin;

use App\Enums\BillingCycle;
use App\Enums\ShopStatus;
use App\Enums\SubscriptionStatus;
use App\Livewire\Admin\Auth\Login;
use App\Livewire\Admin\Dashboard;
use App\Livewire\Admin\Shops\Index;
use App\Livewire\Admin\Shops\Show;
use App\Models\Admin;
use App\Models\Plan;
use App\Models\Subscription;
use App\Models\SubscriptionPayment;
use App\Services\Admin\DashboardStats;
use Livewire\Livewire;
use Tests\TestCase;

class AdminPanelTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
    }

    /** Reloaded from the database, as a signed-in admin always is. */
    private function createAdmin(array $attributes = []): Admin
    {
        return Admin::factory()->create($attributes)->fresh();
    }

    // --- Access -------------------------------------------------------------

    public function test_guests_are_sent_to_the_login_page(): void
    {
        $this->get('/admin')->assertRedirect('/admin/login');
        $this->get('/admin/shops')->assertRedirect('/admin/login');
        $this->get('/admin/login')->assertOk()->assertSee('Sign in');
    }

    public function test_a_shop_users_api_token_does_not_open_the_admin_panel(): void
    {
        $shop = $this->createShop();

        $this->withHeaders($this->tokenFor($shop->owner))->get('/admin')->assertRedirect('/admin/login');
        $this->actingAs($shop->owner, 'web')->get('/admin')->assertRedirect('/admin/login');
        $this->actingAs($shop->owner, 'sanctum')->get('/admin/shops')->assertRedirect('/admin/login');
    }

    public function test_an_admin_can_sign_in_and_out(): void
    {
        $admin = $this->createAdmin(['email' => 'boss@example.com']);

        Livewire::test(Login::class)
            ->set('email', 'boss@example.com')->set('password', 'wrong')
            ->call('login')->assertHasErrors('email');
        $this->assertGuest('admin');

        Livewire::test(Login::class)
            ->set('email', 'boss@example.com')->set('password', 'password')
            ->call('login')->assertHasNoErrors()->assertRedirect(route('admin.dashboard'));
        $this->assertAuthenticatedAs($admin, 'admin');

        $this->post('/admin/logout')->assertRedirect('/admin/login');
        $this->assertGuest('admin');
    }

    public function test_admin_login_locks_after_repeated_failures(): void
    {
        $this->createAdmin(['email' => 'boss@example.com']);

        for ($i = 0; $i < 5; $i++) {
            Livewire::test(Login::class)->set('email', 'boss@example.com')->set('password', 'wrong')->call('login');
        }

        Livewire::test(Login::class)
            ->set('email', 'boss@example.com')->set('password', 'password')
            ->call('login')->assertHasErrors('email');
        $this->assertGuest('admin');
    }

    public function test_a_disabled_admin_cannot_sign_in_and_loses_an_open_session(): void
    {
        $admin = $this->createAdmin(['email' => 'boss@example.com']);
        $admin->forceFill(['is_active' => false])->save();

        Livewire::test(Login::class)
            ->set('email', 'boss@example.com')->set('password', 'password')
            ->call('login')->assertHasErrors('email');

        $this->actingAs($admin, 'admin')->get('/admin')->assertRedirect('/admin/login');
    }

    // --- Dashboard ----------------------------------------------------------

    public function test_the_dashboard_shows_real_counts(): void
    {
        $this->createShop();
        $this->createShop();
        $this->createShop(['status' => 'suspended']);
        $paidShop = $this->createShop(['status' => 'inactive']);

        $paidShop->subscriptions()->update(['status' => SubscriptionStatus::Cancelled]);
        $subscription = Subscription::create([
            'shop_id' => $paidShop->id,
            'plan_id' => Plan::query()->where('code', 'standard')->firstOrFail()->id,
            'billing_cycle' => BillingCycle::Yearly,
            'status' => SubscriptionStatus::Active,
            'price' => 6000,
            'starts_at' => now()->subMonth(),
            'ends_at' => now()->addDays(3),
        ]);
        SubscriptionPayment::create([
            'subscription_id' => $subscription->id, 'shop_id' => $paidShop->id,
            'amount' => 6000, 'method' => 'bkash', 'paid_at' => now()->subMonth(),
        ]);

        $stats = app(DashboardStats::class);

        $this->assertSame(['total' => 4, 'active' => 2, 'inactive' => 1, 'suspended' => 1], $stats->shops());
        $this->assertSame(4, $stats->registrations()['total_users']);
        $this->assertSame(4, $stats->registrations()['today']);

        $subscriptions = $stats->subscriptions();
        $this->assertSame(1, $subscriptions['paid']);
        $this->assertSame(3, $subscriptions['free']);
        $this->assertSame(500.0, $subscriptions['mrr']);
        $this->assertSame(6000.0, $subscriptions['total_revenue']);
        $this->assertSame(1, $subscriptions['expiring_7_days']);
        $this->assertSame(0, $subscriptions['expired']);

        $this->assertSame(4, $stats->registrationSeries()->last()['total']);

        $this->actingAs($this->createAdmin(), 'admin')
            ->get('/admin')->assertOk()
            ->assertSeeLivewire(Dashboard::class)
            ->assertSee('Registered shops')
            ->assertSee('৳500');
    }

    public function test_the_dashboard_renders_with_no_data(): void
    {
        $this->actingAs($this->createAdmin(), 'admin')
            ->get('/admin')->assertOk()
            ->assertSee('No shops have registered yet.');
    }

    // --- Shops --------------------------------------------------------------

    public function test_shops_can_be_searched_and_filtered(): void
    {
        $this->actingAs($this->createAdmin(), 'admin');

        $this->createShop(['name' => 'Rahim Grocery', 'shop_type' => 'grocery']);
        $this->createShop(['name' => 'Karim Pharma', 'shop_type' => 'pharmacy', 'status' => 'suspended']);

        Livewire::test(Index::class)
            ->assertSee('Rahim Grocery')->assertSee('Karim Pharma')
            ->set('search', 'rahim')->assertSee('Rahim Grocery')->assertDontSee('Karim Pharma')
            ->set('search', '')->set('status', 'suspended')->assertSee('Karim Pharma')->assertDontSee('Rahim Grocery')
            ->set('status', '')->set('type', 'grocery')->assertSee('Rahim Grocery')->assertDontSee('Karim Pharma')
            ->set('search', 'nobody-has-this-name')->assertSee('No shops match these filters.')
            ->call('clearFilters')->assertSee('Rahim Grocery')->assertSee('Karim Pharma');
    }

    public function test_shops_can_be_found_by_owner_phone(): void
    {
        $this->actingAs($this->createAdmin(), 'admin');

        $shop = $this->createShop(['name' => 'Findable']);
        $this->createShop(['name' => 'Other']);

        Livewire::test(Index::class)->set('search', $shop->owner->phone)->assertSee('Findable')->assertDontSee('Other');
    }

    public function test_suspending_a_shop_blocks_its_users_and_is_audited(): void
    {
        $admin = $this->createAdmin();
        $shop = $this->createShop(['name' => 'Target']);

        $this->actingAs($admin, 'admin');
        Livewire::test(Show::class, ['shopId' => $shop->id])
            ->assertSee('Target')
            ->set('confirmingSuspend', true)
            ->set('reason', 'Fraud report')
            ->call('suspend');

        $shop->refresh();
        $this->assertSame(ShopStatus::Suspended, $shop->status);
        $this->assertSame('Fraud report', $shop->suspended_reason);
        $this->assertDatabaseHas('audit_logs', [
            'shop_id' => $shop->id, 'action' => 'shop.status_changed', 'actor_type' => 'admin', 'actor_id' => $admin->id,
        ]);

        // The mobile API refuses the shop from the very next request.
        $this->asOwnerOf($shop)->getJson('/api/v1/categories')->assertForbidden()->assertJsonPath('code', 'SHOP_SUSPENDED');

        $this->actingAs($admin, 'admin');
        Livewire::test(Show::class, ['shopId' => $shop->id])->call('activate');

        $this->assertSame(ShopStatus::Active, $shop->fresh()->status);
        $this->assertNull($shop->fresh()->suspended_reason);
        $this->asOwnerOf($shop)->getJson('/api/v1/categories')->assertOk();
    }

    public function test_a_shop_can_be_deactivated(): void
    {
        $shop = $this->createShop();
        $this->actingAs($this->createAdmin(), 'admin');

        Livewire::test(Show::class, ['shopId' => $shop->id])->call('deactivate');

        $this->assertSame(ShopStatus::Inactive, $shop->fresh()->status);
    }

    public function test_the_shop_page_shows_plan_and_modules_and_404s_for_unknown_shops(): void
    {
        $shop = $this->createShop(['name' => 'Detail Shop']);
        $this->actingAs($this->createAdmin(), 'admin');

        $this->get("/admin/shops/{$shop->id}")->assertOk()
            ->assertSee('Detail Shop')->assertSee('Free')->assertSee('products')->assertSee($shop->owner->phone);

        $this->get('/admin/shops/999999')->assertNotFound();
    }

    public function test_admin_actions_cannot_be_called_by_a_guest(): void
    {
        $shop = $this->createShop();

        // Livewire update requests go through the same admin middleware as the page.
        $this->get("/admin/shops/{$shop->id}")->assertRedirect('/admin/login');
        $this->assertSame(ShopStatus::Active, $shop->fresh()->status);
    }
}
