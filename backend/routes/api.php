<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\BarcodeController;
use App\Http\Controllers\Api\V1\BrandController;
use App\Http\Controllers\Api\V1\CategoryController;
use App\Http\Controllers\Api\V1\GlobalCatalogController;
use App\Http\Controllers\Api\V1\MeController;
use App\Http\Controllers\Api\V1\MetaController;
use App\Http\Controllers\Api\V1\ProductController;
use App\Http\Controllers\Api\V1\ShopController;
use App\Http\Controllers\Api\V1\StockController;
use App\Http\Controllers\Api\V1\UnitController;
use App\Http\Controllers\Api\V1\VendorController;
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

                Route::get('brands', [BrandController::class, 'index']);
                Route::get('units', [UnitController::class, 'index']);
                Route::get('products', [ProductController::class, 'index']);
                Route::get('products/{product}', [ProductController::class, 'show']);
                Route::get('barcodes/lookup', [BarcodeController::class, 'lookup']);
                Route::get('stock/summary', [StockController::class, 'summary']);

                Route::middleware('permission:catalog.manage')->group(function () {
                    Route::post('categories', [CategoryController::class, 'store']);
                    Route::patch('categories/{category}', [CategoryController::class, 'update']);
                    Route::delete('categories/{category}', [CategoryController::class, 'destroy']);

                    Route::post('brands', [BrandController::class, 'store']);
                    Route::patch('brands/{brand}', [BrandController::class, 'update']);
                    Route::delete('brands/{brand}', [BrandController::class, 'destroy']);

                    Route::post('units', [UnitController::class, 'store']);
                    Route::patch('units/{unit}', [UnitController::class, 'update']);
                    Route::delete('units/{unit}', [UnitController::class, 'destroy']);

                    Route::post('products', [ProductController::class, 'store']);
                    Route::patch('products/{product}', [ProductController::class, 'update']);
                    Route::delete('products/{product}', [ProductController::class, 'destroy']);
                    Route::post('products/{product}/image', [ProductController::class, 'uploadImage']);
                    Route::delete('products/{product}/image', [ProductController::class, 'deleteImage']);
                });

                // Receiving, removing and counting stock is part of every plan.
                Route::middleware('permission:inventory.manage')->group(function () {
                    Route::post('stock/in', [StockController::class, 'stockIn']);
                    Route::post('stock/out', [StockController::class, 'stockOut']);
                    Route::post('stock/adjust', [StockController::class, 'adjust']);
                });

                // The full movement history is the paid "inventory" module.
                Route::get('stock/movements', [StockController::class, 'movements'])->middleware('module:inventory');
            });

            Route::middleware('module:vendors')->group(function () {
                Route::get('vendors', [VendorController::class, 'index']);
                Route::get('vendors/{vendor}', [VendorController::class, 'show']);
                Route::get('vendors/{vendor}/products', [VendorController::class, 'products']);
                Route::get('vendors/{vendor}/purchases', [VendorController::class, 'purchases']);

                Route::middleware('permission:vendors.manage')->group(function () {
                    Route::post('vendors', [VendorController::class, 'store']);
                    Route::patch('vendors/{vendor}', [VendorController::class, 'update']);
                    Route::delete('vendors/{vendor}', [VendorController::class, 'destroy']);
                });
            });

            Route::middleware('module:global_catalog')->prefix('global-catalog')->group(function () {
                Route::get('categories', [GlobalCatalogController::class, 'categories']);
                Route::get('products', [GlobalCatalogController::class, 'products']);
                Route::post('products/{globalProduct}/import', [GlobalCatalogController::class, 'import'])
                    ->whereNumber('globalProduct')->middleware('permission:catalog.manage');
            });
        });
    });
});
