# 12 · Release `app-v0.1.0`

Needs the backend release (`docs/backend_plan/branches/10-release.md`) first, for the production URL.

1. Get the production API URL from the user (the only open question). The legal text is replaced in its own later step, not here.
2. App id stays `com.machyons.pensil_warung` (already set). Change the manifest `android:label` from `pensil_warung` to "Pensil Warung".
3. Launcher icon from the design logo: `rsvg-convert -w 1024 -h 1024 assets/images/logo_pensil_warung.svg -o assets/images/launcher_icon.png` (plus a foreground version with ~20 % padding for the adaptive icon). Generate the mipmaps with `flutter_launcher_icons` (a dev dependency only), with adaptive background `#F3F2F1`. Check it on the emulator's home screen and in the round mask.
4. Release signing: an upload keystore kept outside the repo, `key.properties` ignored by git.
5. Google: add the release SHA-1 (and the Play app-signing SHA-1) to the Android OAuth client.
6. `.env.production` (ignored) with the Render `API_BASE_URL` (https). Build `flutter build appbundle --dart-define-from-file=.env.production`.
7. Check the Render cold start: the splash keeps waiting on `/health` (up to ~60 s) with its dots, then shows `ErrorView`.
8. Smoke test the release build on the emulator against production: Google sign-in, a Catat save, Histori, a broadcast.
9. PR `develop` → `main`, tag `app-v0.1.0`.
