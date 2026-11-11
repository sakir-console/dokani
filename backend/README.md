# Dokani backend

Laravel application serving three things:

- the mobile REST API at `/api/v1`
- the Global Admin panel at `/admin` (Livewire + Tailwind)
- the public invoice page (from Phase 3)

Setup, environment variables and test instructions: [`../docs/06-setup.md`](../docs/06-setup.md).
Architecture and tenancy rules: [`../docs/01-architecture.md`](../docs/01-architecture.md).

## Rules for anyone adding code here

1. **Every shop-owned model uses the `BelongsToShop` trait** and has a `shop_id` column. Never write `where('shop_id', …)` by hand, and never make `shop_id` fillable.
2. **Never read a shop id from the request.** The current shop is `TenantContext`, set by the `tenant` middleware.
3. **Validate ids from the client with `ExistsInShop`**, not `exists:table,id`.
4. **Inject `TenantContext` and other request-scoped services into controller methods**, not constructors.
5. **Every new tenant endpoint gets a case in `tests/Feature/Api/TenantIsolationTest.php`.**
6. Money and stock changes happen in one service, inside one database transaction.
