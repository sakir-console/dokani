<?php

namespace App\Http\Middleware;

use App\Exceptions\ApiException;
use App\Models\ShopUser;
use App\Services\Tenancy\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Decides which shop this request acts for.
 *
 * The shop always comes from the authenticated user's own memberships.
 * The X-Shop-Id header may only choose between shops the user belongs to;
 * shop_id values in the body or query string are never read.
 */
class ResolveShop
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        $memberships = ShopUser::query()
            ->where('user_id', $user->id)
            ->where('is_active', true)
            ->whereHas('shop')
            ->with('shop')
            ->orderBy('id')
            ->get();

        if ($memberships->isEmpty()) {
            throw ApiException::forbidden('NO_SHOP', __('This account is not linked to any shop.'));
        }

        $requested = $request->header('X-Shop-Id');

        if ($requested !== null && $requested !== '') {
            $membership = ctype_digit((string) $requested)
                ? $memberships->firstWhere('shop_id', (int) $requested)
                : null;

            if ($membership === null) {
                throw ApiException::forbidden('SHOP_ACCESS_DENIED', __('You do not have access to this shop.'));
            }
        } else {
            $membership = $memberships->first();
        }

        $this->tenant->set($membership->shop, $membership);

        return $next($request);
    }
}
