<?php

namespace App\Http\Middleware;

use App\Exceptions\ApiException;
use App\Services\Tenancy\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Usage: ->middleware('permission:catalog.manage')
 * Checks the role the user holds in the current shop.
 */
class RequirePermission
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function handle(Request $request, Closure $next, string $permission): Response
    {
        $role = $this->tenant->membership()?->role;

        if ($role === null || ! $role->can($permission)) {
            throw ApiException::forbidden('FORBIDDEN', __('You do not have permission to do this.'));
        }

        return $next($request);
    }
}
