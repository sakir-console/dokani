<?php

namespace Database\Factories;

use App\Enums\BillingCycle;
use App\Enums\ShopRole;
use App\Enums\ShopStatus;
use App\Enums\ShopType;
use App\Enums\SubscriptionStatus;
use App\Models\Plan;
use App\Models\Shop;
use App\Models\ShopUser;
use App\Models\Subscription;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Shop> */
class ShopFactory extends Factory
{
    public function definition(): array
    {
        return [
            'owner_id' => User::factory(),
            'name' => fake()->company().' Store',
            'shop_type' => fake()->randomElement(ShopType::cases()),
            'phone' => '01'.fake()->numerify('8########'),
            'address' => fake()->address(),
            'status' => ShopStatus::Active,
        ];
    }

    /** Mirrors what registration creates: owner membership + default-plan subscription. */
    public function configure(): static
    {
        return $this->afterCreating(function (Shop $shop) {
            ShopUser::firstOrCreate(
                ['shop_id' => $shop->id, 'user_id' => $shop->owner_id],
                ['role' => ShopRole::Owner, 'is_active' => true],
            );

            if (! $shop->subscriptions()->exists()) {
                Subscription::create([
                    'shop_id' => $shop->id,
                    'plan_id' => Plan::default()->id,
                    'billing_cycle' => BillingCycle::Lifetime,
                    'status' => SubscriptionStatus::Active,
                    'price' => 0,
                    'starts_at' => now(),
                ]);
            }
        });
    }

    public function suspended(): static
    {
        return $this->state(['status' => ShopStatus::Suspended, 'suspended_reason' => 'Test']);
    }

    public function inactive(): static
    {
        return $this->state(['status' => ShopStatus::Inactive]);
    }
}
