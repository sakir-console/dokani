<?php

use App\Exceptions\ApiException;
use App\Http\Middleware\EnsureShopIsActive;
use App\Http\Middleware\EnsureUserIsActive;
use App\Http\Middleware\RedirectIfNotAdmin;
use App\Http\Middleware\RequireModule;
use App\Http\Middleware\RequirePermission;
use App\Http\Middleware\ResolveShop;
use App\Http\Middleware\SetLocale;
use App\Services\Tenancy\MissingTenantException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Exceptions\ThrottleRequestsException;
use Illuminate\Http\Request;
use Illuminate\Routing\Middleware\SubstituteBindings;
use Illuminate\Support\Facades\Route;
use Illuminate\Validation\ValidationException;
use Psr\Log\LogLevel;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
        then: function () {
            Route::middleware('api')->prefix('api/v1')->group(base_path('routes/api.php'));
            Route::middleware('web')->prefix('admin')->name('admin.')->group(base_path('routes/admin.php'));
        },
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'tenant' => ResolveShop::class,
            'shop.active' => EnsureShopIsActive::class,
            'user.active' => EnsureUserIsActive::class,
            'module' => RequireModule::class,
            'permission' => RequirePermission::class,
            'admin' => RedirectIfNotAdmin::class,
        ]);

        $middleware->api(prepend: [SetLocale::class]);
        $middleware->throttleApi();

        // Route-model binding runs tenant-scoped queries, so the shop must be
        // resolved (and the user authenticated) before bindings are substituted.
        $middleware->prependToPriorityList(SubstituteBindings::class, EnsureUserIsActive::class);
        $middleware->prependToPriorityList(SubstituteBindings::class, ResolveShop::class);
        $middleware->prependToPriorityList(SubstituteBindings::class, EnsureShopIsActive::class);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $isApi = fn (Request $request) => $request->is('api/*');

        $exceptions->shouldRenderJsonWhen(fn (Request $request) => $request->is('api/*') || $request->expectsJson());

        // A tenant model used without a shop is a programming error, never a
        // reason to fall back to unscoped data. Always worth an alert.
        $exceptions->level(MissingTenantException::class, LogLevel::CRITICAL);

        // One error shape for the whole API: { message, code, errors? }.
        $exceptions->render(function (ApiException $e) {
            return $e->render();
        });

        $exceptions->render(function (ValidationException $e, Request $request) use ($isApi) {
            return $isApi($request) ? response()->json([
                'message' => $e->getMessage(),
                'code' => 'VALIDATION_FAILED',
                'errors' => $e->errors(),
            ], $e->status) : null;
        });

        $exceptions->render(function (AuthenticationException $e, Request $request) use ($isApi) {
            return $isApi($request) ? response()->json([
                'message' => __('Please log in to continue.'),
                'code' => 'UNAUTHENTICATED',
            ], 401) : null;
        });

        $exceptions->render(function (ThrottleRequestsException $e, Request $request) use ($isApi) {
            return $isApi($request) ? response()->json([
                'message' => __('Too many attempts. Please wait a moment and try again.'),
                'code' => 'RATE_LIMITED',
            ], 429, $e->getHeaders()) : null;
        });

        $exceptions->render(function (NotFoundHttpException $e, Request $request) use ($isApi) {
            // Also covers ModelNotFoundException, which Laravel converts before rendering.
            // Another shop's record lands here too: it is simply "not found".
            return $isApi($request) ? response()->json([
                'message' => __('Not found.'),
                'code' => 'NOT_FOUND',
            ], 404) : null;
        });

        $exceptions->render(function (HttpExceptionInterface $e, Request $request) use ($isApi) {
            return $isApi($request) ? response()->json([
                'message' => $e->getMessage() ?: __('Request failed.'),
                'code' => 'HTTP_'.$e->getStatusCode(),
            ], $e->getStatusCode(), $e->getHeaders()) : null;
        });
    })->create();
