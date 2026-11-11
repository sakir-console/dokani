<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\CategoryController;
use App\Http\Controllers\Api\V1\MeController;
use App\Http\Controllers\Api\V1\MetaController;
use App\Http\Controllers\Api\V1\ShopController;
use Illuminate\Support\Facades\Route;

/*
| Mobile API, version 1. Mounted at /api/v1.
|
| Middleware aliases used below:
|   tenant           ResolveShop        — sets the current shop from the user's membership
|   shop.active      EnsureShopIsActive — blocks suspended and inactive shops
|   module:<key>     RequireModule      — the shop's plan must include the module
|   permission:<p>   RequirePermission  — the user's role in the shop must allow it
*/

Route::get('meta', MetaController::class);

Route::prefix('auth')->middleware('throttle:auth')->group(function () {
    Route::post('register', [AuthController::class, 'register']);
    Route::post('login', [AuthController::class, 'login']);
    Route::post('forgot-password', [AuthController::class, 'forgotPassword'])->middleware('throttle:otp');
    Route::post('reset-password', [AuthController::class, 'resetPassword']);
});

Route::middleware(['auth:sanctum', 'user.active'])->group(function () {
    Route::post('auth/logout', [AuthController::class, 'logout']);
    Route::post('auth/change-password', [AuthController::class, 'changePassword'])->middleware('throttle:auth');

    Route::middleware('tenant')->group(function () {
        // Reachable even when the shop is suspended, so the app can explain why.
        Route::get('me', [MeController::class, 'show']);
        Route::patch('me', [MeController::class, 'update']);

        Route::middleware('shop.active')->group(function () {
            Route::get('shop', [ShopController::class, 'show']);
            Route::get('shop/settings', [ShopController::class, 'settings']);

            Route::middleware('permission:settings.manage')->group(function () {
                Route::patch('shop', [ShopController::class, 'update']);
                Route::post('shop/logo', [ShopController::class, 'uploadLogo']);
                Route::delete('shop/logo', [ShopController::class, 'deleteLogo']);
                Route::patch('shop/settings', [ShopController::class, 'updateSettings']);
            });

            Route::middleware('module:products')->group(function () {
                Route::get('categories', [CategoryController::class, 'index']);
                Route::get('categories/{category}', [CategoryController::class, 'show']);

                Route::middleware('permission:catalog.manage')->group(function () {
                    Route::post('categories', [CategoryController::class, 'store']);
                    Route::patch('categories/{category}', [CategoryController::class, 'update']);
                    Route::delete('categories/{category}', [CategoryController::class, 'destroy']);
                });
            });
        });
    });
});
