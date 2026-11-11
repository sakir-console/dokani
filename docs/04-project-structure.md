# 04 — Project Structure

One repository, two projects.

```
dokani/
├── backend/        Laravel: REST API + Global Admin panel + public invoice page
├── mobile/         Flutter: Shop Owner app
└── docs/           Architecture and progress records
```

## Laravel (`backend/`)

Standard Laravel layout; domain code is grouped by module inside each layer so a module can be found, and later extracted, easily.

```
backend/
├── app/
│   ├── Enums/                   ShopStatus, ShopType, ShopRole, PaymentMethod, SaleStatus, StockMovementType, …
│   ├── Exceptions/              ApiException (carries an error code), domain exceptions
│   ├── Http/
│   │   ├── Controllers/
│   │   │   ├── Api/V1/          AuthController, MeController, ShopController, ProductController, SaleController, …
│   │   │   └── PublicInvoiceController
│   │   ├── Middleware/          ResolveShop, EnsureShopIsActive, RequireModule, RequirePermission, SetLocale
│   │   ├── Requests/Api/V1/     one FormRequest per write endpoint
│   │   └── Resources/           UserResource, ShopResource, ProductResource, SaleResource, …
│   ├── Livewire/Admin/          admin panel screens (see 01-architecture §7)
│   ├── Models/                  Eloquent models
│   │   └── Concerns/BelongsToShop.php      tenant global scope
│   ├── Rules/                   ExistsInShop, BangladeshPhone
│   ├── Services/
│   │   ├── Auth/                RegisterShop, OtpService
│   │   ├── Tenancy/             TenantContext
│   │   ├── Subscription/        Entitlements, SubscriptionService
│   │   ├── Catalog/             ProductService, BarcodeService, GlobalCatalogImporter
│   │   ├── Inventory/           StockService
│   │   ├── Sales/               CreateSale, VoidSale, SaleCalculator, InvoiceNumberGenerator
│   │   ├── Customers/           LedgerService, CollectDue
│   │   ├── Reports/             SalesReport, exports
│   │   ├── Sync/                PullService, PushService
│   │   ├── Sms/                 SmsSender interface, LogSmsSender, gateway drivers
│   │   └── Audit/               AuditLogger
│   └── Support/                 Money (BigDecimal helpers), Phone (normaliser)
├── config/dokani.php            role → permission map, OTP settings, limits
├── database/
│   ├── migrations/
│   ├── factories/
│   └── seeders/                 ModuleSeeder, PlanSeeder, UnitSeeder, AdminSeeder
├── resources/views/
│   ├── components/admin/        layout, sidebar, stat-card, badge, table, modal
│   ├── livewire/admin/
│   └── invoices/                public invoice + PDF templates
├── routes/
│   ├── api.php                  /api/v1
│   ├── admin.php                /admin
│   └── web.php                  /i/{token}
└── tests/
    ├── Feature/Api/             Auth, TenantIsolation, Products, Sales, Dues, Sync, Subscription …
    ├── Feature/Admin/
    └── Unit/                    Money, SaleCalculator, Phone
```

## Flutter (`mobile/`)

Feature-first structure. Each feature has the same three layers; UI never talks to Dio or Drift directly.

```
mobile/lib/
├── main.dart
├── app/
│   ├── app.dart                 MaterialApp.router, theme, locale
│   ├── router.dart              go_router routes + auth redirect
│   └── theme/                   colours, typography (Bengali-capable font), component themes
├── core/
│   ├── config/                  environment (API base URL via --dart-define)
│   ├── network/                 Dio client, auth interceptor, ApiException mapping
│   ├── storage/                 secure token store, preferences
│   ├── database/                Drift database, tables, DAOs        (Phase 5)
│   ├── sync/                    outbox, sync engine, connectivity   (Phase 5)
│   ├── money/                   Money type (integer paisa), formatters (৳, Bangla digits)
│   ├── l10n/                    app_bn.arb, app_en.arb, generated localizations
│   └── widgets/                 AppButton, AppTextField, StatCard, EmptyState, ErrorView, LoadingView
└── features/
    ├── auth/
    │   ├── data/                AuthApi, AuthRepository, DTOs
    │   ├── application/         AuthController (Riverpod), session state
    │   └── presentation/        Login, Register, ForgotPassword, ResetPassword screens
    ├── shop/                    profile, settings, language
    ├── dashboard/
    ├── products/                list, form, variants, barcodes
    ├── scanner/                 camera scanner widget, scan feedback
    ├── pos/                     catalog grid, cart, checkout, payments
    ├── customers/               list, detail, ledger, due collection
    ├── vendors/
    ├── sales/                   history, sale detail
    ├── invoices/                invoice view, PDF, share, thermal print
    ├── reports/
    └── subscription/
```

Packages (each chosen for one job):

| Purpose | Package |
|---|---|
| State management | `flutter_riverpod` |
| Routing | `go_router` |
| HTTP | `dio` |
| Secure token storage | `flutter_secure_storage` |
| Preferences | `shared_preferences` |
| Offline database | `drift` + `sqlite3_flutter_libs` (Phase 5) |
| Barcode/QR scanning | `mobile_scanner` (CameraX + ML Kit) (Phase 2) |
| Localisation | `flutter_localizations` + `intl`, ARB files |
| Image picking | `image_picker` |
| Thermal printing | `print_bluetooth_thermal` + ESC/POS raster (Phase 7) |
| Sharing | `share_plus` |

## Admin panel

Part of `backend/`. Structure and screens are in `01-architecture.md` §7. Assets are built with Vite + Tailwind (`npm run build`).
