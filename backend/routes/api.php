<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\BarcodeController;
use App\Http\Controllers\Api\V1\BrandController;
use App\Http\Controllers\Api\V1\CategoryController;
use App\Http\Controllers\Api\V1\CustomerController;
use App\Http\Controllers\Api\V1\DashboardController;
use App\Http\Controllers\Api\V1\GlobalCatalogController;
use App\Http\Controllers\Api\V1\MeController;
use App\Http\Controllers\Api\V1\MetaController;
use App\Http\Controllers\Api\V1\NotificationController;
use App\Http\Controllers\Api\V1\ProductController;
use App\Http\Controllers\Api\V1\ReportController;
use App\Http\Controllers\Api\V1\SaleController;
use App\Http\Controllers\Api\V1\ShopController;
use App\Http\Controllers\Api\V1\StockController;
use App\Http\Controllers\Api\V1\SyncController;
use App\Http\Controllers\Api\V1\UnitController;
use App\Http\Controllers\Api\V1\VendorController;
use App\Http\Controllers\PublicInvoiceController;
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

// The invoice behind a receipt's QR code. No login; the random token is the credential.
Route::get('public/invoices/{token}', [PublicInvoiceController::class, 'json'])->middleware('throttle:public-invoice');

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

            Route::get('dashboard', DashboardController::class);

            Route::get('notifications', [NotificationController::class, 'index']);
            Route::post('notifications/read-all', [NotificationController::class, 'markAllRead']);
            Route::post('notifications/{notification}/read', [NotificationController::class, 'markRead']);

            // Offline mode: the phone pulls what changed and pushes what it recorded offline.
            Route::middleware('module:offline')->group(function () {
                Route::post('devices', [SyncController::class, 'registerDevice']);
                Route::get('sync/products', [SyncController::class, 'products']);
                Route::get('sync/customers', [SyncController::class, 'customers']);
                Route::get('sync/categories', [SyncController::class, 'categories']);
                Route::post('sync/push', [SyncController::class, 'push']);
            });

            Route::middleware('module:customers')->group(function () {
                Route::get('customers', [CustomerController::class, 'index']);
                Route::get('customers/lookup', [CustomerController::class, 'lookup']);
                Route::get('customers/{customer}', [CustomerController::class, 'show']);
                Route::get('customers/{customer}/ledger', [CustomerController::class, 'ledger']);
                Route::get('customers/{customer}/sales', [CustomerController::class, 'sales']);
                Route::get('customers/{customer}/payments', [CustomerController::class, 'payments']);

                Route::middleware('permission:customers.manage')->group(function () {
                    Route::post('customers', [CustomerController::class, 'store']);
                    Route::patch('customers/{customer}', [CustomerController::class, 'update']);
                    Route::delete('customers/{customer}', [CustomerController::class, 'destroy']);
                });

                Route::post('customers/{customer}/collect-due', [CustomerController::class, 'collectDue'])
                    ->middleware('permission:due.collect');
            });

            Route::middleware('module:pos')->group(function () {
                Route::get('sales', [SaleController::class, 'index']);
                Route::get('sales/{sale}', [SaleController::class, 'show']);
                Route::get('sales/{sale}/invoice.pdf', [SaleController::class, 'pdf']);
                Route::post('sales', [SaleController::class, 'store'])->middleware('permission:pos.sell');
                Route::post('sales/{sale}/void', [SaleController::class, 'void'])->middleware('permission:sales.void');
            });

            // Reports show cost and profit, so they need the reports permission as well as the module.
            Route::middleware(['module:reports', 'permission:reports.view'])->prefix('reports')->group(function () {
                Route::get('summary', [ReportController::class, 'summary']);
                Route::get('daily', [ReportController::class, 'daily']);
                Route::get('payment-methods', [ReportController::class, 'paymentMethods']);
                Route::get('best-sellers', [ReportController::class, 'bestSellers']);
                Route::get('low-stock', [ReportController::class, 'lowStock']);
                Route::get('sales', [ReportController::class, 'sales']);
                Route::get('dues', [ReportController::class, 'dues']);

                // Downloadable files are a separate, higher-plan module.
                Route::get('{report}/export', [ReportController::class, 'export'])->middleware('module:exports');
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
