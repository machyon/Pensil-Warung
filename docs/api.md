# Pensil Warung API

Reference for the HTTP API as it is built. It grows as branches merge. Only what exists in the code is listed here.

## Conventions

| Topic | Rule |
|---|---|
| Base path | `/api/v1`. The only route outside it is `GET /health` |
| Format | JSON only. Request bodies need `Content-Type: application/json` |
| Auth | Bearer token: `Authorization: Bearer <jwt>`. Not built yet, it comes with the auth branch |
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
- **SQL map**: mapped from a database error. No route writes data yet, so nothing returns it yet.
- **later**: defined for a later branch.

| Code | HTTP | Default message | Used | When |
|---|---|---|---|---|
| `invalid_body` | 400 | Isi permintaan tidak valid. | now | Malformed JSON, wrong shape, or missing JSON content type |
| `invalid_query` | 400 | Parameter permintaan tidak valid. | now | A query string value does not parse |
| `invalid_path` | 400 | Alamat permintaan tidak valid. | now | A path parameter does not parse |
| `invalid_value` | 422 | Nilai yang dimasukkan tidak valid. | SQL map | A field fails a rule. A database check failure (other than stock) gives 422. An unknown unique index gives 409 with this code |
| `invalid_name` | 422 | Nama yang dimasukkan tidak valid. | later | A name fails the name rules |
| `not_found` | 404 | Data tidak ditemukan. | now | Unknown route, or the record does not exist |
| `unauthorized` | 401 | Sesi Anda telah berakhir. Silakan masuk kembali. | later | Missing or invalid bearer token |
| `invalid_credentials` | 401 | Email atau kata sandi salah. | later | Wrong email or password at login |
| `forbidden` | 403 | Anda tidak memiliki akses untuk tindakan ini. | later | Signed in, but not allowed (for example, not a broadcaster) |
| `account_gone` | 401 | Akun tidak ditemukan. Silakan masuk kembali. | SQL map | The user no longer exists. A foreign key violation (SQLSTATE 23503) maps here |
| `email_taken` | 409 | Email sudah digunakan. | SQL map | Unique violation on `users.email` |
| `username_taken` | 409 | Username sudah digunakan. | SQL map | Unique violation on `users.username` |
| `name_taken` | 409 | Nama produk sudah digunakan. | SQL map | Unique violation on a product name for this user |
| `email_registered` | 409 | Email ini sudah terdaftar. Silakan masuk dengan kata sandi. | later | Google sign-in with an email that already has a password account |
| `google_account` | 403 | Akun ini masuk dengan Google, sehingga tidak dapat diubah di sini. | later | Password or email change on a Google-only account |
| `reauth_required` | 401 | Silakan verifikasi ulang akun Anda untuk melanjutkan. | later | A sensitive action needs a fresh sign-in, such as account deletion |
| `stock_insufficient` | 422 | Stok tidak cukup. | SQL map | A sale would take stock below zero |
| `not_editable` | 409 | Data ini tidak dapat diubah. | later | The record cannot be changed in its current state |
| `time_passed` | 422 | Waktu untuk tindakan ini sudah lewat. | later | The time window for an action has passed |
| `payload_too_large` | 413 | Ukuran berkas terlalu besar. | now | Body is over the limit. The message says "berkas" (file) even for JSON |
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
