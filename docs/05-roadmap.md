# 05 — Implementation Roadmap and Progress Record

Each phase ends with: working code, tests for its business rules, and an update to the status table below.
A phase is not started until the previous phase's tests pass.

## Phases

### Phase 0 — Analysis and architecture
Requirement gaps, architecture, database, API, structure, risks. *(this folder)*

### Phase 1 — Foundation
- Laravel project, environment configuration, MySQL connection
- Error envelope, locale middleware, rate limiters
- Users, shops, memberships; registration, login, logout, password reset by OTP
- Tenant context, fail-closed tenant scope, `ResolveShop`, shop status gate
- Plans, modules, subscriptions (data + entitlement resolution + `RequireModule`)
- Shop profile, logo upload, settings
- Admin guard, login, layout, dashboard with real numbers, shop list with activate/suspend
- Flutter project: theme, Bangla/English, API client, secure token storage, auth screens, shop home shell
- Tests: authentication, tenant resolution, shop status, module gate

### Phase 2 — Catalogue and inventory
Units, categories, brands, vendors, products, variants, barcodes, images, plan product limit, stock in/out/adjust, stock movements, low-stock alerts, global catalogue + import, barcode scanner screen, product screens.
Tests: product CRUD, variant stock, barcode lookup and uniqueness, tenant isolation for every catalogue endpoint, plan limit.

### Phase 3 — POS, payments, dues, invoices
Customers, lookup by phone, `CreateSale` (totals, split and partial payment, due rule, stock deduction, ledger, invoice number, public token), void sale, due collection, customer ledger, dashboard, invoice page + PDF + QR, POS and checkout screens.
Tests: sale creation, totals validation, partial and split payment, due requires customer, customer find-or-create, due collection and installments, stock deduction, concurrent sale of the last item, idempotent sale, public invoice access.

### Phase 4 — Reports
Summary, payment methods, best sellers, low stock, sales history, dues; date ranges in the shop's time zone; Excel/CSV/PDF export; report screens.
Tests: profit with cost snapshots, discounts, voids; date boundaries.

### Phase 5 — Offline mode
Drift schema, delta pull, outbox, push with per-record results, conflict flags, device registration, sync status UI, offline receipts.
Tests: duplicate prevention, offline due sale, stock conflict acceptance, partial batch failure.

### Phase 6 — Subscriptions and full admin panel
Plan CRUD, plan modules and limits, renew/upgrade/downgrade, payments, expiry job and fallback to the default plan, per-shop module overrides, global catalogue management, admin accounts, audit log viewer, analytics.
Tests: subscription permissions, expiry fallback, admin authorisation.

### Phase 7 — Polish and production readiness
Thermal printing (58/80mm), WhatsApp share, push notifications, accessibility pass, performance pass on low-end devices, security review, backup scripts, deployment guide, CI.

## Status

Legend: ✅ done and tested · 🟡 partly done · ⬜ not started · – not applicable

| Area | Backend | Admin | Mobile | Notes |
|---|---|---|---|---|
| Architecture documents | ✅ | ✅ | ✅ | Phase 0 |
| Registration, login, logout | ✅ | ✅ | ✅ | Admin has its own guard and login |
| Password reset by OTP | 🟡 | – | ✅ | Works end to end, but only the `log` SMS driver exists; a real gateway needs credentials |
| OTP at registration | ⬜ | – | ⬜ | Phone numbers are not verified at sign-up yet |
| Tenant isolation foundation | ✅ | – | – | Fail-closed scope, membership-based resolution, isolation test suite |
| Shop profile and settings | ✅ | 🟡 | 🟡 | Admin: view, activate, deactivate, suspend. Mobile: profile editing; logo only at registration; settings screen not built |
| Plans / modules / entitlements | ✅ | ⬜ | 🟡 | Resolution and enforcement done. Admin cannot edit plans yet (Phase 6). Mobile shows plan and modules |
| Roles and permissions | ✅ | – | 🟡 | Owner, manager, cashier enforced by the API; no screen to add staff yet |
| Categories | ✅ | – | ✅ | Sub-categories exist in the API; the app manages one level |
| Brands, units | ✅ | – | 🟡 | App picks units and creates brands from the product form; no screen to add custom units or rename brands |
| Products and variants | ✅ | – | ✅ | Variant attributes (size/colour as separate fields) are stored by the API but the app only edits the variant name |
| Barcodes and scanner | ✅ | – | 🟡 | Lookup, uniqueness, scan-to-find and scan-to-fill work. The camera itself is untested on real phones. Continuous scanning into a cart is Phase 3; offline lookup is Phase 5 |
| Vendors | ✅ | – | 🟡 | CRUD, search, picker in the product form. Vendor's product list and purchase history are API-only so far |
| Global catalogue | ✅ | ✅ | ⬜ | Admin can manage it and the import API works; the app has no browse/import screen yet |
| Inventory | ✅ | – | 🟡 | Stock in/out/correct and low/out-of-stock alerts in the app. Movement history is API-only |
| Customers and ledger | ⬜ | – | ⬜ | Phase 3 |
| POS and sales | ⬜ | – | ⬜ | Phase 3 |
| Payments (split, partial, due) | ⬜ | – | ⬜ | Phase 3 |
| Due collection | ⬜ | – | ⬜ | Phase 3 |
| Invoices (page, PDF, QR) | ⬜ | – | ⬜ | Phase 3 |
| Dashboard | ⬜ | ✅ | ⬜ | Admin dashboard shows real platform numbers; shop dashboard is Phase 3 |
| Reports and exports | ⬜ | – | ⬜ | Phase 4 |
| Offline sync | ⬜ | – | 🟡 | The app opens and stays signed in offline from a cached session; offline selling is Phase 5 |
| Subscription management | 🟡 | ⬜ | ⬜ | Data model and enforcement exist; no renew/upgrade actions yet |
| Audit log | ✅ | 🟡 | – | Written for registration, shop changes, password changes, admin actions; shown per shop, no global viewer yet |
| Thermal printing | – | – | ⬜ | Needs printers to test |
| Push notifications | ⬜ | – | ⬜ | Needs a Firebase project |
| Deployment, backups, CI | ⬜ | – | – | Phase 7 |

## Phase 1 record

**Automated checks at the end of Phase 1**

| Suite | Result |
|---|---|
| `backend`: `php artisan test` | 90 tests, 378 assertions, all passing (MariaDB 10.11) |
| `mobile`: `flutter analyze` | no issues |
| `mobile`: `flutter test` | 56 tests, all passing |

**Checked by hand**

- The API was exercised with real HTTP requests against a running server (register, login, `/me`, create a category, Bangla error message).
- The admin panel was driven in a real browser at desktop and phone widths: sign in, dashboard, search, suspend a shop. No console errors, no horizontal overflow.
- The app's screens were rendered to images with the bundled Bengali font and inspected.

**Not verified**

- The app has not been built into an APK or run on an Android device or emulator; there was no Android SDK in the development environment. Camera, secure storage and the image picker are therefore untested on real hardware.
- Nothing has been load-tested or deployed.

**Decisions made during Phase 1 that differ from or add to the original design**

- Controllers never hold request-scoped services (tenant context) in their constructor; they are injected per method. A test caught a stale shop being returned when a controller instance was reused.
- Category names are unique per shop and parent among live rows, enforced in validation rather than by a database unique index, so a deleted category's name can be reused.
- The `offline` module is a core module (in every plan), because offline selling is treated as essential.
- Plan prices and limits in the seeder (Free 50 products, Basic ৳299, Standard ৳599, Premium ৳999) are placeholders to be changed.

## Phase 2 record

**Automated checks at the end of Phase 2**

| Suite | Result |
|---|---|
| `backend`: `php artisan test` | 147 tests, all passing (MariaDB 10.11) |
| `mobile`: `flutter analyze` | no issues |
| `mobile`: `flutter test` | 104 tests, all passing |

**Checked by hand**

- The catalogue API over real HTTP: create a product in Bangla with a decimal quantity, barcode lookup, refused over-withdrawal, stock in, summary, Bangla error for a module outside the plan.
- The admin catalogue screens in a real browser: add a product with a Bangla name, a new category and two variants.
- The app's catalogue screens rendered to images in Bangla: home, product list, product page, stock sheet, product form.
- The concurrency test was run with the row lock removed to confirm it fails (all 12 workers oversold), then restored.

**Not verified**

- Still no run on an Android device or emulator. The scanner screen in particular has only been compiled and analysed; camera start-up time, autofocus and detection on low-end phones are unknown.
- The product photo picker and upload from a real phone.

**Decisions made during Phase 2**

- A product has one vendor (`products.vendor_id`); the `product_vendor` pivot from the original design was dropped. One vendor still supplies many products.
- Variants are edited as part of the product (one request carries the complete set) rather than through separate variant endpoints.
- Receiving, removing and counting stock is in every plan. Only the full movement history is the paid `inventory` module; otherwise a free shop could never restock.
- Stock-in with a cost sets the variant's purchase price to that latest cost. There is no weighted-average costing.
- A variant that still has stock cannot be removed; its stock must be corrected to zero first.
- Deleting a category, brand or vendor keeps its products and unlinks them.
- The JSON column for variant attributes is named `options`, because Eloquent reserves `attributes`. The API field is still `attributes`.
- `brick/math` 1.0 is a direct dependency; all money and quantity arithmetic goes through `App\Support\Dec`.
- Global catalogue brands are plain text on the product instead of a separate table.

**Left for later from Phase 2's scope**

- App screen to browse and import from the global catalogue.
- App screens for stock movement history, a vendor's products and purchases, custom units, brand management, sub-categories.

**Next: Phase 3 — POS, payments, dues, invoices**

Customers and phone lookup, the sale transaction (server-computed totals, split and partial payment, the due-requires-customer rule, stock deduction, ledger, invoice number and public token), voiding a sale, due collection, customer ledger, shop dashboard figures, invoice page with PDF and QR, and the POS, cart and checkout screens with continuous scanning.
