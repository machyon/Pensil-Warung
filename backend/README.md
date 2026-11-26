# Pensil Warung backend: local setup

Rust API (Axum, tokio-postgres, deadpool). Run every command below from the `backend/` directory.

## Prerequisites

- Rust stable, edition 2024 (Rust 1.85 or newer).
- PostgreSQL 18. The schema uses `uuidv7()`, which needs 18 or newer.

## Configuration

Copy the example file and edit it:

```sh
cp .env.example .env
```

`.env` is git-ignored. Never commit it or real credentials.

| Key | Default | Meaning |
|---|---|---|
| `PORT` | `3000` | HTTP port |
| `APP_ENV` | `development` | `development` or `production`. Production refuses to start without a valid `JWT_SECRET` |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn` or `error`. `RUST_LOG` overrides it if set |
| `DATABASE_URL` | none (required) | PostgreSQL connection string |
| `DATABASE_CA_CERT` | empty | CA certificate as PEM text. Used first if set |
| `DATABASE_CA_CERT_FILE` | empty | Path to a CA certificate file, used when `DATABASE_CA_CERT` is empty. Resolved from the current directory, so run from `backend/` |
| `DATABASE_POOL_MAX` | `5` | Maximum pooled connections (at least 1) |
| `JWT_SECRET` | empty | Signing key, at least 32 characters. Required in production. In development a random key is made when unset, so tokens stop working on restart |
| `JWT_EXPIRES_IN` | `7d` | Token lifetime: a number and a unit (`s`, `m`, `h`, `d`) |
| `GOOGLE_CLIENT_IDS` | empty | Comma-separated Google client ids (Android, iOS, web). Optional |
| `AWS_ENDPOINT_URL_S3` | empty | Tigris endpoint, for example `https://t3.storage.dev` |
| `AWS_REGION` | `auto` | Region for the S3 client |
| `AWS_ACCESS_KEY_ID` | empty | Tigris access key |
| `AWS_SECRET_ACCESS_KEY` | empty | Tigris secret key |
| `TIGRIS_BUCKET` | empty | Bucket name |
| `IMAGE_URL_TTL_SECONDS` | `3600` | Lifetime of presigned image URLs, 1 to 604800 |
| `TEST_DATABASE_URL` | empty | Server used by `cargo test`. See Tests |

Storage is used only when `TIGRIS_BUCKET`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are all set. Leave them empty until image upload is used.

**Warning about `.env`:** the app always reads `.env` (from the current directory upward). It never overrides a variable that is already set in your shell. If `DATABASE_URL` is not exported in your shell, the value in `.env` is used, and it may point at the Aiven database. Check the value before running `migrate` or `serve`.

Remote database hosts always use TLS, even if the URL has no `sslmode`. Plain TCP is used only for `localhost`, `127.0.0.1` and `::1`.

## Migrations

Migrations are SQL files in `backend/migrations/`, named `V<n>__name.sql`. They are embedded in the binary by refinery.

```sh
cargo run -- migrate
```

- Applies every migration that is not yet recorded. Running it again does nothing and prints "database already up to date".
- Each migration runs in its own transaction.
- Applied versions are recorded in the `refinery_schema_history` table.
- Once a migration has been applied to a shared database, never edit it. Add a new file with the next number, for example `V2__add_something.sql`.
- `build.rs` tells Cargo to rebuild when `migrations/` changes, so a new file is picked up on the next build.

## Run the server

```sh
cargo run          # same as: cargo run -- serve
```

Listens on `PORT` (default 3000). Check it with:

```sh
curl localhost:3000/health
curl localhost:3000/api/v1/health/db
```

`/health` does not touch the database. `/api/v1/health/db` returns 503 if the database cannot be reached.

## Tests

```sh
TEST_DATABASE_URL=postgres://postgres@localhost:5432/postgres cargo test
```

- Integration tests (everything in `tests/`) need `TEST_DATABASE_URL`. It must be a full URL with a database name. The harness replaces that name.
- The role must be able to create databases (`CREATEDB`).
- Each test creates its own database `pw_test_<uuid>`, runs the migrations on it, and drops it when the test ends, even if the test fails.
- The harness does not read `.env`. It builds its config from fixed values, so real credentials are never used.
- Unit tests in `src/` do not need a database.

Full check, the same as CI:

```sh
cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
```

## CI

`.github/workflows/backend.yml` runs on pushes and pull requests to `develop` and `main` that touch `backend/**` or the workflow file. It starts a `postgres:18` service and runs, in `backend/`:

1. `cargo fmt --check`
2. `cargo clippy --all-targets -- -D warnings`
3. `cargo test`, with `TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres`

CI does not run `migrate` or `serve`.
