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

## Dashboard — ✅ implemented in Phase 3

| Method | Path | Notes |
|---|---|---|
| GET | `/dashboard` | `today` (`sales, profit, orders, items_sold, paid, due`), `stock`, `total_customer_due`, `customers_with_due`, `recent_sales` |

"Today" is the shop's own calendar day (its time zone). Cancelled sales are excluded.
`profit` = items after discounts − their cost at the time of sale, plus additional charges when the shop counts them as income. It is omitted for roles without `reports.view`.

## Catalogue — ✅ implemented in Phase 2

Reads need the `products` module (in every plan). Writes also need the `catalog.manage` permission (owner, manager).

| Method | Path | Notes |
|---|---|---|
| GET, POST | `/categories` | |
| GET, PATCH, DELETE | `/categories/{id}` | Delete is refused while sub-categories exist; products become uncategorised |
| GET, POST | `/brands` | `q` search |
| PATCH, DELETE | `/brands/{id}` | Deleting leaves products without a brand |
| GET, POST | `/units` | Built-in units plus the shop's own |
| PATCH, DELETE | `/units/{id}` | The shop's own units only; refused while products use it (`UNIT_IN_USE`) |
| GET | `/products` | `q` (name, or exact barcode/SKU), `category_id`, `brand_id`, `vendor_id`, `stock=low|out|in`, `page`, `per_page` |
| POST | `/products` | Product with `variants[]`; checks the plan's product limit (`PLAN_LIMIT_REACHED`) |
| GET | `/products/{id}` | With variants, barcodes, category, brand, unit, vendor, stock status |
| PATCH | `/products/{id}` | Product fields; if `variants[]` is sent it is the complete set (see below) |
| DELETE | `/products/{id}` | Soft delete; frees its barcodes |
| POST, DELETE | `/products/{id}/image` | multipart `image`; re-encoded to JPEG, max 800px |
| GET | `/barcodes/lookup?code=` | → `{ code, variant_id, product }`, or 404 `BARCODE_NOT_FOUND` |

### Product payload

```json
{
  "name": "Polo T-shirt",
  "unit_id": 1,
  "category_id": 4, "brand_id": null, "vendor_id": null,
  "storage_location": "Rack 3", "description": null, "low_stock_threshold": "5",
  "has_variants": true,
  "variants": [
    { "name": "S", "attributes": {"size": "S"}, "purchase_price": "200", "selling_price": "350",
      "stock_quantity": "4", "sku": "TS-S", "barcodes": ["8901234567890"] },
    { "id": 12, "name": "M", "purchase_price": "210", "selling_price": "360", "barcodes": [] }
  ]
}
```

- A product without variants sends `has_variants: false` and exactly one variant with no name.
- On update, variants with an `id` are changed, variants without are created, and existing variants left out are removed. A variant that still has stock cannot be removed (`409 VARIANT_HAS_STOCK`).
- `stock_quantity` is the opening stock and only applies to variants being created. Existing stock changes only through the stock endpoints.
- A barcode can belong to one variant per shop (`422 BARCODE_TAKEN`).
- Quantities must be whole numbers unless the product's unit allows decimals (`422 QUANTITY_MUST_BE_WHOLE`).

## Vendors — ✅ implemented in Phase 2 (module `vendors`)

| Method | Path | Notes |
|---|---|---|
| GET, POST | `/vendors` | `q` searches name, phone and company |
| GET, PATCH, DELETE | `/vendors/{id}` | Deleting leaves the vendor's products in place, unlinked |
| GET | `/vendors/{id}/products` | |
| GET | `/vendors/{id}/purchases` | Stock-in entries that named this vendor, newest first |

Writes need `vendors.manage`.

## Global catalogue — ✅ implemented in Phase 2 (module `global_catalog`)

| Method | Path | Notes |
|---|---|---|
| GET | `/global-catalog/categories` | |
| GET | `/global-catalog/products` | `q`, `category_id`; each row has `already_imported` for the current shop |
| POST | `/global-catalog/products/{id}/import` | `purchase_price?, selling_price?, stock_quantity?, vendor_id?, variants[]?` (per-variant prices by `global_variant_id`) → the new shop product |

## Inventory — ✅ implemented in Phase 2

| Method | Path | Notes |
|---|---|---|
| POST | `/stock/in` | `variant_id, quantity, unit_cost?, vendor_id?, note?`. A cost, when given, becomes the variant's current purchase price |
| POST | `/stock/out` | `variant_id, quantity, note` (a reason is required). `409 INSUFFICIENT_STOCK` unless the shop allows negative stock |
| POST | `/stock/adjust` | `variant_id, new_quantity, note?` — sets the counted quantity and records the difference |
| GET | `/stock/summary` | `total_products, low_stock_products, out_of_stock_products` |
| GET | `/stock/movements` | Module `inventory`. Filters: `variant_id, product_id, type, from, to` |

Stock in, out and adjust are part of every plan and need `inventory.manage`. Only the full movement history is a paid module.

## Customers and dues — ✅ implemented in Phase 3 (module `customers`)

| Method | Path | Notes |
|---|---|---|
| GET | `/customers` | `q` (name or phone), `has_due=1` (largest due first) |
| POST | `/customers` | `name, phone, address?, notes?, credit_limit?, opening_due?`. `422 CUSTOMER_EXISTS` for a phone already in this shop |
| GET | `/customers/lookup?phone=` | Exact match inside this shop → customer, or `404 CUSTOMER_NOT_FOUND`. Used at checkout |
| GET, PATCH, DELETE | `/customers/{id}` | The balance cannot be edited. Delete is refused while the balance is not zero (`409 CUSTOMER_HAS_DUE`) |
| GET | `/customers/{id}/ledger` | Newest first, each entry with `debit`, `credit`, `balance_after` |
| GET | `/customers/{id}/sales` | Purchase history |
| GET | `/customers/{id}/payments` | Payment history |
| POST | `/customers/{id}/collect-due` | `client_uuid, amount, method, transaction_id?, reference?`. More than is owed → `422 AMOUNT_EXCEEDS_DUE`. The same `client_uuid` again returns the first result with `200` |

Writes need `customers.manage`; collecting needs `due.collect`.

## Sales / POS — ✅ implemented in Phase 3 (module `pos`)

| Method | Path | Notes |
|---|---|---|
| POST | `/sales` | Create a sale — see below. Needs `pos.sell` |
| GET | `/sales` | Filters: `from, to` (days in the shop's time zone), `customer_id, status, payment_method, has_due, q` (invoice no) |
| GET | `/sales/{id}` | Items, payments, customer, `invoice_url`. `total_cost` and `gross_profit` only for roles with `reports.view` |
| POST | `/sales/{id}/void` | `reason`. Needs `sales.void`. Stock returns, the due is taken off the ledger, payments are recorded as refunded. `409 SALE_ALREADY_VOIDED` |
| GET | `/sales/{id}/invoice.pdf` | `?width=a4|80|58` |

The product list for the counter is `GET /products`; there is no separate POS catalogue endpoint.

### `POST /sales`

```json
{
  "client_uuid": "8f6c1c0e-1111-4222-8333-444455556666",
  "sold_at": "2026-11-12T10:15:00+06:00",
  "items": [
    { "variant_id": 12, "quantity": "2", "unit_price": "600.00", "discount_amount": "0.00" }
  ],
  "discount_amount": "100.00",
  "additional_charge": "20.00",
  "grand_total": "1120.00",
  "payments": [
    { "method": "cash",  "amount": "500.00", "received_amount": "1000.00" },
    { "method": "bkash", "amount": "200.00", "transaction_id": "9XK2L0" }
  ],
  "due_amount": "420.00",
  "customer_id": null,
  "customer": { "name": "Rahim Uddin", "phone": "01712345678" },
  "note": null
}
```

`client_uuid`, `items`, `grand_total` and `due_amount` are required. Payment methods: `cash, bkash, nagad, bank, card, other`.

Server behaviour, in order:

1. The same `client_uuid` again → the stored sale, `200`, nothing else changes. A new sale is `201`.
2. Prices and costs are read from the database. A `unit_price` that differs from the catalogue price needs `pos.price_override` (otherwise `403 PRICE_OVERRIDE_NOT_ALLOWED`) and is audited.
3. Stock is checked across the whole cart: `409 INSUFFICIENT_STOCK` with `errors` naming each short line, unless the shop allows negative stock.
4. Totals are computed by the server: each line is `round(unit_price × quantity, 2) − line discount`, half-up; `grand_total = subtotal − discount + additional_charge`. A `grand_total` that disagrees is `422 TOTALS_MISMATCH`, with the server's figure in `errors.grand_total`.
5. `Σ payments.amount + due_amount` must equal `grand_total` exactly, else `422 PAYMENT_MISMATCH`. For cash, `received_amount ≥ amount`; the difference is change and is not a payment.
6. `due_amount > 0` needs `customer_id` or `customer.phone` (`422 DUE_REQUIRES_CUSTOMER`). The customer is found by phone in this shop, or created — a new customer needs `customer.name` (`422 CUSTOMER_NAME_REQUIRED`). A fully paid sale needs no customer.
7. A customer's `credit_limit`, when set, is enforced (`422 CREDIT_LIMIT_EXCEEDED`). The plan's monthly sales limit is enforced (`403 PLAN_LIMIT_REACHED`).
8. Mobile-money and card payments are stored with `verification: "unverified"`. Nothing in the system marks them verified without a gateway.

## Public invoice — ✅ implemented in Phase 3 (no login, 30 requests a minute per IP)

| Method | Path | Notes |
|---|---|---|
| GET | `/i/{token}` | Read-only HTML invoice. No session, no cookies, `noindex` |
| GET | `/i/{token}/pdf` | The same invoice as PDF |
| GET | `/api/v1/public/invoices/{token}` | JSON with the same data |

The token is 32 random bytes (43 base64url characters). Database ids and invoice numbers do not work in its place.
The public invoice contains no ids, no cost, no transaction ids, and the customer's phone only masked (`018*****678`).

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
