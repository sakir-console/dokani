# Dokani — Shop Management SaaS for Bangladesh

*One App. Every Shop. Complete Business Management.*

A multi-tenant shop management platform: a Flutter app for shop owners (products, POS, barcode scanning, dues, invoices, reports, offline sales) and a Laravel backend with a global admin panel.

## Repository layout

| Path | What |
|---|---|
| [`docs/`](docs/) | Architecture, database design, API, roadmap and progress record |
| `backend/` | Laravel REST API, admin panel, public invoice page |
| `mobile/` | Flutter shop owner app |

## Documentation

1. [System architecture, tenancy, security, risks](docs/01-architecture.md)
2. [Database ERD and table design](docs/02-database.md)
3. [API endpoints](docs/03-api.md)
4. [Laravel, Flutter and admin panel structure](docs/04-project-structure.md)
5. [Roadmap and feature status](docs/05-roadmap.md)
6. [Setup, commands and testing](docs/06-setup.md)

## Status

Phases 1 to 3 are complete: authentication, multi-tenant isolation, plans and modules, the admin panel (shops, global catalogue), products with variants and barcodes, stock, vendors, the point of sale with split and partial payments, customer dues and ledger, and invoices with PDF and QR.
Reports, offline selling, subscription management and printing are not built yet.

The project is **not production-ready**. The status table in [`docs/05-roadmap.md`](docs/05-roadmap.md) says exactly what is built and tested.
