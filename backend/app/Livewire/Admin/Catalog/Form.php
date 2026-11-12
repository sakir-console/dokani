<?php

namespace App\Livewire\Admin\Catalog;

use App\Exceptions\ApiException;
use App\Models\GlobalCategory;
use App\Models\GlobalProduct;
use App\Services\Admin\GlobalCatalogService;
use Database\Seeders\UnitSeeder;
use Illuminate\Validation\Rule;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Locked;
use Livewire\Component;
use Livewire\WithFileUploads;

#[Layout('components.admin.layout')]
class Form extends Component
{
    use WithFileUploads;

    #[Locked]
    public ?int $productId = null;

    public string $name = '';

    public string $name_bn = '';

    public string $brand = '';

    public string $description = '';

    public string $default_unit = 'Piece';

    public string $barcode = '';

    public string $category_id = '';

    public string $new_category = '';

    public bool $is_active = true;

    /** @var list<array{id: ?int, name: string, barcode: string}> */
    public array $variants = [];

    public $image = null;

    public ?string $currentImageUrl = null;

    public function mount(?int $productId = null): void
    {
        if ($productId === null) {
            return;
        }

        $product = GlobalProduct::query()->with('variants')->findOrFail($productId);

        $this->productId = $product->id;
        $this->name = $product->name;
        $this->name_bn = (string) $product->name_bn;
        $this->brand = (string) $product->brand;
        $this->description = (string) $product->description;
        $this->default_unit = $product->default_unit;
        $this->barcode = (string) $product->barcode;
        $this->category_id = (string) $product->global_category_id;
        $this->is_active = $product->is_active;
        $this->currentImageUrl = $product->imageUrl();
        $this->variants = $product->variants
            ->map(fn ($v) => ['id' => $v->id, 'name' => $v->name, 'barcode' => (string) $v->barcode])->all();
    }

    public function addVariant(): void
    {
        $this->variants[] = ['id' => null, 'name' => '', 'barcode' => ''];
    }

    public function removeVariant(int $index): void
    {
        unset($this->variants[$index]);
        $this->variants = array_values($this->variants);
    }

    public function addCategory(): void
    {
        $this->validate(['new_category' => ['required', 'string', 'max:100', 'unique:global_categories,name']]);

        $this->category_id = (string) GlobalCategory::create(['name' => trim($this->new_category)])->id;
        $this->new_category = '';
    }

    public function save(GlobalCatalogService $catalog)
    {
        $data = $this->validate([
            'name' => ['required', 'string', 'max:190'],
            'name_bn' => ['nullable', 'string', 'max:190'],
            'brand' => ['nullable', 'string', 'max:100'],
            'description' => ['nullable', 'string', 'max:2000'],
            'default_unit' => ['required', Rule::in(array_keys(UnitSeeder::UNITS))],
            'barcode' => ['nullable', 'string', 'max:64'],
            'category_id' => ['nullable', 'integer', 'exists:global_categories,id'],
            'is_active' => ['boolean'],
            'image' => ['nullable', 'file', 'mimes:jpg,jpeg,png,webp', 'max:'.config('dokani.uploads.product_image_max_kb')],
            'variants' => ['array', 'max:100'],
            'variants.*.name' => ['required', 'string', 'max:120', 'distinct:ignore_case'],
            'variants.*.barcode' => ['nullable', 'string', 'max:64'],
        ], attributes: ['variants.*.name' => 'variant name', 'variants.*.barcode' => 'variant barcode']);

        $product = $this->productId ? GlobalProduct::query()->findOrFail($this->productId) : null;

        try {
            $catalog->save($product, [
                'name' => trim($data['name']),
                'name_bn' => $data['name_bn'] ?: null,
                'brand' => $data['brand'] ?: null,
                'description' => $data['description'] ?: null,
                'default_unit' => $data['default_unit'],
                'barcode' => $data['barcode'] ?: null,
                'global_category_id' => $data['category_id'] ?: null,
                'is_active' => $data['is_active'],
            ], $this->variants, $this->image);
        } catch (ApiException $e) {
            // The uploaded file passed the type check but could not be decoded as an image.
            $this->addError('image', $e->getMessage());

            return null;
        }

        session()->flash('status', $product ? 'Product updated.' : 'Product added to the catalogue.');

        return $this->redirectRoute('admin.catalog.index', navigate: true);
    }

    public function render()
    {
        return view('livewire.admin.catalog.form', [
            'categories' => GlobalCategory::query()->orderBy('name')->get(['id', 'name']),
            'units' => array_keys(UnitSeeder::UNITS),
        ])->title($this->productId ? 'Edit catalogue product' : 'New catalogue product');
    }
}
