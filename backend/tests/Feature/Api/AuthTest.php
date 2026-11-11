<?php

namespace Tests\Feature\Api;

use App\Enums\BillingCycle;
use App\Enums\OtpPurpose;
use App\Enums\ShopRole;
use App\Exceptions\ApiException;
use App\Models\OtpCode;
use App\Models\Plan;
use App\Models\Shop;
use App\Models\User;
use App\Services\Auth\OtpService;
use App\Services\Sms\SmsSender;
use Illuminate\Support\Facades\Hash;
use Tests\Support\FakeSmsSender;
use Tests\TestCase;

class AuthTest extends TestCase
{
    private FakeSmsSender $sms;

    protected function setUp(): void
    {
        parent::setUp();
        $this->sms = new FakeSmsSender;
        $this->app->instance(SmsSender::class, $this->sms);
    }

    private function registrationPayload(array $overrides = []): array
    {
        return array_merge([
            'shop_name' => 'Rahim Store',
            'owner_name' => 'Rahim Uddin',
            'phone' => '01712345678',
            'password' => 'secret-pass',
            'shop_type' => 'grocery',
            'address' => 'Mirpur 10, Dhaka',
            'device_name' => 'Pixel 4a',
        ], $overrides);
    }

    // --- Registration -------------------------------------------------------

    public function test_registration_creates_owner_shop_membership_and_free_subscription(): void
    {
        $response = $this->postJson('/api/v1/auth/register', $this->registrationPayload());

        $response->assertCreated()
            ->assertJsonPath('data.user.phone', '01712345678')
            ->assertJsonPath('data.shop.name', 'Rahim Store')
            ->assertJsonPath('data.shop.status', 'active')
            ->assertJsonPath('data.shop.currency', 'BDT')
            ->assertJsonPath('data.shop.timezone', 'Asia/Dhaka')
            ->assertJsonPath('data.user.locale', 'bn')
            ->assertJsonPath('data.role', 'owner')
            ->assertJsonPath('data.subscription.plan.code', 'free')
            ->assertJsonStructure(['data' => ['token', 'modules', 'limits', 'permissions', 'settings']]);

        $user = User::query()->where('phone', '01712345678')->firstOrFail();
        $shop = Shop::query()->where('owner_id', $user->id)->firstOrFail();

        $this->assertTrue(Hash::check('secret-pass', $user->password));
        $this->assertDatabaseHas('shop_users', ['shop_id' => $shop->id, 'user_id' => $user->id, 'role' => ShopRole::Owner->value]);
        $this->assertDatabaseHas('subscriptions', ['shop_id' => $shop->id, 'billing_cycle' => BillingCycle::Lifetime->value, 'status' => 'active']);
        $this->assertDatabaseHas('audit_logs', ['shop_id' => $shop->id, 'action' => 'shop.registered', 'actor_type' => 'user', 'actor_id' => $user->id]);

        // The returned token works straight away.
        $this->resetRequestState();
        $this->withToken($response->json('data.token'))->getJson('/api/v1/me')
            ->assertOk()->assertJsonPath('data.shop.id', $shop->id);
    }

    public function test_registration_never_returns_the_password(): void
    {
        $response = $this->postJson('/api/v1/auth/register', $this->registrationPayload());

        $this->assertStringNotContainsString('password', $response->getContent());
    }

    public function test_the_same_phone_in_another_format_cannot_register_twice(): void
    {
        $this->postJson('/api/v1/auth/register', $this->registrationPayload())->assertCreated();

        $this->postJson('/api/v1/auth/register', $this->registrationPayload(['phone' => '+880 1712-345678']))
            ->assertUnprocessable()
            ->assertJsonPath('code', 'VALIDATION_FAILED')
            ->assertJsonValidationErrors('phone');

        $this->assertSame(1, User::query()->count());
        $this->assertSame(1, Shop::query()->count());
    }

    public function test_registration_validates_its_input(): void
    {
        $this->postJson('/api/v1/auth/register', [
            'shop_name' => '',
            'owner_name' => '',
            'phone' => '12345',
            'password' => 'short',
            'shop_type' => 'spaceship',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors(['shop_name', 'owner_name', 'phone', 'password', 'shop_type', 'device_name']);

        $this->assertSame(0, User::query()->count());
    }

    public function test_a_failed_registration_leaves_nothing_behind(): void
    {
        // No default plan → the subscription step fails → everything rolls back.
        Plan::query()->update(['is_default' => false]);

        $this->postJson('/api/v1/auth/register', $this->registrationPayload())->assertNotFound();

        $this->assertSame(0, User::query()->count());
        $this->assertSame(0, Shop::query()->count());
    }

    // --- Login --------------------------------------------------------------

    public function test_login_returns_a_token_and_the_session(): void
    {
        $shop = $this->createShop();

        $response = $this->postJson('/api/v1/auth/login', [
            'phone' => '+88'.$shop->owner->phone,
            'password' => 'password',
            'device_name' => 'Pixel 4a',
        ]);

        $response->assertOk()
            ->assertJsonPath('data.shop.id', $shop->id)
            ->assertJsonPath('data.role', 'owner')
            ->assertJsonStructure(['data' => ['token']]);

        $this->assertNotNull($shop->owner->fresh()->last_login_at);
    }

    public function test_wrong_password_and_unknown_phone_get_the_same_answer(): void
    {
        $shop = $this->createShop();

        $wrongPassword = $this->postJson('/api/v1/auth/login', ['phone' => $shop->owner->phone, 'password' => 'nope-nope', 'device_name' => 'x']);
        $unknownPhone = $this->postJson('/api/v1/auth/login', ['phone' => '01999999999', 'password' => 'nope-nope', 'device_name' => 'x']);

        $wrongPassword->assertUnprocessable()->assertJsonPath('code', 'INVALID_CREDENTIALS');
        $this->assertSame($wrongPassword->json(), $unknownPhone->json());
        $this->assertSame($wrongPassword->status(), $unknownPhone->status());
    }

    public function test_a_disabled_account_cannot_log_in_or_use_an_existing_token(): void
    {
        $shop = $this->createShop();
        $headers = $this->tokenFor($shop->owner);
        $shop->owner->forceFill(['is_active' => false])->save();

        $this->postJson('/api/v1/auth/login', ['phone' => $shop->owner->phone, 'password' => 'password', 'device_name' => 'x'])
            ->assertForbidden()->assertJsonPath('code', 'ACCOUNT_DISABLED');

        $this->resetRequestState();
        $this->withHeaders($headers)->getJson('/api/v1/me')
            ->assertForbidden()->assertJsonPath('code', 'ACCOUNT_DISABLED');
    }

    public function test_login_is_rate_limited_per_phone(): void
    {
        $shop = $this->createShop();
        $attempt = fn () => $this->postJson('/api/v1/auth/login', ['phone' => $shop->owner->phone, 'password' => 'wrong-pass', 'device_name' => 'x']);

        for ($i = 0; $i < 5; $i++) {
            $attempt()->assertUnprocessable();
        }

        $attempt()->assertTooManyRequests()->assertJsonPath('code', 'RATE_LIMITED');
    }

    public function test_protected_routes_require_a_token(): void
    {
        $this->getJson('/api/v1/me')->assertUnauthorized()->assertJsonPath('code', 'UNAUTHENTICATED');
        $this->withToken('not-a-real-token')->getJson('/api/v1/me')->assertUnauthorized();
    }

    public function test_logout_revokes_only_the_current_token(): void
    {
        $shop = $this->createShop();
        $phone = $this->tokenFor($shop->owner);
        $tablet = $this->tokenFor($shop->owner);

        $this->withHeaders($phone)->postJson('/api/v1/auth/logout')->assertOk();

        $this->resetRequestState();
        $this->withHeaders($phone)->getJson('/api/v1/me')->assertUnauthorized();

        $this->resetRequestState();
        $this->withHeaders($tablet)->getJson('/api/v1/me')->assertOk();
    }

    // --- Password reset by OTP ---------------------------------------------

    public function test_forgot_password_sends_a_code_to_a_registered_number(): void
    {
        $shop = $this->createShop();

        $this->postJson('/api/v1/auth/forgot-password', ['phone' => $shop->owner->phone])->assertOk();

        $this->assertCount(1, $this->sms->sent);
        $this->assertSame($shop->owner->phone, $this->sms->sent[0]['phone']);

        // Only a hash is stored.
        $code = $this->sms->lastCodeFor($shop->owner->phone);
        $stored = OtpCode::query()->firstOrFail();
        $this->assertNotSame($code, $stored->code_hash);
        $this->assertTrue(Hash::check($code, $stored->code_hash));
    }

    public function test_forgot_password_does_not_reveal_whether_a_number_is_registered(): void
    {
        $shop = $this->createShop();

        $known = $this->postJson('/api/v1/auth/forgot-password', ['phone' => $shop->owner->phone]);
        $unknown = $this->postJson('/api/v1/auth/forgot-password', ['phone' => '01999999999']);

        $known->assertOk();
        $this->assertSame($known->json(), $unknown->json());
        $this->assertCount(1, $this->sms->sent, 'No SMS is sent to an unregistered number.');
    }

    public function test_a_second_code_cannot_be_requested_immediately(): void
    {
        $shop = $this->createShop();

        $this->postJson('/api/v1/auth/forgot-password', ['phone' => $shop->owner->phone])->assertOk();
        $this->postJson('/api/v1/auth/forgot-password', ['phone' => $shop->owner->phone])->assertOk();

        $this->assertCount(1, $this->sms->sent);
    }

    public function test_reset_password_with_the_right_code_changes_the_password_and_signs_out_all_devices(): void
    {
        $shop = $this->createShop();
        $oldToken = $this->tokenFor($shop->owner);

        $this->postJson('/api/v1/auth/forgot-password', ['phone' => $shop->owner->phone])->assertOk();
        $code = $this->sms->lastCodeFor($shop->owner->phone);

        $this->postJson('/api/v1/auth/reset-password', [
            'phone' => $shop->owner->phone, 'otp' => $code, 'password' => 'brand-new-pass',
        ])->assertOk();

        $this->assertTrue(Hash::check('brand-new-pass', $shop->owner->fresh()->password));
        $this->assertSame(0, $shop->owner->tokens()->count());

        $this->resetRequestState();
        $this->withHeaders($oldToken)->getJson('/api/v1/me')->assertUnauthorized();

        // A code works once.
        $this->postJson('/api/v1/auth/reset-password', [
            'phone' => $shop->owner->phone, 'otp' => $code, 'password' => 'another-pass-1',
        ])->assertUnprocessable()->assertJsonPath('code', 'OTP_INVALID');
    }

    public function test_a_wrong_code_is_rejected_and_the_code_locks_after_too_many_attempts(): void
    {
        $shop = $this->createShop();
        $phone = $shop->owner->phone;
        $otp = app(OtpService::class);

        $otp->send($phone, OtpPurpose::ResetPassword);
        $code = $this->sms->lastCodeFor($phone);
        $wrong = $code === '000000' ? '111111' : '000000';

        for ($i = 0; $i < config('dokani.otp.max_attempts'); $i++) {
            try {
                $otp->verify($phone, OtpPurpose::ResetPassword, $wrong);
                $this->fail('A wrong code was accepted.');
            } catch (ApiException $e) {
                $this->assertSame('OTP_INVALID', $e->errorCode);
            }
        }

        // Even the right code is refused once the attempts are used up.
        $this->expectException(ApiException::class);
        $otp->verify($phone, OtpPurpose::ResetPassword, $code);
    }

    public function test_an_expired_code_is_rejected(): void
    {
        $shop = $this->createShop();

        $this->postJson('/api/v1/auth/forgot-password', ['phone' => $shop->owner->phone])->assertOk();
        $code = $this->sms->lastCodeFor($shop->owner->phone);

        $this->travel(config('dokani.otp.ttl_minutes') + 1)->minutes();

        $this->postJson('/api/v1/auth/reset-password', [
            'phone' => $shop->owner->phone, 'otp' => $code, 'password' => 'brand-new-pass',
        ])->assertUnprocessable()->assertJsonPath('code', 'OTP_INVALID');

        $this->assertTrue(Hash::check('password', $shop->owner->fresh()->password));
    }

    // --- Change password ----------------------------------------------------

    public function test_change_password_requires_the_current_password_and_signs_out_other_devices(): void
    {
        $shop = $this->createShop();
        $thisDevice = $this->tokenFor($shop->owner);
        $otherDevice = $this->tokenFor($shop->owner);

        $this->withHeaders($thisDevice)->postJson('/api/v1/auth/change-password', [
            'current_password' => 'wrong-one', 'password' => 'brand-new-pass',
        ])->assertUnprocessable()->assertJsonPath('code', 'CURRENT_PASSWORD_INCORRECT');

        $this->resetRequestState();
        $this->withHeaders($thisDevice)->postJson('/api/v1/auth/change-password', [
            'current_password' => 'password', 'password' => 'brand-new-pass',
        ])->assertOk();

        $this->assertTrue(Hash::check('brand-new-pass', $shop->owner->fresh()->password));

        $this->resetRequestState();
        $this->withHeaders($thisDevice)->getJson('/api/v1/me')->assertOk();
        $this->resetRequestState();
        $this->withHeaders($otherDevice)->getJson('/api/v1/me')->assertUnauthorized();
    }

    // --- Misc ---------------------------------------------------------------

    public function test_meta_is_public_and_lists_shop_types(): void
    {
        $this->getJson('/api/v1/meta')->assertOk()
            ->assertJsonPath('data.api_version', 'v1')
            ->assertJsonCount(11, 'data.shop_types');
    }

    public function test_errors_are_translated_to_bangla_on_request(): void
    {
        $this->withHeaders(['Accept-Language' => 'bn'])
            ->postJson('/api/v1/auth/login', ['phone' => '01999999999', 'password' => 'whatever1', 'device_name' => 'x'])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'মোবাইল নম্বর অথবা পাসওয়ার্ড সঠিক নয়।');
    }

    public function test_unknown_api_routes_return_the_json_error_shape(): void
    {
        $this->getJson('/api/v1/does-not-exist')->assertNotFound()->assertJsonPath('code', 'NOT_FOUND');
    }
}
