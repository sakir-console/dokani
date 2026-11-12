<?php

namespace App\Livewire\Admin\Catalog;

use App\Models\GlobalCategory;
use App\Models\GlobalProduct;
use App\Services\Admin\GlobalCatalogService;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\Component;
use Livewire\WithPagination;

#[Layout('components.admin.layout')]
#[Title('Global catalogue')]
class Index extends Component
{
    use WithPagination;

    #[Url(as: 'q', except: '')]
    public string $search = '';

    #[Url(except: '')]
    public string $category = '';

    public function updated(string $property): void
    {
        if (in_array($property, ['search', 'category'], true)) {
            $this->resetPage();
        }
    }

    public function toggleActive(int $id): void
    {
        $product = GlobalProduct::query()->findOrFail($id);
        $product->update(['is_active' => ! $product->is_active]);
    }

    public function delete(int $id, GlobalCatalogService $catalog): void
    {
        $catalog->delete(GlobalProduct::query()->findOrFail($id));
        session()->flash('status', 'Product removed from the catalogue. Shops that imported it keep their copy.');
    }

    public function render()
    {
        $term = trim($this->search);
        $like = '%'.addcslashes($term, '%_\\').'%';

        return view('livewire.admin.catalog.index', [
            'products' => GlobalProduct::query()
                ->with('category:id,name')->withCount('variants')
                ->when($term !== '', fn ($q) => $q->where(fn ($q) => $q
                    ->where('name', 'like', $like)->orWhere('name_bn', 'like', $like)
                    ->orWhere('brand', 'like', $like)->orWhere('barcode', $term)))
                ->when(ctype_digit($this->category), fn ($q) => $q->where('global_category_id', (int) $this->category))
                ->orderBy('name')
                ->paginate(20),
            'categories' => GlobalCategory::query()->orderBy('name')->get(['id', 'name']),
        ]);
    }
}
