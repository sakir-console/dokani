# 03 — API Endpoint Documentation

Base URL: `https://<host>/api/v1`. JSON only.

## Conventions

**Headers**

| Header | Purpose |
|---|---|
| `Authorization: Bearer <token>` | Required on everything except the Auth and Public groups |
| `Accept: application/json` | Always |
| `Accept-Language: bn` or `en` | Language of validation messages |
| `X-Shop-Id: <id>` | Optional. Selects one of the user's own shops. Ignored if the user has one shop; `403` if the user is not a member |
| `Idempotency-Key: <uuid>` | Optional duplicate guard on non-sale writes. Sales and due collections use `client_uuid` in the body |

**Success**

```json
{ "data": { }, "meta": { "current_page": 1, "per_page": 30, "total": 124 } }
```

**Error**

```json
{ "message": "Customer is required for a due sale.", "code": "DUE_REQUIRES_CUSTOMER", "errors": { "customer.phone": ["…"] } }
```

| Status | Meaning |
|---|---|
| 200 / 201 | OK / created |
| 401 | Missing or invalid token |
| 403 | Not a member of the shop, role lacks permission, shop suspended (`SHOP_SUSPENDED`), module not in plan (`MODULE_NOT_AVAILABLE`), plan limit reached (`PLAN_LIMIT_REACHED`) |
| 404 | Not found **in this shop** (another shop's record is also 404) |
| 409 | Conflict: insufficient stock (`INSUFFICIENT_STOCK`), duplicate barcode |
| 422 | Validation failed, totals mismatch (`TOTALS_MISMATCH`, `PAYMENT_MISMATCH`) |
| 429 | Rate limited |

Lists accept `page`, `per_page` (max 100), `q` (search) and resource-specific filters.
Money is sent and returned as strings with two decimals (`"1120.00"`); quantities as strings with up to three (`"0.250"`).

Status column: ✅ implemented in Phase 1, otherwise the phase in which it is delivered.

## Auth (public, rate-limited)

| Method | Path | Body | Status |
|---|---|---|---|
| POST | `/auth/register` | `shop_name, owner_name, phone, password, shop_type, address?, logo?` (multipart), `device_name` → user, shop, token | ✅ |
| POST | `/auth/login` | `phone, password, device_name` → user, shops, token | ✅ |
| POST | `/auth/logout` | revokes the current token (auth required) | ✅ |
| POST | `/auth/forgot-password` | `phone` → sends OTP; always answers 200 | ✅ |
| POST | `/auth/reset-password` | `phone, otp, password` → resets password, revokes all tokens | ✅ |
| POST | `/auth/change-password` | `current_password, password` (auth required) | ✅ |

## Session and shop

| Method | Path | Notes | Status |
|---|---|---|---|
| GET | `/me` | user, current shop, role, permissions, plan, enabled modules, limits and usage | ✅ |
| PATCH | `/me` | `name, locale` | ✅ |
| GET | `/shop` | shop profile | ✅ |
| PATCH | `/shop` | `name, shop_type, phone, address` — owner/manager | ✅ |
| POST | `/shop/logo` | multipart `logo` | ✅ |
| DELETE | `/shop/logo` | | ✅ |
| GET | `/shop/settings` | | ✅ |
| PATCH | `/shop/settings` | `allow_negative_stock, low_stock_threshold, receipt_width, invoice_footer, …` | ✅ |
| GET | `/meta` | public: shop types, payment methods, API version, minimum app version | ✅ |

## Dashboard — Phase 3

| Method | Path | Notes |
|---|---|---|
| GET | `/dashboard` | today's sales, profit, orders, units sold, total products, low/out-of-stock counts, total customer due, recent sales |

## Catalogue — Phase 2

| Method | Path | Notes |
|---|---|---|
| GET, POST | `/categories` | |
| PATCH, DELETE | `/categories/{id}` | |
| GET, POST | `/brands` | |
| PATCH, DELETE | `/brands/{id}` | |
| GET, POST | `/units` | built-in units + the shop's custom units |
| PATCH, DELETE | `/units/{id}` | custom units only |
| GET | `/products` | filters: `q, category_id, brand_id, vendor_id, stock=low|out|in, barcode` |
| POST | `/products` | product + `variants[]` (each with prices, opening stock, sku, barcodes[]); checks plan product limit |
| GET | `/products/{id}` | with variants, barcodes, vendors |
| PATCH | `/products/{id}` | |
| DELETE | `/products/{id}` | soft delete |
| POST | `/products/{id}/image` | multipart |
| POST | `/products/{id}/variants` | |
| PATCH, DELETE | `/variants/{id}` | |
| POST | `/variants/{id}/barcodes` | `code, type?` |
| DELETE | `/barcodes/{id}` | |
| GET | `/barcodes/lookup?code=` | → variant + product, or 404 `BARCODE_NOT_FOUND` |
| GET, POST | `/vendors` | `q` search |
| GET, PATCH, DELETE | `/vendors/{id}` | |
| GET | `/vendors/{id}/products` | |
| GET | `/vendors/{id}/purchases` | |
| GET | `/global-catalog/categories` | |
| GET | `/global-catalog/products` | `q, category_id, barcode` |
| POST | `/global-catalog/products/{id}/import` | `purchase_price, selling_price, stock, vendor_id?, variants[]?` → creates a shop product |

## Inventory — Phase 2/3

| Method | Path | Notes |
|---|---|---|
| POST | `/stock/in` | `variant_id, quantity, unit_cost?, note?` |
| POST | `/stock/out` | `variant_id, quantity, note` |
| POST | `/stock/adjust` | `variant_id, new_quantity, note` — sets the counted quantity, records the difference |
| GET | `/stock/movements` | filters: `variant_id, type, from, to` |
| GET | `/stock/alerts` | low-stock and out-of-stock variants |

## Customers and dues — Phase 3

| Method | Path | Notes |
|---|---|---|
| GET | `/customers` | `q` (name or phone), `has_due=1` |
| POST | `/customers` | `name, phone, address?, notes?, opening_due?` |
| GET | `/customers/lookup?phone=` | exact match inside this shop → customer or 404. Used at checkout |
| GET, PATCH, DELETE | `/customers/{id}` | delete refused while `current_due > 0` |
| GET | `/customers/{id}/ledger` | paged ledger with running balance |
| GET | `/customers/{id}/sales` | purchase history |
| GET | `/customers/{id}/payments` | payment history |
| POST | `/customers/{id}/collect-due` | `client_uuid, amount, method, transaction_id?, reference?, paid_at?` — rejects amounts above the outstanding due |

## Sales / POS — Phase 3

| Method | Path | Notes |
|---|---|---|
| GET | `/pos/catalog` | lightweight product grid for the POS: variants with price, stock, image thumbnail; `q, category_id` |
| POST | `/sales` | create a sale — see below |
| GET | `/sales` | filters: `from, to, customer_id, status, payment_method, q` (invoice no) |
| GET | `/sales/{id}` | items, payments, invoice link |
| POST | `/sales/{id}/void` | `reason` — owner/manager; restores stock, reverses ledger |
| GET | `/sales/{id}/invoice.pdf` | PDF download, `?width=a4|80|58` |

### `POST /sales`

```json
{
  "client_uuid": "8f6c1c0e-…",
  "sold_at": "2026-11-11T10:15:00+06:00",
  "items": [
    { "variant_id": 12, "quantity": "2", "unit_price": "600.00", "discount_amount": "0.00" }
  ],
  "discount_amount": "100.00",
  "additional_charge": "20.00",
  "grand_total": "1120.00",
  "payments": [
    { "method": "cash",  "amount": "500.00", "received_amount": "500.00" },
    { "method": "bkash", "amount": "200.00", "transaction_id": "9XK2L0" }
  ],
  "due_amount": "420.00",
  "customer_id": null,
  "customer": { "name": "Rahim Uddin", "phone": "01712345678" },
  "note": null
}
```

Server behaviour:

1. Same `client_uuid` again → returns the stored sale, `200`, nothing else changes.
2. Recomputes every total from the items. `grand_total` and `due_amount` from the client are only cross-checked; a mismatch is `422 TOTALS_MISMATCH`.
3. `Σ payments.amount + due_amount` must equal `grand_total`, else `422 PAYMENT_MISMATCH`.
4. For cash, `received_amount ≥ amount`; `change = received_amount − amount`.
5. `due_amount > 0` without `customer_id` or `customer {name, phone}` → `422 DUE_REQUIRES_CUSTOMER`.
6. `customer_id` from another shop → `422`.
7. Insufficient stock → `409 INSUFFICIENT_STOCK` with the offending variants.
8. Response `201`: the sale with `invoice_no`, `invoice_url` (public QR link), items, payments, customer and new due balance.

## Public invoice — Phase 3 (no auth, rate-limited)

| Method | Path | Notes |
|---|---|---|
| GET | `/i/{token}` (web route) | read-only HTML invoice |
| GET | `/i/{token}/pdf` | PDF |
| GET | `/api/v1/public/invoices/{token}` | JSON, same data, customer phone masked |

## Reports — Phase 4

All accept `range=today|yesterday|last_7_days|this_week|this_month|custom` with `from`, `to` for custom.

| Method | Path | Notes |
|---|---|---|
| GET | `/reports/summary` | total sales, orders, units sold, paid, due, discounts, charges, cost, gross profit |
| GET | `/reports/payment-methods` | totals per method, including due collections |
| GET | `/reports/best-sellers` | by quantity and by revenue |
| GET | `/reports/low-stock` | |
| GET | `/reports/sales` | sales history rows |
| GET | `/reports/dues` | customers with outstanding due |
| POST | `/reports/{report}/export` | `format=xlsx|csv|pdf` → file, or a queued job + download URL for large ranges |

## Offline sync — Phase 5

| Method | Path | Notes |
|---|---|---|
| POST | `/devices` | register the phone: `device_uuid, name, platform, app_version, fcm_token?` |
| GET | `/sync/pull?since=<cursor>&types=products,variants,barcodes,categories,customers` | changed and deleted rows since the cursor + the next cursor |
| POST | `/sync/push` | `{ "customers": [...], "sales": [...], "due_collections": [...] }`, max 50 per call. Response lists each `client_uuid` with `status: created|duplicate|failed`, the server record and, for failures, `code` + `message` |

`/sync/push` processes each record in its own transaction, so one bad sale does not block the rest.

## Subscription (shop side) — Phase 6

| Method | Path | Notes |
|---|---|---|
| GET | `/subscription` | current plan, expiry, limits, usage |
| GET | `/plans` | plans available for upgrade |

Plan changes and renewals are performed by the admin (or, later, by a payment gateway callback).

## Admin panel

The admin panel is server-rendered Livewire at `/admin`, not a JSON API. Its screens are listed in `01-architecture.md` §7 and `04-project-structure.md`.
