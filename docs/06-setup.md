# 06 — Setup, Commands and Testing

## Requirements

| Tool | Version used during development |
|---|---|
| PHP | 8.3 with `pdo_mysql`, `gd`, `mbstring`, `intl` |
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
| `APP_MIN_VERSION` | Oldest app version the API accepts (reported by `/meta`) | `1.0.0` |

**OTP in development.** With `SMS_DRIVER=log` the code is written to `storage/logs/laravel.log` and no SMS is sent.
This is the only driver that exists so far. Before real users can reset a password, a gateway driver must be added (implement `App\Services\Sms\SmsSender`, register it in `AppServiceProvider`); that needs an account with a Bangladeshi SMS provider.

### URLs

| URL | What |
|---|---|
| `http://127.0.0.1:8000/api/v1/meta` | API health check / reference data |
| `http://127.0.0.1:8000/admin` | Global Admin panel |

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
| `test/features/screens/*.dart` | The real app with a fake server: Bangla by default, language switch, form validation, login, registration, password reset, home, settings, shop editing, role and suspension rules |
