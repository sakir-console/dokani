<?php

namespace Tests\Feature\Api;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class ShopProfileTest extends TestCase
{
    public function test_the_owner_can_view_and_update_the_shop(): void
    {
        $shop = $this->createShop(['name' => 'Old name']);

        $this->asOwnerOf($shop)->getJson('/api/v1/shop')->assertOk()->assertJsonPath('data.name', 'Old name');

        $this->asOwnerOf($shop)->patchJson('/api/v1/shop', [
            'name' => 'New name', 'shop_type' => 'pharmacy', 'phone' => '+8801811111111', 'address' => 'Uttara',
        ])->assertOk()
            ->assertJsonPath('data.name', 'New name')
            ->assertJsonPath('data.shop_type', 'pharmacy')
            ->assertJsonPath('data.phone', '01811111111');

        $this->assertDatabaseHas('audit_logs', ['shop_id' => $shop->id, 'action' => 'shop.updated']);
    }

    public function test_protected_shop_fields_cannot_be_changed_through_the_api(): void
    {
        $shop = $this->createShop(['status' => 'active']);
        $otherOwner = $this->createShop()->owner_id;

        $this->asOwnerOf($shop)->patchJson('/api/v1/shop', [
            'name' => 'Still mine', 'status' => 'suspended', 'owner_id' => $otherOwner, 'id' => 999,
        ])->assertOk();

        $fresh = $shop->fresh();
        $this->assertSame('active', $fresh->status->value);
        $this->assertSame($shop->owner_id, $fresh->owner_id);
    }

    public function test_settings_have_defaults_and_only_known_keys_are_stored(): void
    {
        $shop = $this->createShop();

        $this->asOwnerOf($shop)->getJson('/api/v1/shop/settings')
            ->assertOk()
            ->assertJsonPath('data.allow_negative_stock', false)
            ->assertJsonPath('data.receipt_width', '58');

        $this->asOwnerOf($shop)->patchJson('/api/v1/shop/settings', [
            'allow_negative_stock' => true, 'receipt_width' => '80', 'is_admin' => true,
        ])->assertOk()
            ->assertJsonPath('data.allow_negative_stock', true)
            ->assertJsonPath('data.receipt_width', '80')
            ->assertJsonMissingPath('data.is_admin');

        $this->assertArrayNotHasKey('is_admin', $shop->fresh()->settings);

        $this->asOwnerOf($shop)->patchJson('/api/v1/shop/settings', ['receipt_width' => '120'])
            ->assertUnprocessable()->assertJsonValidationErrors('receipt_width');
    }

    public function test_a_logo_is_re_encoded_resized_and_replaces_the_old_one(): void
    {
        Storage::fake('public');
        $shop = $this->createShop();

        $first = $this->asOwnerOf($shop)->post('/api/v1/shop/logo', ['logo' => UploadedFile::fake()->image('logo.png', 2000, 1000)], ['Accept' => 'application/json']);
        $first->assertOk();

        $path = $shop->fresh()->logo_path;
        $this->assertStringStartsWith("shops/{$shop->id}/", $path);
        $this->assertStringEndsWith('.jpg', $path);
        Storage::disk('public')->assertExists($path);

        [$width, $height] = getimagesizefromstring(Storage::disk('public')->get($path));
        $this->assertSame([512, 256], [$width, $height]);

        $this->asOwnerOf($shop)->post('/api/v1/shop/logo', ['logo' => UploadedFile::fake()->image('new.jpg', 100, 100)], ['Accept' => 'application/json'])->assertOk();
        Storage::disk('public')->assertMissing($path);

        $this->asOwnerOf($shop)->deleteJson('/api/v1/shop/logo')->assertOk()->assertJsonPath('data.logo_url', null);
        $this->assertSame([], Storage::disk('public')->allFiles());
    }

    public function test_a_file_that_is_not_an_image_is_rejected(): void
    {
        Storage::fake('public');
        $shop = $this->createShop();

        $this->asOwnerOf($shop)->post('/api/v1/shop/logo', ['logo' => UploadedFile::fake()->create('shell.php', 10, 'application/x-php')], ['Accept' => 'application/json'])
            ->assertUnprocessable();

        // Right extension and MIME type, but the bytes are not an image.
        $this->asOwnerOf($shop)->post('/api/v1/shop/logo', ['logo' => UploadedFile::fake()->createWithContent('fake.jpg', '<?php echo 1;')], ['Accept' => 'application/json'])
            ->assertUnprocessable();

        $this->assertSame([], Storage::disk('public')->allFiles());
        $this->assertNull($shop->fresh()->logo_path);
    }

    public function test_the_user_can_update_their_name_and_language(): void
    {
        $shop = $this->createShop();

        $this->asOwnerOf($shop)->patchJson('/api/v1/me', ['name' => 'Karim', 'locale' => 'en', 'phone' => '01999999999'])
            ->assertOk()
            ->assertJsonPath('data.user.name', 'Karim')
            ->assertJsonPath('data.user.locale', 'en')
            ->assertJsonPath('data.user.phone', $shop->owner->phone);
    }
}
