# 01 · `chore/app-foundation`

**Goal:** the Flutter project is in git, talks to the local backend, and has the theme, shared widgets, session and router that every later branch builds on.

Screens: [00c] `SplashRuang` (already built as `lib/splash_screen.dart`, keep it).

## Endpoints
| Method | Path | Use |
|---|---|---|
| GET | `/health` | Splash pings it while it shows (also wakes a sleeping Render instance later) |
| GET | `/api/v1/me` | Splash: if a token is stored, load the user. `401`/`account_gone` → clear it |

## Rules
- `pensil_warung/` is untracked today. **Before the first `git add`**, add `.env` and `.env.*` to `pensil_warung/.gitignore`, and check `git status` shows no `.env`.
- Delete the counter demo (`MyHomePage`) and its test.
- `config.dart`: `apiBaseUrl` (`API_BASE_URL`) and `googleServerClientId` (`GOOGLE_SERVER_CLIENT_ID`, the web client id) from `String.fromEnvironment`. Throw at startup in debug if `apiBaseUrl` is empty, with the hint to pass `--dart-define-from-file=.env`.
- Android: `INTERNET` permission in the main manifest. Cleartext HTTP only in debug (`android/app/src/debug/AndroidManifest.xml` `usesCleartextTraffic="true"`), so `http://10.0.2.2:3000` works.
- **Ready for any production URL:** every request URL is `apiBaseUrl` + a path starting with `/api/v1` or `/health`, so a trailing slash in `API_BASE_URL` is trimmed once in `config.dart`. In release builds an `http://` base URL is a startup error. No host appears anywhere else in the code. Photo URLs are used as the API sends them.
- `ApiClient` (`http`): `get/post/patch/put/delete` + `multipart`, JSON in and out, `Authorization: Bearer` from `Session`, a 20 s timeout, envelope → `ApiException`, socket/timeout → `NetworkException`, the logging rule from `conventions.md`.
- `Session` (`ChangeNotifier`): `token`, `User` (`id, display_name, username, email, role, permissions, has_password`), `signIn(token, user)`, `replaceToken(token, user)`, `signOut()`. The token is kept in `flutter_secure_storage`.
- Router (`go_router`), with `refreshListenable: session`:
  - No session → `/welcome` (Landing, built in 02).
  - `role == user` → shell with tabs `/produk`, `/catat` (initial), `/histori`.
  - `role == broadcaster` → shell with tabs `/siaran`, `/tulis`, `/akun`.
  - Tabs are a `StatefulShellRoute.indexedStack` so each tab keeps its state (Catat text must survive a tab switch).
  - Placeholder screens for each tab until their branch lands.
- Splash shows at least as long as its intro animation (1 s), then routes. Drop the fixed 3 s timer.
- Theme and widgets from `conventions.md` (tokens, `ui/core/widgets/`), plus `format.dart` (`rupiah`, `rupiahCompact`, `wib`, `wibDate`, Indonesian day and month names).
- `MainNav` and `AppHeader` match [04] `AppCatat`: nav 64 px, white with top border, selected tab a yellow pill with weight 800.

## Commits
1. `chore(app): track the Flutter project, ignore .env`
2. `chore(app): config from dart-define, Android internet and debug cleartext`
3. `feat(app): ApiClient, ApiException, request logging`
4. `feat(app): Session with secure token storage`
5. `feat(app): theme tokens, format helpers, shared widgets`
6. `feat(app): go_router with user and broadcaster shells, splash routing`
7. `test(app): format helpers, ApiClient envelope and 401 handling, router redirects`

## Done when
- `flutter analyze` and `flutter test` pass.
- On the emulator with the local backend running, the splash goes to the placeholder Landing, and the log shows `[api] GET /health 200 <request-id>`.
- With the backend stopped, the splash shows `ErrorView` with "Coba lagi", and the backend comes back when you tap it.
