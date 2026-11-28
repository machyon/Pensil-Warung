# App conventions

## Run
```sh
cd backend && cargo run -- migrate && cargo run            # local API on :3000
cd pensil_warung
flutter run --dart-define-from-file=.env                    # emulator Medium_Phone (Google Play image)
flutter analyze && flutter test
```
`pensil_warung/.env` (never committed) holds:
- `API_BASE_URL=http://10.0.2.2:3000`
- `GOOGLE_CLIENT_ID=<Android client id>`: the user's existing key. It is reference only, because the Android client is matched by package name + SHA-1 and never passed in code.
- `GOOGLE_SERVER_CLIENT_ID=<web client id>`: the same value as `BACKEND_GOOGLE_CLIENT_ID` in `backend/.env`. It is passed to `google_sign_in` as `serverClientId`, so it becomes the token's `aud`.

Read them with `String.fromEnvironment` in `lib/config.dart` only.

## Layout
```
pensil_warung/lib/
  main.dart                 runApp, MultiProvider, MaterialApp.router
  config.dart               apiBaseUrl, googleClientId (dart-define)
  routing/router.dart       go_router: redirect by session + role, two StatefulShellRoutes
  data/
    api_client.dart         http wrapper: base URL, bearer, JSON, envelope → ApiException, logging
    api_exception.dart      ApiException {status, code, message, details, requestId}, NetworkException
    session.dart            Session (ChangeNotifier): token + user, flutter_secure_storage
    prefs.dart              shared_preferences: text size, tema, read broadcast ids
    repositories/<feature>_repository.dart
  domain/<model>.dart       immutable models with fromJson
  catat/                    pure Dart, no Flutter imports: parser.dart, matcher.dart, linter.dart
  ui/
    core/theme.dart         colour + type tokens (below), ThemeData
    core/format.dart        rupiah, compact rupiah, WIB dates
    core/widgets/           shared widgets (below)
    <feature>/<screen>_screen.dart, <screen>_view_model.dart
test/                       mirrors lib/
```

### `ui/core/widgets/`: write a widget here once, never copy it into a feature
| Widget | Used by |
|---|---|
| `AppHeader` | Big title, optional subtitle, bell (with unread dot) and avatar letter linking to Pengaturan |
| `BackHeader` | Back arrow + title for pushed screens |
| `MainNav` | Bottom nav: Produk / Catat / Histori (user), Siaran / Tulis / Akun (broadcaster). Selected = yellow pill |
| `PrimaryButton`, `SecondaryButton` | 56 px, radius 18, yellow `#FFC727` on `#2A2000` / white with `#D1D1D0` border; disabled `#DEDEDD` on `#7C7B79` |
| `LabeledField` | Label, 56 px field radius 16, helper/error text, optional show-password toggle |
| `AppCard` | White, `#E3E3E1` border, radius 24 |
| `AppSheet` | Bottom sheet / alert dialog style used by every confirm |
| `EmptyState` | Icon, title, text, action |
| `ProductAvatar` | Photo or initials (NG, ET) on `#EAE9E8` |
| `SegmentedTabs` | Histori / Analitik, Semua / Belum dibaca |
| `MonthStepper` | "Bulan November 2026" with prev/next, opens PilihBulan |
| `DayCard` | Expandable "Per hari" card (Histori and Analitik) |
| `ErrorView` | Network error ([30] layout) or `ApiException.message` with "Coba lagi" |

## Design tokens (`theme.dart`)
Colours: ink `#1B1B19`, paper `#F3F2F1`, surface `#FFFFFF`, border `#E3E3E1`, field border `#D1D1D0`, muted `#626260`, label `#4F4F4D`, faint `#8C8B89`, chip `#EAE9E8`, disabled `#DEDEDD`/`#7C7B79`, avatar `#3A3A38`, accent `#FFC727`, on-accent `#2A2000`, error `#B63325`, error bg `#F6E7E5`.
Type: Plus Jakarta Sans (400–800) for UI, Roboto Mono for the Catat box, via `google_fonts` (already in use by `splash_screen.dart`). Titles 30/800/-0.5, money hero 26–30/800.
Sizes: the design is 412 × 915. Touch targets ≥ 44 px.

## Rules
- **Screens are thin.** A screen reads its view model with `context.watch`, and calls its methods. No HTTP or parsing in widgets.
- **View models** hold one screen's state (`loading`, `error`, data) and call repositories. Use a `Command`-style `bool running` to disable buttons during a request, so a double tap never sends twice.
- **Repositories** are plain classes taking `ApiClient`, one per API area (`AuthRepository`, `ProductRepository`, `CatatRepository`, `TransactionRepository`, `AnalyticsRepository`, `BroadcastRepository`, `AccountRepository`). They return domain models and throw `ApiException`/`NetworkException`. No interfaces: there is one implementation.
- **Product cache.** `ProductRepository` keeps the last `GET /products` list in a `ChangeNotifier` (Catat's dictionary, photos for other screens). Refresh it after any save that returns `products_changed`/`products_deleted`, and after product CRUD.
- **Money** is `int` rupiah. Never `double`. `format.rupiah(15000)` → `Rp15.000` (`intl`, `id_ID`). Compact: `887rb`, `1,2jt`, `28,7jt`.
- **Time.** The API sends UTC. Show WIB with a fixed `+07:00` offset (no DST) via `format.wib(dt)`. Dates sent to the API (`date=`, `month=`) are WIB dates.
- **Idempotency.** `POST /catat` and `/revise` send a `client_uuid` (`uuid` v7), made once per Simpan and reused on a retry of the same Simpan.
- **UI text** is Indonesian, copied from the design. Code and identifiers are English.
- **Accessibility.** Keep the design's `aria-label`s as `Semantics`/`tooltip` labels.

## Errors and logging
- `ApiClient` turns every non-2xx into `ApiException` from the envelope `{"error":{code,message,details}}`, plus `x-request-id`. A socket/timeout error is `NetworkException`.
- Show `exception.message` (the server's Indonesian text) unless the screen handles that `code` itself (for example `lines_invalid`, `invalid_credentials`).
- `401 unauthorized` or `account_gone` on an authed call: clear the session and go to Landing.
- Log each request with `dart:developer` `log(name: 'api')`: method, path, status, `code`, `x-request-id`, duration. **Never** log tokens, passwords, `id_token`s or request bodies.
- **Backend fault** = a 5xx, a response that breaks `docs/api.md` (shape, status, code), or behaviour that contradicts it. When you find one:
  1. Find the backend log line with the same request id.
  2. Add an entry to `docs/app_plan/backend_issues.md` (template there).
  3. Tell the user. Work around it in the app only if that's harmless, and note the workaround in the entry.

## Packages
Present: `material_ui` (Material widgets, imported as `package:material_ui/material_ui.dart`, keep it), `flutter_svg`, `google_fonts`.
Add, only in the branch that first needs it: `provider`, `go_router`, `http`, `flutter_secure_storage`, `shared_preferences`, `intl`, `uuid` (01); `google_sign_in` (02); `image_picker`, `crop_your_image` (04); `package_info_plus` (10); dev only: `flutter_launcher_icons` (12). Nothing else without asking.

## Tests
- Unit tests for everything in `catat/` and `ui/core/format.dart`. These are the most important tests in the app.
- Widget tests per screen for the main states (loaded, empty, error, the key action) with `ApiClient` over `MockClient` returning bodies copied from `docs/api.md`.
- Every branch is also checked by hand on the emulator against the local backend. "Done when" lists those checks.
