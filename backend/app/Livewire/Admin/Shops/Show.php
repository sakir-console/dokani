<?php

namespace App\Livewire\Admin\Shops;

use App\Enums\ShopStatus;
use App\Models\AuditLog;
use App\Models\Shop;
use App\Services\Admin\ShopAdministration;
use App\Services\Subscription\Entitlements;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Locked;
use Livewire\Attributes\Validate;
use Livewire\Component;

#[Layout('components.admin.layout')]
class Show extends Component
{
    #[Locked]
    public int $shopId;

    #[Validate('nullable|string|max:255')]
    public string $reason = '';

    public bool $confirmingSuspend = false;

    public function mount(int $shopId): void
    {
        $this->shopId = Shop::query()->findOrFail($shopId)->id;
    }

    public function activate(ShopAdministration $administration): void
    {
        $administration->changeStatus($this->shop(), ShopStatus::Active);
        session()->flash('status', 'Shop is now active.');
    }

    public function deactivate(ShopAdministration $administration): void
    {
        $administration->changeStatus($this->shop(), ShopStatus::Inactive);
        session()->flash('status', 'Shop has been deactivated.');
    }

    public function suspend(ShopAdministration $administration): void
    {
        $this->validate();
        $administration->changeStatus($this->shop(), ShopStatus::Suspended, trim($this->reason));

        $this->reset('reason', 'confirmingSuspend');
        session()->flash('status', 'Shop has been suspended.');
    }

    public function render(Entitlements $entitlements)
    {
        $shop = $this->shop()->load(['owner', 'memberships.user:id,name,phone']);

        return view('livewire.admin.shops.show', [
            'shop' => $shop,
            'plan' => $entitlements->plan($shop),
            'subscription' => $entitlements->subscription($shop),
            'modules' => $entitlements->modules($shop),
            'limits' => $entitlements->limits($shop),
            'activity' => AuditLog::query()->where('shop_id', $shop->id)->latest('id')->limit(15)->get(),
        ])->title($shop->name);
    }

    private function shop(): Shop
    {
        return Shop::query()->findOrFail($this->shopId);
    }
}
