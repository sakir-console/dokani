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
| Barcodes and scanner | ✅ | – | 🟡 | Lookup, uniqueness, scan-to-find, scan-to-fill and continuous scanning into the cart. The camera itself is untested on real phones. Scanning at the counter works offline from the phone's copy |
| Vendors | ✅ | – | 🟡 | CRUD, search, picker in the product form. Vendor's product list and purchase history are API-only so far |
| Global catalogue | ✅ | ✅ | ⬜ | Admin can manage it and the import API works; the app has no browse/import screen yet |
| Inventory | ✅ | – | 🟡 | Stock in/out/correct and low/out-of-stock alerts in the app. Movement history is API-only |
| Customers and ledger | ✅ | – | ✅ | The app shows the latest 100 ledger entries; no paging yet |
| POS and sales | ✅ | – | ✅ | Voiding cancels a whole sale; partial returns are not built. Sales history in the app has no date or status filters yet (the API does) |
| Payments (split, partial, due) | ✅ | – | ✅ | bKash/Nagad/card amounts are typed in by the cashier and stay `unverified`; there is no gateway |
| Due collection | ✅ | – | ✅ | Payments reduce the customer's balance; they are not allocated to individual invoices |
| Invoices (page, PDF, QR) | ✅ | – | 🟡 | Public page, PDF (A4/80mm/58mm), QR. The app shares a link and opens the PDF in the browser; it does not attach the PDF file. Printing is Phase 7 |
| Dashboard | ✅ | ✅ | ✅ | Shop: today's sales, profit, orders, items, customer due, stock alerts. Recent sales are in the API but not shown on the home screen |
| Reports and exports | ✅ | – | ✅ | The daily breakdown is API-only; the app shows no chart. Dates and unit names inside reports are in English even in the Bangla UI |
| Offline sync | ✅ | – | ✅ | Selling, scanning, due sales and due collection work offline and sync later, exactly once. Product and stock changes, new customers, reports and history need a connection. Never run on a real phone or a real flaky network |
| Alerts | 🟡 | – | 🟡 | Stock conflicts from offline sales are raised and shown in the app. No low-stock or expiry alerts yet, and no push delivery |
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

## Phase 3 record

**Automated checks at the end of Phase 3**

| Suite | Result |
|---|---|
| `backend`: `php artisan test` | 203 tests, all passing (MariaDB 10.11) |
| `mobile`: `flutter analyze` | no issues |
| `mobile`: `flutter test` | 149 tests, all passing |

**Checked by hand**

- A real sale over HTTP in Bangla with decimal quantity, line discount, sale discount, charge, cash with change, bKash and a due to a new customer: every figure added up.
- The PDF invoice was rendered to images at A4, 80mm and 58mm: Bengali conjuncts are shaped correctly, the QR code is present, each receipt fits one page.
- The public invoice page in a phone-sized browser: no cookies set, `noindex` header, no horizontal overflow, phone masked.
- The app's counter, cart, checkout, invoice, home and customer screens rendered to images in Bangla.

**A bug the tests caught**

The multi-process sale test deadlocked: when several first sales of a shop arrived together, creating the invoice counter row collided. Fixed by taking one per-shop lock first (`ShopLock`) in sales, voids and product creation, with deadlock retries as a second line of defence. The test now passes repeatedly.

**Not verified**

- Still no run on an Android device or emulator: camera scanning (single and continuous), the share sheet, opening the PDF in a browser and the QR rendering on a real screen.
- The QR code on the invoice has not been scanned with a phone to confirm it opens the page.
- MySQL 8 itself (tests ran on MariaDB 10.11). The `CHECK` constraints need MySQL 8.0.16 or later.

**Decisions made during Phase 3**

- The app must send `grand_total` and `due_amount`; the server compares them with its own. A sale never becomes a due sale by accident because a payment was short.
- A due is never a payment row. It is `sales.due_amount` plus a ledger debit.
- Due collections reduce the customer's balance as a whole; they are not tied to particular invoices.
- Voiding after the due was already collected leaves the customer in credit (a negative balance), shown in the app as an advance.
- At checkout the name typed for an existing phone number does not rename that customer.
- A deleted customer's phone number, used again, restores the old record with its history.
- Sales in one shop are processed one at a time (per-shop lock). Different shops do not wait for each other.
- Free plan: 300 sales a month (placeholder), counted in the shop's time zone.
- The app does its cart arithmetic in whole paisa and thousandths of a unit, using the same half-up rule as the server.
- Checkout pre-fills cash with the full total, so a normal cash sale is one tap.
- Public invoice routes run without sessions or cookies.
- `mpdf/mpdf` and `mpdf/qrcode` were added for PDFs; Hind Siliguri is bundled for Bengali text.

**Left for later from Phase 3's scope**

- Bluetooth thermal printing (Phase 7). The 58mm/80mm PDFs exist, but nothing sends them to a printer.
- Sharing the PDF as a file attachment; today the app shares a link.
- Partial returns, line-level discounts and price override in the app (the API supports line discounts and owner price override).
- Filters on the app's sales history; ledger paging; choosing the PDF width in the app.
- Offline invoices and offline sales (Phase 5).

## Phase 4 record

**Automated checks at the end of Phase 4**

| Suite | Result |
|---|---|
| `backend`: `php artisan test` | 224 tests, all passing (MariaDB 10.11) |
| `mobile`: `flutter analyze` | no issues |
| `mobile`: `flutter test` | 164 tests, all passing |

**Checked by hand**

- Reports over real HTTP after a sale in Bangla with a decimal quantity: summary and period metadata.
- The PDF export rendered to an image: landscape for the wide sales table, Bangla shop and customer names intact, page numbers.
- The Excel export is read back in the tests with PhpSpreadsheet (cell types and values), not just checked for a file signature.
- The report screens rendered to images in Bangla.

**Not verified**

- Still no run on an Android device: the date-range picker, saving the downloaded file and the share sheet with a file attachment.
- Opening the exported Excel and CSV files in Microsoft Excel or Google Sheets themselves.
- Report speed on a shop with tens of thousands of sales. The queries use the existing indexes but have not been measured.

**Decisions made during Phase 4**

- The week starts on Saturday (configurable with `WEEK_STARTS_ON`).
- "Last 7 days" means today and the six days before it.
- Payment-method figures follow the money by the day it moved, so a sale cancelled on a later day shows as a refund on that later day.
- Bill-level discounts are not spread across products in the best-seller list; product revenue there is after line discounts only.
- Reports need both the `reports` module and the `reports.view` permission (owner and manager), because they show cost and profit. Exports are a separate module (Standard plan and above in the placeholder plans).
- Exports are produced during the request, limited to 10,000 rows. Larger periods must be narrowed; background export jobs were not built.
- CSV is written directly rather than through the spreadsheet library, so amounts keep two decimals.
- The app downloads an export itself (the request needs the login token) and passes the file to the share sheet, where it can be saved, opened or sent.
- `maatwebsite/excel` 4.0 (PhpSpreadsheet 5) was added.

**Left for later from Phase 4's scope**

- A chart of daily sales in the app (the data endpoint exists).
- Localised dates and unit names inside report screens and exported files; export headings are English.
- Background exports for very large periods.

**Next: Phase 5 — offline mode**

A local database on the phone (Drift), cached products and barcodes with delta sync, an outbox for offline sales and due collections, push with per-record results, stock-conflict flags, device registration, sync status in the app and offline receipts.

## Phase 5 record

**What was built**

- Server: delta pull for products (with variants and barcodes), customers and categories; `POST /sync/push` with one answer per record; an offline path through sale creation and due collection; devices; shop notifications.
- App: a SQLite database per shop (Drift) holding a copy of products, barcodes and customers and an outbox; a sync engine (push, then pull); the counter and scanner read the phone's copy; every sale and due collection is queued on the phone before it is sent; a pending invoice that turns into a confirmed one; a sync screen; a notice on home while anything is unsent; a warning before logging out with unsent records; customers and due collection from the phone's copy when there is no connection; an alerts screen for stock conflicts.

**Automated checks at the end of Phase 5**

| Suite | Result |
|---|---|
| `backend`: `php artisan test` | 248 tests, all passing (MariaDB 10.11) |
| `mobile`: `flutter analyze` | no issues |
| `mobile`: `flutter test` | 220 tests, all passing |
| `mobile`: `flutter test tool/sync_contract_test.dart` | passing against a locally running backend |

**Checked by hand**

- The app's own sync code against the real Laravel server over HTTP (`tool/sync_contract_test.dart`): first download; a cash sale and a due sale to a new customer made with the connection cut; both arrive once with real invoice numbers; the server's stock and the phone's agree afterwards; the same sale pushed again is answered `duplicate`; an offline due collection reduces the balance on both sides; an oversold sale is accepted, takes stock to −2 and raises a stock-conflict alert that the app reads and marks as read; a sale for a product that does not exist stays on the phone with the server's reason.
- The pending invoice, the home notice and the sync screen rendered to images in Bangla.

**Not verified**

- **The app has still never run on a phone or emulator.** In particular: creating and opening the SQLite file on Android (the tests use an in-memory database through the same code), the background isolate, the database surviving an app update, and sync on resume from the background.
- Behaviour on a real unstable mobile network (slow, half-open connections). "No connection" is simulated by refused connections and injected timeouts.
- Speed with a large catalogue. The first download is 200 products per request; searching the phone's copy and adjusting local stock have not been measured beyond a few thousand rows in theory and a handful in tests.
- Two phones selling the same last item offline: each case is covered by the stock-conflict rule and its tests, but two real devices were not used.
- MySQL 8 (the tests run on MariaDB 10.11).

**Decisions made during Phase 5**

- **Queue first, then send**, even when online. The cost is one local write per sale; the gain is that a sale cannot be lost between "Complete" and the server's answer.
- A clear refusal from the server at the checkout (HTTP 4xx other than 401, 408, 429) is shown to the cashier and not queued. Everything else keeps the record: no connection, timeout, expired login, rate limit, server fault.
- Failed records are retried on every sync, because the cause may have been fixed on the server. Only an owner or manager can delete one, after a warning, and only if it is in the failed state.
- Sales pushed from the queue are never refused for stock, plan limits or credit limits: the goods have left the shop. They are refused only if the arithmetic is wrong, the product never existed in this shop, or the user may not sell.
- The phone's database belongs to the shop, not the login, and is **kept on logout** so unsent sales survive. It is not encrypted. It holds product prices (cost price only if the user's role may see it) and customers' names, phone numbers and balances.
- The pull cursor is saved only after every page of a round has arrived; an interrupted download starts that round again.
- Retry is a fixed 45 seconds while something is waiting, plus app resume, sign-in and the manual button. There is no listener for "connectivity changed" and no exponential backoff, to avoid another plugin that cannot be tested here.
- The temporary invoice reference is `OFF-` plus eight characters of the sale's id rather than a per-device counter, so it needs no coordination.
- A phone clock that is wrong by more than 90 days back or any amount forward does not block a sale; the server's time is used instead.
- `sqlite3_flutter_libs` was dropped: current `sqlite3` builds the library itself. `drift`, `drift_dev`, `build_runner`, `path_provider` and `path` were added.

**Left for later from Phase 5's scope**

- Offline product and stock changes, adding a customer offline (other than through a due sale), and offline views of sales history, the ledger and reports.
- The category list is synced by the server but the counter does not filter by category yet.
- Product images are not stored for offline use; without a connection the counter shows initials.
- A printed or shareable receipt for a sale that has not reached the server (the customer link and QR code exist only after sync).
- Low-stock and subscription alerts; push delivery of alerts.
- Encrypting the phone's database and configuring Android backup rules for it.
- Showing on a confirmed invoice that it was made offline or had a stock conflict (the API returns both flags).

**Next: Phase 6 — subscriptions and the full admin panel**

Plan editing (modules, limits, prices), renew/upgrade/downgrade with recorded payments, the expiry job and fallback to the default plan, per-shop module overrides in the admin panel, admin accounts, the audit log viewer and platform analytics; in the app, a plan screen showing limits and usage.

