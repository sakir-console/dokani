<?php

namespace Tests\Feature\Admin;

use App\Livewire\Admin\Catalog\Form;
use App\Livewire\Admin\Catalog\Index;
use App\Models\Admin;
use App\Models\GlobalCategory;
use App\Models\GlobalProduct;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Livewire\Livewire;
use Tests\TestCase;

class GlobalCatalogAdminTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
    }

    private function signIn(): Admin
    {
        $admin = Admin::factory()->create()->fresh();
        $this->actingAs($admin, 'admin');

        return $admin;
    }

    public function test_the_catalogue_pages_require_an_admin(): void
    {
        $product = GlobalProduct::factory()->create();

        $this->get('/admin/catalog')->assertRedirect('/admin/login');
        $this->get('/admin/catalog/create')->assertRedirect('/admin/login');
        $this->get("/admin/catalog/{$product->id}/edit")->assertRedirect('/admin/login');

        $this->signIn();
        $this->get('/admin/catalog')->assertOk()->assertSee($product->name);
        $this->get('/admin/catalog/create')->assertOk();
        $this->get("/admin/catalog/{$product->id}/edit")->assertOk()->assertSee($product->name);
        $this->get('/admin/catalog/999999/edit')->assertNotFound();
    }

    public function test_an_admin_can_add_a_product_with_category_image_and_variants(): void
    {
        Storage::fake('public');
        $admin = $this->signIn();

        Livewire::test(Form::class)
            ->set('new_category', 'Personal care')->call('addCategory')
            ->set('name', 'Sunsilk Shampoo')
            ->set('name_bn', 'সানসিল্ক শ্যাম্পু')
            ->set('brand', 'Sunsilk')
            ->set('default_unit', 'Bottle')
            ->set('image', UploadedFile::fake()->image('shampoo.png', 1200, 1200))
            ->call('addVariant')->set('variants.0.name', '180ml')->set('variants.0.barcode', 'SS-180')
            ->call('addVariant')->set('variants.1.name', '340ml')
            ->call('save')
            ->assertHasNoErrors()
            ->assertRedirect(route('admin.catalog.index'));

        $product = GlobalProduct::query()->with(['variants', 'category'])->sole();
        $this->assertSame('Sunsilk Shampoo', $product->name);
        $this->assertSame('সানসিল্ক শ্যাম্পু', $product->name_bn);
        $this->assertSame('Personal care', $product->category->name);
        $this->assertSame('Bottle', $product->default_unit);
        $this->assertSame(['180ml', '340ml'], $product->variants->pluck('name')->all());
        $this->assertSame('SS-180', $product->variants[0]->barcode);
        $this->assertNull($product->variants[1]->barcode);

        Storage::disk('public')->assertExists($product->image_path);
        $this->assertSame([800, 800], array_slice(getimagesizefromstring(Storage::disk('public')->get($product->image_path)), 0, 2));

        $this->assertDatabaseHas('audit_logs', ['action' => 'global_product.created', 'actor_type' => 'admin', 'actor_id' => $admin->id]);
    }

    public function test_the_form_validates_its_input(): void
    {
        $this->signIn();
        GlobalCategory::create(['name' => 'Existing']);

        Livewire::test(Form::class)
            ->set('name', '')
            ->set('default_unit', 'Spaceship')
            ->call('addVariant')->set('variants.0.name', 'Red')
            ->call('addVariant')->set('variants.1.name', 'red')
            ->call('addVariant')
            ->call('save')
            ->assertHasErrors(['name', 'default_unit', 'variants.1.name', 'variants.2.name']);

        Livewire::test(Form::class)->set('new_category', 'Existing')->call('addCategory')->assertHasErrors('new_category');

        $this->assertSame(0, GlobalProduct::query()->count());
    }

    public function test_editing_updates_the_product_and_syncs_its_variants(): void
    {
        $this->signIn();
        $product = GlobalProduct::factory()->create(['name' => 'Old']);
        $keep = $product->variants()->create(['name' => 'Keep']);
        $drop = $product->variants()->create(['name' => 'Drop']);

        Livewire::test(Form::class, ['productId' => $product->id])
            ->assertSet('name', 'Old')
            ->assertSet('variants.1.name', 'Drop')
            ->set('name', 'New')
            ->set('variants.0.name', 'Kept')
            ->call('removeVariant', 1)
            ->call('addVariant')->set('variants.1.name', 'Added')
            ->call('save')
            ->assertHasNoErrors();

        $product->refresh();
        $this->assertSame('New', $product->name);
        $this->assertSame(['Kept', 'Added'], $product->variants->pluck('name')->all());
        $this->assertSame($keep->id, $product->variants[0]->id);
        $this->assertDatabaseMissing('global_product_variants', ['id' => $drop->id]);
    }

    public function test_products_can_be_searched_hidden_and_deleted(): void
    {
        $this->signIn();
        $cola = GlobalProduct::factory()->create(['name' => 'Coca-Cola', 'barcode' => '5449000000996']);
        GlobalProduct::factory()->create(['name' => 'Lux Soap']);

        Livewire::test(Index::class)
            ->assertSee('Coca-Cola')->assertSee('Lux Soap')
            ->set('search', 'cola')->assertSee('Coca-Cola')->assertDontSee('Lux Soap')
            ->set('search', '5449000000996')->assertSee('Coca-Cola')
            ->set('search', '')
            ->call('toggleActive', $cola->id);

        $this->assertFalse($cola->fresh()->is_active);

        Livewire::test(Index::class)->call('delete', $cola->id)->assertDontSee('Coca-Cola');
        $this->assertSoftDeleted('global_products', ['id' => $cola->id]);
    }

    public function test_removing_a_catalogue_product_leaves_shop_copies_intact(): void
    {
        $this->signIn();
        $shop = $this->createShop();
        $this->subscribe($shop, 'basic');
        $global = GlobalProduct::factory()->create(['name' => 'Imported thing']);

        $productId = $this->asOwnerOf($shop)->postJson("/api/v1/global-catalog/products/{$global->id}/import", ['selling_price' => 10])->assertCreated()->json('data.id');

        $this->signIn();
        Livewire::test(Index::class)->call('delete', $global->id);

        $this->asOwnerOf($shop)->getJson("/api/v1/products/{$productId}")->assertOk()->assertJsonPath('data.name', 'Imported thing');
        $this->asOwnerOf($shop)->getJson('/api/v1/global-catalog/products')->assertJsonCount(0, 'data');
    }
}
