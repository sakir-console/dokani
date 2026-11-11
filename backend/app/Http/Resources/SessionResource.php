<?php

namespace App\Http\Resources;

use App\Models\Shop;
use App\Models\ShopUser;
use App\Models\User;
use App\Services\Subscription\Entitlements;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Everything the app needs to know about "who am I and what may I use":
 * the user, the current shop, the role held there, the plan and its modules.
 *
 * The app uses this to decide what to show. It is never the enforcement
 * point — every route checks the same rules again on the server.
 */
class SessionResource extends JsonResource
{
    public function __construct(private readonly User $user, private readonly Shop $shop, private readonly ?ShopUser $membership)
    {
        parent::__construct($user);
    }

    public function toArray(Request $request): array
    {
        $entitlements = app(Entitlements::class);
        $plan = $entitlements->plan($this->shop);
        $subscription = $entitlements->subscription($this->shop);
        $role = $this->membership?->role;

        return [
            'user' => new UserResource($this->user),
            'shop' => new ShopResource($this->shop),
            'role' => $role?->value,
            'permissions' => $role?->permissions() ?? [],
            'subscription' => [
                'plan' => ['code' => $plan->code, 'name' => $plan->name],
                'billing_cycle' => $subscription?->billing_cycle->value,
                'ends_at' => $subscription?->ends_at?->toIso8601String(),
                // True when a paid subscription lapsed and the shop fell back to the default plan.
                'is_fallback' => $subscription === null,
            ],
            'modules' => $entitlements->modules($this->shop),
            'limits' => $entitlements->limits($this->shop),
            'settings' => $this->shop->resolvedSettings(),
        ];
    }
}
