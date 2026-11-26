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
| `invalid_value` | 422 | Nilai yang dimasukkan tidak valid. | now | A field fails a rule (email format, username format, password length, field too long, missing `current_password`, negative price or stock, `note` without `stock`, bulk size). A database check failure (other than stock) gives 422. An unknown unique index gives 409 with this code |
| `invalid_name` | 422 | Nama yang dimasukkan tidak valid. | now | `PATCH /me/display-name`: empty after cleaning, or over 50 characters. Products: name empty or over 60 characters |
| `not_found` | 404 | Data tidak ditemukan. | now | Unknown route, or the record does not exist |
| `unauthorized` | 401 | Sesi Anda telah berakhir. Silakan masuk kembali. | now | Missing or invalid bearer token. `POST /auth/google` also returns it for a bad Google ID token, with the message "Token Google tidak valid." |
| `invalid_credentials` | 401 | Email atau kata sandi salah. | now | Wrong email or password at login. Also a wrong `current_password` on the `/me` routes (message "Kata sandi saat ini salah.") |
| `forbidden` | 403 | Anda tidak memiliki akses untuk tindakan ini. | now | Signed in, but the role lacks the permission (all `/products` routes need `product.manage`) |
| `account_gone` | 401 | Akun tidak ditemukan. Silakan masuk kembali. | now | The user no longer exists. A foreign key violation (SQLSTATE 23503) maps here |
| `email_taken` | 409 | Email sudah digunakan. | now | Unique violation on `users.email` (register or `PATCH /me/email` with an existing email) |
| `username_taken` | 409 | Username sudah digunakan. | now | Unique violation on `users.username` (`PATCH /me/username`). Register and Google sign-up retry once before this can surface |
| `name_taken` | 409 | Nama produk sudah digunakan. | now | Unique violation on a product name for this user (create, bulk, rename). Bulk adds `details.index` |
| `email_registered` | 409 | Email ini sudah terdaftar. Silakan masuk dengan kata sandi. | now | Google sign-in with an email that already has a password account |
| `google_account` | 403 | Akun ini masuk dengan Google, sehingga tidak dapat diubah di sini. | now | Email or password change on a Google-only account |
| `reauth_required` | 401 | Silakan verifikasi ulang akun Anda untuk melanjutkan. | now | `DELETE /me` for a Google-only account without a fresh matching Google ID token |
| `stock_insufficient` | 422 | Stok tidak cukup. | SQL map | A stock movement would take stock below zero. Not reachable from `/products` (PATCH sets an absolute stock >= 0), reserved for Catat |
| `nothing_to_update` | 422 | Tidak ada data yang diubah. | now | `PATCH /products/{id}` with no fields |
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
