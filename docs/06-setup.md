# 06 — Setup, Commands and Testing

## Requirements

| Tool | Version used during development |
|---|---|
| PHP | 8.3 with `pdo_mysql`, `gd`, `mbstring`, `intl` (`pcntl` for the concurrency tests) |
| Composer | 2.8 |
| MySQL | 8.x (tests were run on MariaDB 10.11, which is compatible) |
| Node.js | 22 (only to build the admin panel's CSS) |
| Flutter | 3.47 stable (Dart 3.13) |
| Android SDK | Needed to build or run the app on a phone. Not needed for `flutter test`. |

## Backend (`backend/`)

### First-time setup

```bash
cd backend
composer install
cp .env.example .env
php artisan key:generate
```

Create two databases, one for the app and one for tests:

```sql
CREATE DATABASE dokani      CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE dokani_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'dokani'@'127.0.0.1' IDENTIFIED BY 'choose-a-password';
GRANT ALL ON dokani.*      TO 'dokani'@'127.0.0.1';
GRANT ALL ON dokani_test.* TO 'dokani'@'127.0.0.1';
```

Set `DB_PASSWORD` in `.env`, then:

```bash
php artisan migrate --seed      # tables + modules + plans
php artisan storage:link        # serves uploaded logos
php artisan dokani:create-admin # first Global Admin account (asks for name, email, password)
npm install
npm run build                   # admin panel CSS
php artisan serve               # http://127.0.0.1:8000
```

`php artisan db:seed` is safe to run again: it never overwrites plans the admin has edited.
Setting `ADMIN_EMAIL` and `ADMIN_PASSWORD` in `.env` makes the seeder create the admin instead of the command.

### Environment variables added by this project

| Variable | Purpose | Default |
|---|---|---|
| `DB_*` | MySQL connection | `dokani` on `127.0.0.1` |
| `FILESYSTEM_DISK` | Where logos are stored | `public` |
| `ADMIN_NAME`, `ADMIN_EMAIL`, `ADMIN_PASSWORD` | Optional first admin, created by the seeder | empty |
| `SMS_DRIVER` | How OTP codes are sent | `log` |
| `APP_URL` | Base of the public invoice links printed as QR codes. Must be the real public address in production | `http://localhost:8000` |
| `WEEK_STARTS_ON` | First day of the week for "this week" reports: 6 = Saturday, 0 = Sunday, 1 = Monday | `6` |
| `APP_MIN_VERSION` | Oldest app version the API accepts (reported by `/meta`) | `1.0.0` |

**OTP in development.** With `SMS_DRIVER=log` the code is written to `storage/logs/laravel.log` and no SMS is sent.
This is the only driver that exists so far. Before real users can reset a password, a gateway driver must be added (implement `App\Services\Sms\SmsSender`, register it in `AppServiceProvider`); that needs an account with a Bangladeshi SMS provider.

### URLs

| URL | What |
|---|---|
| `http://127.0.0.1:8000/api/v1/meta` | API health check / reference data |
| `http://127.0.0.1:8000/admin` | Global Admin panel |
| `http://127.0.0.1:8000/i/<token>` | Public invoice (the link in a sale's `invoice_url`) |

### Tests

```bash
cd backend
php artisan test
```

Tests use the `dokani_test` database (see `phpunit.xml`) and reset it themselves. They run against MySQL rather than SQLite on purpose: later phases test row locking and constraints.

| File | What it proves |
|---|---|
| `tests/Unit/PhoneTest.php` | Phone normalisation, including `+880`, spaces and Bengali digits |
| `tests/Feature/Api/AuthTest.php` | Registration is all-or-nothing; login does not reveal which numbers exist; rate limit; logout; OTP reset (hashed, single-use, expiry, attempt limit); change password |
| `tests/Feature/Api/TenantIsolationTest.php` | Shop comes from membership; `X-Shop-Id` cannot reach a foreign shop; `shop_id` in the body is ignored; another shop's record is a 404 identical to a missing one; the model layer refuses to run without a shop |
| `tests/Feature/Api/ShopAccessTest.php` | Suspended/inactive/deleted shops are blocked; cashier and manager permissions |
| `tests/Feature/Api/EntitlementsTest.php` | Plan modules and limits; fallback to Free on expiry; per-shop overrides; core modules cannot be disabled; the module middleware |
| `tests/Feature/Api/ShopProfileTest.php` | Profile and settings updates; protected fields cannot be mass-assigned; logo is re-encoded and resized; non-images are rejected |
| `tests/Feature/Api/CategoryTest.php` | CRUD, unique names per parent, no cycles |
| `tests/Feature/Api/ProductTest.php` | Simple and variant products; opening stock as a movement; variant sync; search and stock filters; image; plan product limit; cashier read-only; barcode lookup and uniqueness, including the database index |
| `tests/Feature/Api/StockTest.php` | Stock in/out/adjust, running balance, cost update, whole-unit rule, negative-stock setting, history is append-only |
| `tests/Feature/Api/StockConcurrencyTest.php` | 12 separate processes withdraw from a variant holding 5: exactly 5 succeed, stock ends at 0. Fails if the row lock is removed. Needs the `pcntl` extension (skipped without it) |
| `tests/Feature/Api/CatalogSupportTest.php` | Units, brands, vendors; vendor module gating; deleting a brand/vendor/category keeps its products |
| `tests/Feature/Api/GlobalCatalogTest.php` | Browse, search, import with the shop's own prices, independence of the copy, per-shop `already_imported`, product limit |
| `tests/Feature/Api/SaleTest.php` | A sale records items, payments, stock movements and invoice; server-side totals and prices; half-up rounding per line; stock across duplicate lines; profit unchanged by later price changes; idempotency; plan monthly limit; the database CHECK on totals |
| `tests/Feature/Api/DueTest.php` | Due requires a customer; partial and split payment; Total = Paid + Due; cash change; find-or-create customer by phone; credit limit; due collection in instalments; idempotent collection; ledger running balance; customer CRUD |
| `tests/Feature/Api/VoidAndInvoiceTest.php` | Void reverses stock, ledger and payments by new rows; public invoice page and JSON leak nothing private; bad tokens; rate limit; PDF content and receipt widths (needs `pdftotext` to read the PDF, otherwise that check is skipped); dashboard figures and time zone |
| `tests/Feature/Api/SaleConcurrencyTest.php` | Separate processes at once: no overselling, consecutive invoice numbers, one sale for eight identical requests, six due sales to one new customer all reach the ledger. Needs `pcntl` |
| `tests/Feature/Api/ReportTest.php` | Summary figures with discounts, charges, a cancelled sale and a due collection; profit from frozen costs; every period against a fixed calendar, including the shop's midnight and Saturday week start; payment methods; best sellers; low stock; dues; plan and role gating; tenant isolation; CSV, Excel (read back with PhpSpreadsheet) and PDF exports; formula-injection protection |
| `tests/Feature/Api/SyncTest.php` | First sync and later changes (stock, barcodes, deletions); paging; nothing missed when a row changes during a sync; offline sales keep the phone's time and price; the same sale sent twice, or sent online and again through sync, is stored once; overselling is accepted, flagged and reported; deleted products; offline due sales and collections; bad arithmetic is answered `failed`, not stored; roles; suspended shops; batch limit; device registration; isolation between shops |
| `tests/Feature/Admin/GlobalCatalogAdminTest.php` | Admin catalogue screens: access, add with image and variants, validation, edit, hide, delete |
| `tests/Feature/Admin/AdminPanelTest.php` | Admin guard is separate from shop users; login lockout; dashboard numbers; search and filters; suspend/restore is audited and takes effect on the API immediately |

### Trying the API by hand

```bash
curl -X POST http://127.0.0.1:8000/api/v1/auth/register \
  -H 'Accept: application/json' -H 'Content-Type: application/json' \
  -d '{"shop_name":"Rahim Store","owner_name":"Rahim Uddin","phone":"01712345678","password":"secret-pass","shop_type":"grocery","device_name":"curl"}'
```

The response contains `data.token`. Use it as `Authorization: Bearer <token>` on `/api/v1/me`, `/api/v1/shop`, `/api/v1/categories`.

## Mobile app (`mobile/`)

```bash
cd mobile
flutter pub get      # also generates the Bangla/English classes from lib/l10n/*.arb
flutter analyze
flutter test
```

The phone's database code (`lib/core/database/local_database.g.dart`) is generated and committed. After changing a table in `local_database.dart`, regenerate it:

```bash
dart run build_runner build
```

Run on an Android emulator against a backend on the same computer (the default API address is `http://10.0.2.2:8000/api/v1`, the emulator's name for the host machine):

```bash
flutter run
```

Run on a real phone, or against a deployed server:

```bash
flutter run --dart-define=API_BASE_URL=https://your-server.example/api/v1
```

For a phone on the same Wi-Fi as a development machine, start the backend with `php artisan serve --host=0.0.0.0` and use `http://<computer-ip>:8000/api/v1`.
Plain `http` is allowed in debug builds only; release builds require `https`.

**Barcode scanner.** The scanner uses the `mobile_scanner` package (CameraX + ML Kit, model bundled in the app so it works offline). It needs a real device: the automated tests replace the camera with a fixed result, so scanning speed, autofocus and low-light behaviour are untested until the app runs on phones.

**Offline mode against a real server.** `tool/sync_contract_test.dart` runs the app's own sync code against a running backend: first download, two sales and a due collection made with the connection cut, their arrival exactly once, a duplicate push, an oversold sale and its alert, and a refused record. It is not part of `flutter test` because it needs a server:

```bash
cd backend && php artisan migrate:fresh --seed && php artisan serve --port=8010
cd mobile  && flutter test tool/sync_contract_test.dart     # DOKANI_API=... to use another address
```

Render the main screens to PNG files without a phone (written to `mobile/tool/screenshots/`):

```bash
FLUTTER_ROOT=$(dirname $(dirname $(which flutter))) flutter test tool/screenshots_test.dart --update-goldens
```

| Test file | What it proves |
|---|---|
| `test/core/phone_test.dart` | Same phone rules as the server |
| `test/core/api_exception_test.dart` | Server errors, validation errors and connection failures are parsed into one type |
| `test/core/auth_interceptor_test.dart` | Token and language headers; a rejected token is reported, a failed login is not |
| `test/features/auth/session_test.dart` | `/me` parsing and the cache round trip |
| `test/features/auth/auth_controller_test.dart` | Session restore from cache, staying signed in offline, sign-out on a rejected token, login, logout |
| `test/features/auth/router_redirect_test.dart` | Who can reach which screen |
| `test/core/formatters_test.dart` | Number input (including Bangla digits) and money/quantity display |
| `test/features/catalog/models_test.dart` | Product JSON parsing; what a product draft sends |
| `test/features/catalog/product_list_controller_test.dart` | Search, filters, paging, retry after failure, outdated responses ignored |
| `test/features/catalog/*_test.dart` (screens) | Products list, product form (validation, variants, scan, inline category), product page and stock sheets, categories, vendors, role and plan rules |
| `test/core/exact_test.dart`, `test/features/pos/cart_and_payment_test.dart` | Integer arithmetic matches the server's rounding; cart rules; who pays what at checkout (change, due, split) |
| `test/features/pos/pos_flow_test.dart` | The counter end to end against an in-memory server: cash sale, change, partial and split payment, due needs a customer, new customer, variants, stock limits, cart edits, continuous scanning, retry with the same id, share, cancel, cashier limits |
| `test/features/pos/customers_and_dashboard_test.dart` | Dashboard figures by role, due collection in instalments, customers, sales history |
| `test/core/database/local_database_test.dart` | The phone's database against real SQLite: product and barcode cache, search, local stock, customers, the outbox (no duplicates, failed rows kept, only confirmed rows pruned) |
| `test/core/sync/sync_engine_test.dart` | Full first download and later deltas; an interrupted download starts the round again; deletions; a queued sale is sent once; nothing is lost without a connection; refused records are kept with the reason and retried; batches of 50; simultaneous syncs run as one; push before pull |
| `test/features/pos/sale_submitter_test.dart` | A sale is queued before it is sent; confirmed at once when online; kept when there is no answer (no internet, timeout, 500, 429, expired login); not recorded twice when the answer is lost; a clear refusal is shown and not queued; local stock and the customer's balance on the phone; due collections the same way; deliberate removal of a refused record |
| `test/features/pos/offline_flow_test.dart` | The real app with a local database: selling and scanning without internet, the waiting invoice and its change to confirmed, the notice on home, the sync screen, refused records and who may remove them, the warning before logging out, customers and due collection offline, Bangla |
| `test/features/screens/alerts_test.dart` | Unread count on the bell, the alerts screen, mark all as read, behaviour without a connection |
| `test/features/reports/reports_test.dart` | Who sees reports; period switching; figures; money received; best-seller ranking; export of the chosen report and file type; failure handling; Bangla |
| `test/features/screens/*.dart` | The real app with a fake server: Bangla by default, language switch, form validation, login, registration, password reset, home, settings, shop editing, role and suspension rules |
