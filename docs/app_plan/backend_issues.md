# Backend issues found by the app

Append one entry per issue, newest at the bottom. Never fix the backend from an app branch. The user decides.

Template:
```
## <n>. <short title> (<YYYY-MM-DD>, branch <app branch>)
- Endpoint: `<METHOD> <path>`
- Request id: `<x-request-id>`
- Expected (docs/api.md): …
- Actual: status, body (no tokens or passwords), backend log line
- Workaround in app: none | …
- Status: open
```

## 1. Backend doesn't read the Google client id (2026-11-28, planning)
- Endpoint: `POST /api/v1/auth/google`
- Request id: n/a (found by reading config)
- Expected: `backend/src/config.rs:167` reads only `GOOGLE_CLIENT_IDS` (comma-separated), as in `backend/.env.example`. It must contain the token's `aud`.
- Actual: `backend/.env` has `GOOGLE_CLIENT_ID` (the Android client, for the app) and `BACKEND_GOOGLE_CLIENT_ID` (the web client), but no `GOOGLE_CLIENT_IDS`. The backend sees no client ids, so every Google token is rejected with `401 unauthorized`.
- Why the web id: on Android the app passes the **web** client id as `serverClientId`, and Google puts it in the id token's `aud`. The Android client id is never in the token; Google matches it by package name + SHA-1.
- Fix (user, pick one):
  - a) add `GOOGLE_CLIENT_IDS=<same value as BACKEND_GOOGLE_CLIENT_ID>` to `backend/.env` (no code change), or
  - b) a backend change so `config.rs` reads `BACKEND_GOOGLE_CLIENT_ID` (update `.env.example`, the config tests and the release env list).
- Workaround in app: none.
- Status: fixed 2026-11-28 with a): `GOOGLE_CLIENT_IDS` added to `backend/.env` with the web id, and `GOOGLE_SERVER_CLIENT_ID` added to `pensil_warung/.env` with the same value. The Android client's package and debug SHA-1 were checked and match. Restart the backend so it reads the new key.
