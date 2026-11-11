<?php

namespace App\Services\Auth;

use App\Enums\BillingCycle;
use App\Enums\ShopRole;
use App\Enums\ShopStatus;
use App\Enums\SubscriptionStatus;
use App\Models\Plan;
use App\Models\Shop;
use App\Models\ShopUser;
use App\Models\Subscription;
use App\Models\User;
use App\Services\Audit\AuditLogger;
use App\Services\Media\ImageStore;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;

/**
 * Creates an owner account, their shop, the owner membership and the
 * starting subscription on the default plan — all or nothing.
 */
class RegisterShop
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly ImageStore $images,
    ) {}

    /**
     * @param  array{shop_name: string, owner_name: string, phone: string, password: string, shop_type: string, address?: ?string, locale?: ?string}  $data
     * @return array{0: User, 1: Shop}
     */
    public function handle(array $data, ?UploadedFile $logo = null): array
    {
        $logoPath = null;

        try {
            return DB::transaction(function () use ($data, $logo, &$logoPath) {
                $user = new User([
                    'name' => $data['owner_name'],
                    'phone' => $data['phone'],
                    'password' => $data['password'],
                    'locale' => $data['locale'] ?? 'bn',
                ]);
                $user->save();

                $shop = new Shop([
                    'name' => $data['shop_name'],
                    'shop_type' => $data['shop_type'],
                    'phone' => $data['phone'],
                    'address' => $data['address'] ?? null,
                ]);
                $shop->owner_id = $user->id;
                $shop->status = ShopStatus::Active;
                $shop->save();

                if ($logo !== null) {
                    $logoPath = $this->images->store($logo, "shops/{$shop->id}", config('dokani.uploads.logo_max_px'));
                    $shop->logo_path = $logoPath;
                    $shop->save();
                }

                ShopUser::create([
                    'shop_id' => $shop->id,
                    'user_id' => $user->id,
                    'role' => ShopRole::Owner,
                    'is_active' => true,
                ]);

                $plan = Plan::default();
                Subscription::create([
                    'shop_id' => $shop->id,
                    'plan_id' => $plan->id,
                    'billing_cycle' => BillingCycle::Lifetime,
                    'status' => SubscriptionStatus::Active,
                    'price' => 0,
                    'starts_at' => now(),
                    'ends_at' => null,
                ]);

                $this->audit->log('shop.registered', $shop, null, [
                    'name' => $shop->name,
                    'shop_type' => $shop->shop_type->value,
                    'plan' => $plan->code,
                ], $shop->id, $user);

                return [$user, $shop];
            });
        } catch (\Throwable $e) {
            // The database rolled back; do not leave an orphaned file behind.
            $this->images->delete($logoPath);

            throw $e;
        }
    }
}
