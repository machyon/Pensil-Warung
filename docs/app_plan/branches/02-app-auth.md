# 02 · `feature/app-auth`

**Goal:** sign up and sign in with email or Google. **Google comes first** and is tested with the user before the rest of the branch.

Screens: [00] `AppLanding`, [00] `Login`, [00] `LoginSalah` (the error state of Login), [01] `AppDaftar`.

## Before starting
- `backend_issues.md` #1 must be resolved: the backend has to accept the **web** client id (`BACKEND_GOOGLE_CLIENT_ID`) as `aud`. Ask the user to confirm this first.
- `pensil_warung/.env` must have `GOOGLE_SERVER_CLIENT_ID` = that web client id (see `conventions.md`).
- The Google Cloud **Android** OAuth client (the app's `GOOGLE_CLIENT_ID`) must have package `com.machyons.pensil_warung` and the debug keystore SHA-1 (`cd android && ./gradlew signingReport`). If it doesn't match, the sign-in fails on the phone with `DEVELOPER_ERROR` (code 10) before any request is sent: that's a Google Cloud config issue, not a backend one.
- The emulator must be signed in to a Google account (the `Medium_Phone` image has Play services).

## Endpoints
| Method | Path | Body | Screen |
|---|---|---|---|
| POST | `/api/v1/auth/google` | `{id_token}` | "Masuk dengan Google", "Daftar dengan Google". `200` existing, `201` new |
| POST | `/api/v1/auth/login` | `{email, password}` | Masuk |
| POST | `/api/v1/auth/register` | `{display_name, email, password}` | Daftar ("Nama" is `display_name`) |

## Rules
- Google: `google_sign_in` (v7: `GoogleSignIn.instance.initialize(serverClientId: config.googleServerClientId)`, then `authenticate()`, then `authentication.idToken`). A user cancel is silent. Any other failure is logged with the plugin's error code (no token) and shows "Gagal masuk dengan Google. Coba lagi."
- `409 email_registered` → "Email ini sudah terdaftar dengan kata sandi. Masuk pakai email dan kata sandi." (or the server `message`).
- Login `401 invalid_credentials` → the [00] `LoginSalah` state: red 2 px border on the password field and the alert "Email atau kata sandi salah". Typing clears it.
- Register: client checks match the API (email not blank, password 8–128, name not blank) before sending. `409 email_taken` and `422 invalid_value` show under the field in `details.field`.
- After any success, `session.signIn(token, user)`. The router then picks the shell by role. A brand-new user with no products lands on Catat, which shows [02] (branch 06).
- Show/hide password toggle with the aria labels "Tampilkan password" / "Sembunyikan password".
- Landing's example card (text → transaction) is static artwork.

## Commits
1. `feat(app-auth): Google sign-in against POST /auth/google`. **Stop here and test with the user** (see Done when, first item). Log any failure in `backend_issues.md` if it's backend side.
2. `feat(app-auth): Landing screen`
3. `feat(app-auth): Masuk with wrong-password state`
4. `feat(app-auth): Daftar`
5. `test(app-auth): login error state, register field errors, google cancel, session set on success`

## Done when
- **Google first:** on the emulator, "Masuk dengan Google" on a new Google account gives `201` and opens Catat. Signing out and in again gives `200`. The request ids are in the log. The user has seen this work, or the failure is written up.
- Email register → Catat. Wrong password → the red state. Right password → Catat.
- A broadcaster account (`cargo run -- promote <email>`, then sign in again) lands on the Siaran placeholder.
