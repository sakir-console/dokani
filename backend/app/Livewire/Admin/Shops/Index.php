<?php

namespace App\Livewire\Admin\Shops;

use App\Enums\ShopStatus;
use App\Enums\ShopType;
use App\Models\Shop;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\Component;
use Livewire\WithPagination;

#[Layout('components.admin.layout')]
#[Title('Shops')]
class Index extends Component
{
    use WithPagination;

    #[Url(as: 'q', except: '')]
    public string $search = '';

    #[Url(except: '')]
    public string $status = '';

    #[Url(except: '')]
    public string $type = '';

    public function updated(string $property): void
    {
        if (in_array($property, ['search', 'status', 'type'], true)) {
            $this->resetPage();
        }
    }

    public function clearFilters(): void
    {
        $this->reset('search', 'status', 'type');
        $this->resetPage();
    }

    public function render()
    {
        $search = trim($this->search);
        $like = '%'.addcslashes($search, '%_\\').'%';

        $shops = Shop::query()
            ->with(['owner:id,name,phone', 'activeSubscription.plan:id,name,code'])
            ->when($search !== '', fn ($q) => $q->where(fn ($q) => $q
                ->where('name', 'like', $like)
                ->orWhere('phone', 'like', $like)
                ->orWhereHas('owner', fn ($q) => $q->where('name', 'like', $like)->orWhere('phone', 'like', $like))))
            ->when(ShopStatus::tryFrom($this->status), fn ($q, $status) => $q->where('status', $status))
            ->when(ShopType::tryFrom($this->type), fn ($q, $type) => $q->where('shop_type', $type))
            ->latest('id')
            ->paginate(20);

        return view('livewire.admin.shops.index', [
            'shops' => $shops,
            'statuses' => ShopStatus::cases(),
            'types' => ShopType::cases(),
        ]);
    }
}
