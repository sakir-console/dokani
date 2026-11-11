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

Legend: ✅ done and tested · 🟡 partly done · ⬜ not started

| Area | Backend | Admin | Mobile | Notes |
|---|---|---|---|---|
| Architecture documents | ✅ | ✅ | ✅ | Phase 0 |
| Authentication | ⬜ | ⬜ | ⬜ | |
| Tenant isolation foundation | ⬜ | – | – | |
| Shop profile and settings | ⬜ | ⬜ | ⬜ | |
| Plans / modules / entitlements | ⬜ | ⬜ | ⬜ | |
| Categories, brands, units | ⬜ | – | ⬜ | |
| Products and variants | ⬜ | – | ⬜ | |
| Barcodes and scanner | ⬜ | – | ⬜ | |
| Vendors | ⬜ | – | ⬜ | |
| Global catalogue | ⬜ | ⬜ | ⬜ | |
| Inventory | ⬜ | – | ⬜ | |
| Customers and ledger | ⬜ | – | ⬜ | |
| POS and sales | ⬜ | – | ⬜ | |
| Payments (split, partial, due) | ⬜ | – | ⬜ | |
| Due collection | ⬜ | – | ⬜ | |
| Invoices (page, PDF, QR) | ⬜ | – | ⬜ | |
| Dashboard | ⬜ | ⬜ | ⬜ | |
| Reports and exports | ⬜ | – | ⬜ | |
| Offline sync | ⬜ | – | ⬜ | |
| Subscription management | ⬜ | ⬜ | ⬜ | |
| Thermal printing | – | – | ⬜ | needs printers to test |
| Push notifications | ⬜ | – | ⬜ | needs Firebase project |
| Deployment and backups | ⬜ | – | – | |

This table is updated at the end of every phase.
