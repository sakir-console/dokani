<?php

namespace App\Http\Middleware;

use App\Exceptions\ApiException;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureUserIsActive
{
    public function handle(Request $request, Closure $next): Response
    {
        if (! $request->user()->is_active) {
            throw ApiException::forbidden('ACCOUNT_DISABLED', __('This account has been disabled.'));
        }

        return $next($request);
    }
}
