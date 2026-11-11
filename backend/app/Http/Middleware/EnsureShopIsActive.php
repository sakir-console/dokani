<?php

namespace App\Http\Middleware;

use App\Enums\ShopStatus;
use App\Exceptions\ApiException;
use App\Services\Tenancy\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureShopIsActive
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function handle(Request $request, Closure $next): Response
    {
        match ($this->tenant->shop()->status) {
            ShopStatus::Suspended => throw ApiException::forbidden('SHOP_SUSPENDED', __('This shop has been suspended. Please contact support.')),
            ShopStatus::Inactive => throw ApiException::forbidden('SHOP_INACTIVE', __('This shop is inactive. Please contact support.')),
            ShopStatus::Active => null,
        };

        return $next($request);
    }
}
