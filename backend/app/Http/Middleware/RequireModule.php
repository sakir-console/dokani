<?php

namespace App\Http\Middleware;

use App\Exceptions\ApiException;
use App\Services\Subscription\Entitlements;
use App\Services\Tenancy\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Usage: ->middleware('module:reports')
 * Refuses the request unless the shop's plan (or an admin override) includes the module.
 */
class RequireModule
{
    public function __construct(
        private readonly TenantContext $tenant,
        private readonly Entitlements $entitlements,
    ) {}

    public function handle(Request $request, Closure $next, string $module): Response
    {
        if (! $this->entitlements->hasModule($this->tenant->shop(), $module)) {
            throw ApiException::forbidden('MODULE_NOT_AVAILABLE', __('This feature is not included in your current plan.'));
        }

        return $next($request);
    }
}
