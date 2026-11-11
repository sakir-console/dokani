<?php

namespace App\Services\Tenancy;

use App\Models\Shop;
use App\Models\ShopUser;
use LogicException;

/**
 * The shop the current request (or job) is acting for.
 *
 * Set once by the ResolveShop middleware from the authenticated user's
 * membership. Tenant models read it to scope every query; if it is empty
 * they refuse to run rather than return every shop's rows.
 */
class TenantContext
{
    private ?Shop $shop = null;

    private ?ShopUser $membership = null;

    private bool $bypassed = false;

    public function set(Shop $shop, ?ShopUser $membership = null): void
    {
        $this->shop = $shop;
        $this->membership = $membership;
    }

    public function clear(): void
    {
        $this->shop = null;
        $this->membership = null;
    }

    public function has(): bool
    {
        return $this->shop !== null;
    }

    public function shop(): Shop
    {
        return $this->shop ?? throw new LogicException('No shop in the tenant context.');
    }

    public function id(): int
    {
        return $this->shop()->id;
    }

    public function idOrNull(): ?int
    {
        return $this->shop?->id;
    }

    public function membership(): ?ShopUser
    {
        return $this->membership;
    }

    public function isBypassed(): bool
    {
        return $this->bypassed;
    }

    /**
     * Run code as a specific shop, then restore whatever was there before.
     * For jobs, admin actions and tests.
     *
     * @template T
     *
     * @param  callable(): T  $callback
     * @return T
     */
    public function runFor(Shop $shop, callable $callback): mixed
    {
        [$previousShop, $previousMembership, $previousBypass] = [$this->shop, $this->membership, $this->bypassed];
        $this->shop = $shop;
        $this->membership = null;
        $this->bypassed = false;

        try {
            return $callback();
        } finally {
            [$this->shop, $this->membership, $this->bypassed] = [$previousShop, $previousMembership, $previousBypass];
        }
    }

    /**
     * Run code that deliberately reads across all shops (platform admin only).
     *
     * @template T
     *
     * @param  callable(): T  $callback
     * @return T
     */
    public function withoutTenancy(callable $callback): mixed
    {
        $previous = $this->bypassed;
        $this->bypassed = true;

        try {
            return $callback();
        } finally {
            $this->bypassed = $previous;
        }
    }
}
