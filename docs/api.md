# Pensil Warung API

Reference for the HTTP API as it is built. It grows as branches merge. Only what exists in the code is listed here.

## Conventions

| Topic | Rule |
|---|---|
| Base path | `/api/v1`. The only route outside it is `GET /health` |
| Format | JSON only. Request bodies need `Content-Type: application/json` |
| Auth | Bearer token: `Authorization: Bearer <jwt>`. Get one from the auth endpoints below. It is an HS256 JWT valid for 7 days (`JWT_EXPIRES_IN`), and there is no refresh token: log in again after it expires. A missing, bad, expired or revoked token gives `401 unauthorized`. Changing the email or password revokes every token the user holds, on all devices, including the one that made the change; the client must log in again. Each request costs one primary-key lookup to check this. The `/me` routes require it |
| Times | RFC 3339 strings, for example `2026-11-26T08:00:00Z` |
| Money | Whole rupiah as JSON integers, for example `15000` for Rp15.000. No decimals |
| Body limit | 64 KB by default. A route can set a higher limit |
| Timeout | 15 seconds. A slower request gets `504` (see Errors) |
| Request id | Every response has an `x-request-id` header. If the request sends one, the same value is sent back. If not, the server makes a UUID |
| Unknown paths | `404` with the error envelope below |

## Errors

Every error response has this shape:

```json
{
  "error": {
    "code": "not_found",
    "message": "Data tidak ditemukan.",
    "details": { "field": "price" }
  }
}
```

- `code` is a stable snake_case string. Clients should switch on it, not on `message`.
- `message` is in Indonesian. It is meant for the user.
- `details` is optional. It is only present when there is extra information. A field error uses `{ "field": "<name>" }`. A bad body, query or path uses `{ "reason": "<text>" }`. The reason text comes from the parser and never echoes the request body.

### Error codes

The default status and message come from `backend/src/error.rs`. "Used" says whether a route returns the code today:

- **now**: returned by a route or the server today.
- **SQL map**: mapped from a database error, but no route can reach it yet.
- **later**: defined for a later branch.

| Code | HTTP | Default message | Used | When |
|---|---|---|---|---|
| `invalid_body` | 400 | Isi permintaan tidak valid. | now | Malformed JSON, wrong shape, or missing JSON content type |
| `invalid_query` | 400 | Parameter permintaan tidak valid. | now | A query string value does not parse |
| `invalid_path` | 400 | Alamat permintaan tidak valid. | now | A path parameter does not parse |
| `invalid_value` | 422 | Nilai yang dimasukkan tidak valid. | now | A field fails a rule (`GET /transactions` `date` or `cursor`, void `reason`, email format, username format, password length, field too long, missing `current_password`, negative price or stock, `note` without `stock`, bulk size, `POST /catat` batch rules, a total too large). A database check failure (other than stock) gives 422. An unknown unique index gives 409 with this code |
| `invalid_name` | 422 | Nama yang dimasukkan tidak valid. | now | `PATCH /me/display-name`: empty after cleaning, or over 50 characters. Products: name empty or over 60 characters. Also a line code in `lines_invalid` (`POST /catat`) |
| `invalid_quantity` | 422 | Jumlah yang dimasukkan tidak valid. | now | Line code in `lines_invalid` (`POST /catat`): quantity is not a whole number from 1 to 999 999 999 |
| `invalid_price` | 422 | Harga yang dimasukkan tidak valid. | now | Line code in `lines_invalid` (`POST /catat`): `create_product` price is not a whole number >= 0 |
| `product_not_found` | 404 | Produk tidak ditemukan. | now | Line code in `lines_invalid` (`POST /catat`): no product of the user's has that name at that point in the batch. Never returned as a top-level error |
| `lines_invalid` | 422 | Ada baris yang tidak valid. | now | `POST /catat`: one or more lines failed. `details.lines` lists every failure, and nothing is saved |
| `not_found` | 404 | Data tidak ditemukan. | now | Unknown route, or the record does not exist |
| `unauthorized` | 401 | Sesi Anda telah berakhir. Silakan masuk kembali. | now | Missing or invalid bearer token. `POST /auth/google` also returns it for a bad Google ID token, with the message "Token Google tidak valid." |
| `invalid_credentials` | 401 | Email atau kata sandi salah. | now | Wrong email or password at login. Also a wrong `current_password` on the `/me` routes (message "Kata sandi saat ini salah.") |
| `forbidden` | 403 | Anda tidak memiliki akses untuk tindakan ini. | now | Signed in, but the role lacks the permission (all `/products` routes need `product.manage`; `POST /catat` needs `transaction.create`, plus `product.manage` for non-sale ops; the `/transactions` reads need `transaction.read` and void needs `transaction.void`) |
| `account_gone` | 401 | Akun tidak ditemukan. Silakan masuk kembali. | now | The user no longer exists. A foreign key violation (SQLSTATE 23503) maps here |
| `email_taken` | 409 | Email sudah digunakan. | now | Unique violation on `users.email` (register or `PATCH /me/email` with an existing email) |
| `username_taken` | 409 | Username sudah digunakan. | now | Unique violation on `users.username` (`PATCH /me/username`). Register and Google sign-up retry once before this can surface |
| `name_taken` | 409 | Nama produk sudah digunakan. | now | Unique violation on a product name for this user (create, bulk, rename). Bulk adds `details.index`. Also a line code in `lines_invalid` (`POST /catat`, 422) for a `create_product` whose name is taken |
| `email_registered` | 409 | Email ini sudah terdaftar. Silakan masuk dengan kata sandi. | now | Google sign-in with an email that already has a password account |
| `google_account` | 403 | Akun ini masuk dengan Google, sehingga tidak dapat diubah di sini. | now | Email or password change on a Google-only account |
| `reauth_required` | 401 | Silakan verifikasi ulang akun Anda untuk melanjutkan. | now | `DELETE /me` for a Google-only account without a fresh matching Google ID token |
| `stock_insufficient` | 422 | Stok tidak cukup. | now | Line code in `lines_invalid` (`POST /catat`): a sale or `adjust_down` would take stock below zero. Not reachable from `/products` (PATCH sets an absolute stock >= 0). A bare 422 with this code is only the SQL map for the same check |
| `nothing_to_update` | 422 | Tidak ada data yang diubah. | now | `PATCH /products/{id}` with no fields |
| `already_voided` | 409 | Transaksi ini sudah dibatalkan. | now | `POST /transactions/{id}/void` on a transaction that is already voided |
| `not_editable` | 409 | Data ini tidak dapat diubah. | later | The record cannot be changed in its current state |
| `time_passed` | 422 | Waktu untuk tindakan ini sudah lewat. | later | The time window for an action has passed |
| `payload_too_large` | 413 | Ukuran berkas terlalu besar. | now | Body is over the limit, or the `photo` file is over 5 MB (`PUT /products/{id}/photo`). The message says "berkas" (file) even for JSON |
| `unsupported_image` | 415 | Foto harus berformat JPEG, PNG, atau WebP. | now | `PUT /products/{id}/photo`: the bytes are not a decodable JPEG, PNG or WebP (or the image is over 8000 px on a side) |
| `storage_unavailable` | 503 | Penyimpanan foto belum tersedia. | now | Photo storage is not configured, or the upload to it failed. Both photo routes return it |
| `db_unavailable` | 503 | Layanan sedang tidak tersedia. Coba lagi sebentar. | now | No database connection could be made, or the connection dropped |
| `internal` | 500 | Terjadi kesalahan pada server. | now | Unexpected error, including an unmapped database error. The timeout also uses this code, with status 504 and the message "Permintaan terlalu lama diproses. Coba lagi sebentar." |

Notes:

- The timeout returns `504`, not `500`, but the code is still `internal`.
- A wrong HTTP method on a known path (for example `DELETE /health`) returns `405` from Axum with an empty body. It is not in the JSON shape yet.

## Endpoints

### GET /health

Liveness check for Render. It does not touch the database. No auth.

`200 OK`

```json
{ "status": "ok" }
```

### GET /api/v1/health/db

Readiness check. Runs `SELECT 1` on the database. No auth.

`200 OK`

```json
{ "status": "ok" }
```

`503 Service Unavailable` when the database cannot be reached:

```json
{
  "error": {
    "code": "db_unavailable",
    "message": "Layanan sedang tidak tersedia. Coba lagi sebentar."
  }
}
```

## Auth

All three endpoints return a `token` (see Conventions) and the `user` object. They need no bearer token.

The `user` object:

| Field | Type | Notes |
|---|---|---|
| `id` | string (uuid) | |
| `display_name` | string | Letters, digits and spaces only. A blank name becomes `user <n>` |
| `username` | string | Generated from the display name, for example `siti_rahayu`, then `siti_rahayu_1` |
| `email` | string | Lowercase |
| `role` | string | `user` or `broadcaster` |
| `permissions` | string[] | Permissions of the role |
| `has_password` | boolean | `false` for a Google-only account |

### POST /api/v1/auth/register

```json
{ "display_name": "Siti Rahayu", "email": "siti@example.com", "password": "rahasia123" }
```

- The email is trimmed and lowercased. The password is 8 to 128 characters. `display_name` is at most 100 characters before cleaning.
- `201 Created` with `{ "token": "<jwt>", "user": { ... } }`.
- Errors: `invalid_value` (422, with `details.field`), `email_taken` (409).

### POST /api/v1/auth/login

```json
{ "email": "siti@example.com", "password": "rahasia123" }
```

- `200 OK` with `{ "token": "<jwt>", "user": { ... } }`.
- Errors: `invalid_credentials` (401). A wrong password, an unknown email and a Google-only account all give the same response.

### POST /api/v1/auth/google

```json
{ "id_token": "<Google ID token>" }
```

- The token must be signed by Google, have `aud` in `GOOGLE_CLIENT_IDS`, an accepted `iss`, not be expired, and have a verified email.
- A known Google account logs in: `200 OK` with `{ "token": "<jwt>", "user": { ... }, "created": false }`.
- A new Google account and a new email creates the user (display name from the Google name): `201 Created` with `"created": true`.
- Errors: `unauthorized` (401, bad Google token), `email_registered` (409, the email already has an account. Accounts are never linked automatically).

## Account

All `/me` routes need a bearer token (any role). The `PATCH` routes return the updated `user` object (same shape as under Auth). If the user no longer exists, they return `401 account_gone`.

### GET /api/v1/me

`200 OK` with the `user` object.

### PATCH /api/v1/me/username

```json
{ "username": "warung_siti" }
```

- Must match `^[a-z0-9_]{3,30}$`.
- Errors: `invalid_value` (422), `username_taken` (409).

### PATCH /api/v1/me/display-name

```json
{ "display_name": "Warung Siti" }
```

- Cleaned like at register (letters, digits and spaces). The result must be 1 to 50 characters. The username does not change. At most 100 characters before cleaning.
- Errors: `invalid_name` (422), `invalid_value` (422, too long).

### PATCH /api/v1/me/email

```json
{ "email": "baru@example.com", "current_password": "rahasia123" }
```

- The email is trimmed and lowercased. There is no verification email.
- On success all of the user's tokens stop working, including the one used for this call: the next request gets `401 unauthorized`, so the client must log in again with the new email. The response is still `200` with the updated user.
- Errors: `invalid_value` (422), `invalid_credentials` (401, wrong password), `google_account` (403, Google-only account), `email_taken` (409).

### PUT /api/v1/me/password

```json
{ "current_password": "rahasia123", "new_password": "rahasia456" }
```

- `new_password` is 8 to 128 characters. `204 No Content`.
- On success all of the user's tokens stop working, including the one used for this call: the client must log in again with the new password.
- The `details.field` of a length error is `new_password`.
- Errors: `invalid_value` (422), `invalid_credentials` (401), `google_account` (403).

### DELETE /api/v1/me

Deletes the account and all of the warung's data. Broadcasts the user created stay, with `created_by` set to null. `204 No Content`.

Users with a password send:

```json
{ "current_password": "rahasia123" }
```

Google-only users send a Google ID token from a fresh sign-in:

```json
{ "id_token": "<Google ID token>" }
```

- The token must pass the same checks as `POST /auth/google`, its `sub` must be this user's Google identity, and its `iat` must be at most 5 minutes old (a small clock skew into the future is allowed).
- Errors: `invalid_credentials` (401, wrong password), `invalid_value` (422, password user without `current_password`), `reauth_required` (401, Google-only user with a missing, stale, invalid or mismatched token).
- An old JWT of a deleted user still decodes: later `/me` calls return `401 account_gone`.

## Products

All routes need a bearer token and the `product.manage` permission (else `403 forbidden`). Every query is scoped to the caller: another user's product is `404 not_found`.

Product object:

```json
{ "id": 1, "name": "Nasi Goreng", "price": 15000, "stock": 10, "photo_url": null, "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z" }
```

- `price` is whole rupiah. `stock` is a whole number, sent and returned as a JSON integer (a decimal such as `1.5` is `400 invalid_body`). `photo_url` is described under Photos below.
- `name` is trimmed and inner whitespace collapsed, 1 to 60 characters. It is unique per user ignoring case (`Nasi Goreng` = `nasi  goreng`), else `409 name_taken`. Other users may reuse a name.
- `price` and `stock` must be >= 0 (`422 invalid_value`, `details.field`).

### GET /api/v1/products?q=

`200 OK` with `{ "items": [product], "count": 2 }`: all of the user's products ordered by name (case-insensitive), not paged. `q` is an optional case-insensitive substring of the name; `%`, `_` and `\` match literally.

### GET /api/v1/products/{id}

`200 OK` with the product. `404 not_found` if it is not the user's.

### POST /api/v1/products

```json
{ "name": "Nasi Goreng", "price": 15000, "stock": 10 }
```

`201 Created` with the product. A `stock` above 0 is recorded as an `initial` stock movement. Errors: `invalid_name`, `invalid_value` (422), `name_taken` (409).

### POST /api/v1/products/bulk

```json
{ "items": [{ "name": "Teh", "price": 3000, "stock": 0 }, { "name": "Kopi", "price": 4000, "stock": 7 }] }
```

1 to 50 items. `201 Created` with `{ "items": [product] }` in request order. All or nothing: if any item fails, nothing is saved. A duplicate name returns `409 name_taken` with `details.index` (0-based): the later item when two items in the request clash, or the item that clashes with an existing product. Other errors are as for `POST /products`; `invalid_value` for a wrong item count has `details.field = "items"`.

### PATCH /api/v1/products/{id}

```json
{ "name": "Nasi Goreng Spesial", "price": 18000, "stock": 12, "note": "belanja pasar" }
```

All fields are optional; `200 OK` with the updated product.

- `stock` is the NEW absolute stock (integer >= 0), not a delta. The server compares it with the current stock inside one transaction (row locked) and records the difference in the stock ledger: a `restock` movement when it goes up, an `adjustment` when it goes down. The stock itself is never written directly.
- If `stock` equals the current stock, nothing is recorded and `note` is ignored.
- `note` (up to 200 characters after trimming) is stored on the movement. It is only valid together with `stock`: alone it is `422 invalid_value` with `details.field = "note"`.
- An empty body (`{}`) is `422 nothing_to_update`.
- Renaming follows the name rules above. Changing only the case of the product's own name is allowed.
- Errors: `nothing_to_update`, `invalid_name`, `invalid_value` (422), `name_taken` (409), `not_found` (404).

### DELETE /api/v1/products/{id}

`204 No Content`; `404 not_found` if it is not the user's. A hard delete: the product's stock movements go with it, while past sale items keep their name and price snapshot (their `product_id` becomes null).

### Photos

`photo_url` is a presigned URL for the product's photo, or `null` when the product has no photo (or the server has no photo storage). The URL expires after `IMAGE_URL_TTL_SECONDS` (default 3600) and is different on every response, so the client should cache the image by product id plus photo (for example `updated_at` after a photo change), not by URL. Every product response carries it: list, get, create, bulk, patch and the photo PUT.

#### PUT /api/v1/products/{id}/photo

`multipart/form-data` with one file field named `photo`: JPEG, PNG or WebP, at most 5 MB. The type is detected from the file bytes, the client's content type is ignored. The server stores it as a JPEG with the longest side at most 512 px (never enlarged, transparency becomes white), replacing any earlier photo. `200 OK` with the product, including its new `photo_url`.

Errors: `invalid_body` (400, no `photo` field or bad multipart), `not_found` (404), `payload_too_large` (413), `unsupported_image` (415), `storage_unavailable` (503).

#### DELETE /api/v1/products/{id}/photo

`204 No Content`. Idempotent: also 204 when the product has no photo. Errors: `not_found` (404), `storage_unavailable` (503).

## Catat

### POST /api/v1/catat

One Simpan on the Catat screen: everything typed in the box is saved as one atomic batch (all lines, or nothing). Needs `transaction.create`, plus `product.manage` when the batch has any op that is not a `sale` (else `403 forbidden`, checked before any database work). Every lookup is scoped to the caller's own products.

The client parses the typed text and sends structured ops. The server never parses text.

Request:

```json
{
  "client_uuid": "0193d5a0-7c1e-7a55-9b0e-3f6c1d2e4a10",
  "raw_text": "nasi goreng 2\nes teh manis 3\ntambah stok kopi susu 10",
  "ops": [
    { "line_no": 1, "op": "sale", "product": "Nasi goreng", "quantity": 2 },
    { "line_no": 2, "op": "sale", "product": "Es teh manis", "quantity": 3 },
    { "line_no": 3, "op": "restock", "product": "Kopi susu", "quantity": 10 }
  ]
}
```

- `client_uuid`: a UUID made by the phone for this Simpan, used for retries (see Replay).
- `raw_text`: exactly what was typed, stored as is on the transaction. Required, at most 20 000 characters.
- `ops`: 1 to 200 lines, each with a unique `line_no`. They run in `line_no` order.
- `occurred_at` is not accepted: the time is always the server's `now()`. Any unknown field (including a client price) is ignored.

Ops (`product` is matched against the user's product names ignoring case and extra spaces):

| `op` | Fields | Effect |
|---|---|---|
| `sale` | `product`, `quantity` | An item on the batch's one transaction. The price is always the product's current `price` |
| `restock` | `product`, `quantity` | Stock movement `restock`, `+quantity`. No transaction |
| `adjust_down` | `product`, `quantity` | Stock movement `adjustment`, `-quantity` (damaged or lost goods). No transaction |
| `create_product` | `name`, `price`, `stock` | A new product. A `stock` above 0 gets an `initial` movement |
| `delete_product` | `product` | Hard delete, plus the photo object. Past sale items keep their snapshot with `product_id: null` |

`quantity`, `price` and `stock` are JSON integers. A decimal or out-of-range number is a line error (not a 400). A quantity is 1 to 999 999 999.

Batch rules: a product created earlier in the batch can be used by later lines, and a product deleted earlier cannot. Restocks and creates earlier in the batch count toward later stock checks. The same product on two sale lines gives two items. All `sale` lines together make one transaction; with no sale line there is no transaction.

Response `201 Created`:

```json
{
  "transaction": {
    "id": 12, "raw_text": "...", "total": 39000, "status": "completed",
    "occurred_at": "2026-11-26T08:00:00Z", "voided_at": null, "void_reason": null,
    "items": [
      { "id": 30, "line_no": 1, "product_id": 5, "product_name": "Nasi goreng",
        "unit_price": 15000, "quantity": 2, "line_total": 30000 }
    ]
  },
  "products_changed": [ { "id": 5, "name": "Nasi goreng", "stock": 8 } ],
  "products_deleted": [ 9 ]
}
```

- `transaction` is `null` when the batch had no sale. Its shape is the transaction object that the transaction endpoints reuse.
- `products_changed`: every product the batch touched (sold, restocked, adjusted or created) and that still exists, with its final stock, ordered by id. Use it to refresh the local stock.
- `products_deleted`: ids of existing products the batch deleted. A product created and deleted in the same batch appears in neither list.

Replay: if the user already has a transaction with this `client_uuid`, nothing is executed and the answer is `200 OK` with the stored transaction. `products_changed` then lists the products in that transaction's items that still exist, with their current stock (which may differ from the first answer), and `products_deleted` is `[]`. The ops in a replayed request are not compared with the stored ones. A concurrent duplicate is treated the same way.

Command-only batches are not retry-safe: a batch with no `sale` line stores no transaction, so a retry with the same `client_uuid` runs again (a repeated restock adds the stock twice). This is accepted for now because there is no offline mode (see `docs/note.md`).

Errors:

- `403 forbidden`: missing `transaction.create`, or a non-sale op without `product.manage`.
- `422 invalid_value` (with `details.field`): `ops` not 1 to 200 lines, `line_no` not unique, `raw_text` empty or too long.
- `422 lines_invalid`: one or more lines are wrong. Every failing line is reported at once, and nothing is saved:

```json
{ "error": { "code": "lines_invalid", "message": "Ada baris yang tidak valid.",
  "details": { "lines": [
    { "line_no": 2, "code": "stock_insufficient", "message": "Stok tidak cukup." },
    { "line_no": 3, "code": "product_not_found", "message": "Produk tidak ditemukan." }
  ] } } }
```

  Line codes: `invalid_quantity`, `invalid_price`, `invalid_name`, `invalid_value`, `product_not_found`, `name_taken`, `stock_insufficient`.
- `400 invalid_body`: malformed JSON, a missing field, or an unknown `op`.

#### Command grammar (client side)

One command per line, case-insensitive. The client checks the prefixes in this order and sends the matching op:

| Typed line | Op |
|---|---|
| `tambah stok <name> <qty>` | `restock` |
| `hapus stok <name> <qty>` | `adjust_down` |
| `buat produk <name> harga <price> stok <stock>` | `create_product` |
| `hapus <name>` | `delete_product` |
| `<name> <qty>` | `sale` |

Voiding a sale is not a command; it is a transaction endpoint.

## Transactions

Needs `transaction.read` (list, detail) or `transaction.void` (void), else `403 forbidden`. Every route only sees the caller's own transactions; another user's id is `404 not_found`. Transactions are created by `POST /catat` and are never deleted, only voided.

### GET /api/v1/transactions?date=&cursor=&limit=

One calendar day of the caller's transactions, newest first. Days are Asia/Jakarta (WIB, UTC+07:00): `date=2026-11-17` covers `2026-11-16T17:00:00Z` up to, not including, `2026-11-17T17:00:00Z`.

- `date`: `YYYY-MM-DD`, default today in WIB. A bad date is `422 invalid_value` with `details.field` `date`.
- `limit`: 1 to 100, default 20. Out-of-range values are clamped.
- `cursor`: the `next_cursor` of the previous page. It is opaque: pass it back unchanged with the same `date`. A bad cursor is `422 invalid_value` with `details.field` `cursor`.

`200 OK`

```json
{
  "items": [
    { "id": 12, "occurred_at": "2026-11-17T08:00:00Z", "total": 54000, "status": "completed",
      "item_count": 4, "summary": "Nasi goreng 2, Es teh manis 3, Kopi 1 +1 lainnya" }
  ],
  "next_cursor": "MTc5NDU1MDAwMDAwMDAwMDoxMg",
  "day": { "date": "2026-11-17", "transaction_count": 38, "revenue": 1250000 }
}
```

- Paging is keyset on `(occurred_at, id)` descending, so rows added or voided while paging never cause a duplicate. `next_cursor` is `null` on the last page.
- `day` counts completed sales only, for the whole day (not just this page). It is sent on the first page (no `cursor`) and is `null` on later pages.
- Voided transactions are listed with `status: "voided"`; they are not counted in `day`.
- `item_count` is the number of lines. `summary` names the first 3 lines in `line_no` order as "name quantity", joined by ", ", then " +N lainnya" when there are more.

### GET /api/v1/transactions/{id}

`200 OK` with the transaction object (the same shape as `transaction` in `POST /catat`): `id`, `raw_text`, `total`, `status` (`completed` or `voided`), `occurred_at`, `voided_at`, `void_reason` and `items[]`. Errors: `not_found` (404).

### POST /api/v1/transactions/{id}/void

Request body is optional: no body (or an empty one) means no reason. A body with content must be valid JSON, else `400 invalid_body`.

```json
{ "reason": "salah catat" }
```

- `reason` is optional, trimmed, and a blank value counts as none. At most 200 characters, else `422 invalid_value` with `details.field` `reason`.
- `200 OK` with the updated transaction (`status: "voided"`, `voided_at`, `void_reason`).
- Stock is restored: each item adds a `void_sale` stock movement for its product, unless the product has since been deleted.
- A sale can be voided at any time, with no window. Voiding an old sale changes the totals of its day and month in past analytics.
- Voiding is final; there is no un-void.

Errors: `not_found` (404, no such transaction for this user), `already_voided` (409), `invalid_value` (422), `forbidden` (403).

## Analytics

Needs `analytics.read`, else `403 forbidden`. Every route only sees the caller's own data and counts completed transactions only (voided ones are ignored everywhere). Days and months are Asia/Jakarta (WIB). Quantities and money are JSON integers (whole rupiah); percentages are numbers with one decimal.

Parameters:

- `month`: `YYYY-MM`, default the current WIB month. A bad format or a month after the current one is `422 invalid_value` with `details.field` `month`. A month before the first sale is allowed and comes back empty.
- `date` (path of the day route): `YYYY-MM-DD`. A bad date or a date after today (WIB) is `422 invalid_value` with `details.field` `date`.

Grouping and names: items are grouped by product when the product still exists, and show its current name (so a rename moves the old sales under the new name) and its current `stock`. Sales of a deleted product are grouped by the name saved on the sale, have `product_id: null` and `stock: null`. Items are ranked by quantity, then revenue.

### GET /api/v1/analytics/months

`[{ "month": "2026-11", "revenue": 18175000 }]`: only months with sales, newest first. A new user gets `[]`. Use it for the month picker limits.

### GET /api/v1/analytics/month?month=

```json
{
  "month": "2026-11", "through_day": 17,
  "revenue": 18175000, "transaction_count": 641,
  "previous": { "month": "2026-10", "revenue": 16800000, "change_pct": 8.2 },
  "trend": [ { "month": "2025-12", "revenue": 21400000 } ],
  "weekday_avg": [ { "weekday": 1, "avg_revenue": 887000 } ],
  "top_items": [ { "name": "Es teh manis", "qty": 512, "revenue": 2560000, "stock": 37 } ]
}
```

- `through_day` is today's day for the current month, otherwise the last day of the month. `revenue` and `transaction_count` cover days 1 to `through_day`.
- `previous` is the same day range of the previous month (clamped to its length). `change_pct` is `(revenue - previous) / previous * 100`, rounded half away from zero to one decimal, and `null` when the previous revenue is 0.
- `trend` has exactly 12 entries, oldest first, ending with `month` (which may be unfinished). Months without sales have `revenue: 0`. The design showed 6 bars, so the client must show 12.
- `weekday_avg` is `null` while the month has fewer than 14 days with sales. Otherwise it has 7 entries (`weekday` 1 = Monday to 7 = Sunday). Each average is over every calendar day from the 1st to `through_day`, and days without sales count as Rp0 (Mondays = revenue on all Mondays so far divided by the number of Mondays so far).
- `top_items`: the top 5 over days 1 to `through_day`.

### GET /api/v1/analytics/month/days?month=&cursor=&limit=

"Per hari". Days of the month that have sales (days 1 to `through_day`), newest first.

```json
{ "items": [ { "day": "2026-11-17", "transaction_count": 38, "revenue": 1250000 } ],
  "next_cursor": "MjAyNi0xMS0xNg" }
```

`limit` is 1 to 100, default 20 (clamped). `cursor` is the opaque `next_cursor` of the previous page; pass it back unchanged with the same `month`. It encodes the last day returned, so paging never repeats a day. A bad cursor is `422 invalid_value` with `details.field` `cursor`. `next_cursor` is `null` on the last page.

### GET /api/v1/analytics/days/{date}/items

A day row expanded.

```json
{ "items": [ { "product_id": 4, "name": "Nasi goreng", "qty": 30, "revenue": 450000 } ],
  "other_revenue": 120000, "total": 1250000 }
```

`items` are the top 3 by quantity, then revenue. `total` is the day's revenue and `other_revenue` is `total` minus the revenue of `items`. A day without sales gives `items: []` and zeros.

### GET /api/v1/analytics/month/items?month=&q=

Screen "Semua barang terjual".

```json
{ "total_qty": 2184, "revenue": 18175000,
  "items": [ { "product_id": 4, "name": "Es teh manis", "qty": 512, "share_pct": 23.4,
               "revenue": 2560000, "stock": 37 } ],
  "unsold": [ { "id": 9, "name": "Roti", "stock": 12 } ] }
```

- `items` are not paged. `share_pct` is `qty / total_qty * 100`, rounded half away from zero to one decimal (so the shares sum to about 100, not exactly).
- `unsold` is the user's current products with no completed sale in the month, by name.
- `q` filters both `items` and `unsold` by name: case-insensitive contains, with `%`, `_` and `\` matching literally. `total_qty`, `revenue` and `share_pct` stay whole-month figures whatever `q` is.
- There is no low-stock flag in v1 ("hampir habis" is dropped, see `docs/note.md`).

## Broadcasts

In-app announcements, no push. Broadcasts are global: every user reads the same feed, so nothing is scoped to the caller. There is no scheduler: a scheduled broadcast counts as sent once its time has passed, worked out when someone reads (the rows are never rewritten). `shown_at` is the sent time, or the scheduled time for a broadcast that became due on its own.

`category` is `update`, `berita`, `info` or `tips`.

### GET /api/v1/broadcasts

Needs `broadcast.read`. The latest 5 that count as sent, newest first.

```json
[ { "id": 3, "category": "info", "title": "Libur lebaran", "summary": "Layanan tetap jalan.",
    "has_body": true, "shown_at": "2026-11-27T03:00:00Z" } ]
```

### GET /api/v1/broadcasts/{id}

Needs `broadcast.read`. The same fields plus `body` (`null` if there is none). `404 not_found` unless it counts as sent (scheduled for later and cancelled ones are hidden).

### Broadcaster routes

`/broadcaster/broadcasts...` need `broadcast.create` (list, create, detail), `broadcast.update` (PATCH) or `broadcast.cancel` (cancel), else `403 forbidden`. Make a broadcaster with `cargo run -- promote <email>` (`demote` reverses it). Both bump the user's `token_version`, so the old token gets `401` and the user logs in again.

Any broadcaster may change or cancel any scheduled broadcast; there is no ownership check.

### GET /api/v1/broadcaster/broadcasts?cursor=&limit=

```json
{ "recipient_count": 120,
  "scheduled": [ { "id": 5, "category": "tips", "title": "...", "summary": "...", "has_body": false,
                   "shown_at": "2026-12-01T01:00:00Z" } ],
  "sent": { "items": [ { "id": 3, "...": "same fields" } ], "next_cursor": null } }
```

- `recipient_count` is the number of users with the `user` role.
- `scheduled` is every broadcast not yet due, soonest first (not paged). `sent` is a page of the ones that count as sent, newest first (`limit` 1 to 100, default 20; `cursor` opaque). Cancelled broadcasts are in neither list.

### POST /api/v1/broadcaster/broadcasts

```json
{ "category": "info", "title": "Libur lebaran", "summary": "Layanan tetap jalan.",
  "body": "Isi lengkap (optional)", "send_at": null }
```

- `title` is 1 to 60 characters and `summary` 1 to 120, after trimming. A blank `body` becomes `null`. Errors: `422 invalid_value` with `details.field`.
- `send_at: null` (or missing) sends now. An RFC 3339 time schedules it, and it must be in the future: otherwise `422 time_passed`. There is no upper limit.

`201 Created` with the detail object below.

### GET /api/v1/broadcaster/broadcasts/{id}

Any broadcast, including cancelled ones.

```json
{ "id": 5, "category": "tips", "title": "...", "summary": "...", "has_body": true, "body": "...",
  "shown_at": "2026-12-01T01:00:00Z", "effective_status": "scheduled",
  "created_at": "2026-11-27T03:00:00Z", "created_by_name": "Admin",
  "cancelled_at": null, "cancelled_by_name": null }
```

`effective_status` is `cancelled`, `sent` or `scheduled`, as worked out above. Errors: `not_found` (404).

### PATCH /api/v1/broadcaster/broadcasts/{id}

"Ubah". Any of `category`, `title`, `summary`, `body` (blank clears it) and `send_at`, with the same rules as create. `send_at` has three cases: missing keeps the schedule, a future time reschedules, and `null` sends it now. Other fields in the same request are applied too. An empty body is `422 nothing_to_update`. `200 OK` with the detail object.

Only a scheduled broadcast that is not yet due can change. Otherwise: `404 not_found` if it does not exist, or `409 not_editable` if it was already sent, cancelled or has just become due. To correct a sent broadcast, send a new one.

### POST /api/v1/broadcaster/broadcasts/{id}/cancel

"Batalkan". No body. Records who cancelled and when. `200 OK` with the detail object, with the same `404` and `409 not_editable` rules as PATCH.
