# Pensil Warung: database

Context for agents working on this repo. The schema lives in `backend/migrations/V1__init.sql` (PostgreSQL 18).

## What the app is
Mobile sales notebook for small Indonesian warung owners (UI text is Indonesian). The owner types sales as plain text ("nasi goreng 2"); the app parses them into transactions and updates stock. There is also a separate broadcaster role that posts announcements to all users. Source design: the Hi-Fi page of the "Pensil Warung Onboarding" canvas. Light and dark screens are the same data.

## Stack decisions
- PostgreSQL 18 or newer (the schema uses `uuidv7()`), one account = one warung (no staff or shop table).
- Hosting: Aiven service `db-pensil-warung` (project `achyon-eafb`, database `defaultdb`).
- Login: Google (direct official credentials, no Supabase/Neon Auth) plus email/password. Identities live in `auth_identities`.
- Offline mode is out of scope for v1. `transactions.client_uuid` is kept for retry safety later.
- Theme and text size are not stored. The app handles them.

## Conventions
- Money: whole rupiah, `bigint`. Never float.
- Quantity and stock: `numeric(12,3)`. The UI uses whole numbers for now.
- Time: `timestamptz`. History day grouping uses `Asia/Jakarta` (see `v_daily_sales`).
- Keys: `users.id` is uuid, version 7 by default (time-ordered, so an id reveals when it was created). Everything else is an integer identity.

## Tables
- `roles`, `permissions`, `role_permission`: plain id + name. Seeded: role 1 = user, 2 = broadcaster. `users.role_id` defaults to 1.
- `users`: `email`, `display_name`, `username`, `role_id`, `token_version` (starts at 0, bumped on email or password change; a JWT whose `ver` differs is rejected).
- `auth_identities`: one row per login method per user.
- `products`: name (unique per user, case-insensitive), price, stock, optional photo (`photo_key`, a Tigris object key; the API returns presigned URLs).
- `transactions`: one "Simpan" = one transaction. Holds `raw_text`, `total`, `status` (completed or voided).
- `transaction_items`: snapshot of name and price at sale time.
- `stock_movements`: ledger of every stock change (initial, sale, void_sale, restock, adjustment).
- `broadcasts`: category, title (60), summary (120), optional body, status (scheduled, sent, cancelled), `broadcasted_at` is the sent time.

## Rules to keep
- Never `UPDATE products.stock`. Insert a `stock_movements` row; a trigger applies it. Selling more than the stock fails with SQLSTATE 23514 and rolls back the whole sale.
- Insert a transaction, then its items, in one database transaction; item triggers create the sale movements. Pass `total` and each `line_total = round(quantity * unit_price)`.
- Transactions are never deleted. Void them (`status = 'voided'` and set `voided_at`): stock is restored and a void cannot be undone.
- Deleting a product is a hard delete. Past sale items keep their name and price (`product_id` becomes NULL). The product's stock movements are deleted with it.
- Broadcast feed query: `WHERE status = 'sent' ORDER BY broadcasted_at DESC, id DESC LIMIT 5`. No per-user cursor or read-state.
- Names: `display_name` allows only letters, digits and spaces. The database does not clean names, it rejects bad ones (check `users_display_name_chars`). The trigger only fills a blank name with `user <n>`.
- Usernames: `generate_username()` returns `siti_rahayu`, then `siti_rahayu_1`, and so on. It is best effort, so retry once on SQLSTATE 23505.

## Backend responsibilities (not enforced by the database)
- Sanitize names (strip accents and symbols) in the backend and UI before insert.
- Check permissions before writes, for example only `broadcast.create` may insert broadcasts.
- Parse the typed text, match product names, and surface "barang tidak ditemukan".
- Check that a sale only uses the seller's own products, and that `total` equals the sum of the line totals.
- Move scheduled broadcasts to `sent` and set `broadcasted_at` when due.

## Migrations
Run from `backend/` with `cargo run -- migrate`. Migrations are embedded by refinery. Each one runs in its own transaction, and applied versions are recorded in `refinery_schema_history`. Running it again does nothing.

Once a migration has been applied to a shared database, do not edit it; add a new `V<n>__name.sql` file instead.

## Testing
Database tests are in `backend/tests/` (for example `tests/migrations.rs`). They create a throwaway Postgres 18 database per test. See `backend/README.md` for how to run them.
