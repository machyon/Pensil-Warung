# 10 · `feature/app-settings`

**Goal:** Pengaturan: account changes, display preferences, about, legal, sign out, delete account.

Screens: [10] `Pengaturan`, [10a] `UbahUsername`, [10b] `UbahEmail`, [10d] `UbahSandi`, [10e] `KeluarKonfirmasi`, [10f] `Tentang`, [10g] `Legal`, [10h] `HapusAkun`, [10i] `HapusAkunKonfirmasi`. Dropped: [10c] `VerifikasiEmail`.

## Endpoints
| Method | Path | Use |
|---|---|---|
| GET | `/api/v1/me` | Refresh on open |
| PATCH | `/api/v1/me/username` | [10a] |
| PATCH | `/api/v1/me/email` | [10b] `{email, current_password}` → `{token, user}` |
| PUT | `/api/v1/me/password` | [10d] `{current_password, new_password}` → `{token, user}` |
| DELETE | `/api/v1/me` | [10h] `{current_password}` or `{id_token}` |

## Rules
- Opened from the avatar in any `AppHeader` (user) or the Akun tab (broadcaster, branch 11 reuses these screens).
- Profile card: avatar letter, username, email.
- Google-only users (`has_password == false`): hide the Kata sandi row, and the Email row shows the email without a link (the API answers `google_account`).
- [10a]: "Sekarang", "Username baru", rule text "3 sampai 30 karakter. Huruf kecil, angka, dan garis bawah. Tanpa spasi." with the client regex `^[a-z0-9_]{3,30}$`. `409 username_taken` → "Username sudah dipakai". No live availability check.
- [10b]: email + password, "Simpan" (not "Kirim kode"), and drop the code paragraph. On `200`, `session.replaceToken`.
- [10d]: current, new, repeat. Checks "Minimal 8 karakter" and "Sama dengan kata sandi baru" (planner's call). Keep "Setelah diganti, HP lain yang masuk dengan akun ini akan keluar otomatis." On `200`, `session.replaceToken`. `401 invalid_credentials` → under the current-password field.
- Tampilan: Tema (Terang / Gelap / Ikuti HP) is saved in prefs and **has no effect** (decisions). Ukuran tulisan Kecil / Sedang / Besar → `TextScaler` 0.9 / 1.0 / 1.2 for the whole app, saved in prefs.
- [10e] Keluar: "2 baris di Catat belum disimpan" comes from the Catat view model (hidden when 0). Keluar → `session.signOut()` (and `GoogleSignIn.instance.signOut()`).
- [10f] Tentang: version from `package_info_plus`, "Lisensi sumber terbuka" → `showLicensePage`. Hide "Cek pembaruan" and "Beri nilai aplikasi". Footer "Pensil Warung · <current year>".
- [10g] Legal: the design's placeholder layout, one screen with a `title` parameter for "Syarat & Ketentuan" and "Kebijakan Privasi". Content is lorem ipsum in a const for each document (`ui/settings/legal_text.dart`), to be replaced by the real text after the frontend is done. Keep "Berlaku sejak [TANGGAL]" as lorem too.
- [10h] Hapus akun: the list "Yang ikut terhapus" (product count from the cache), the password field, and the checkbox, which must be ticked first. Google-only: the field is replaced by "Masuk ulang dengan Google" (a fresh `id_token`, sent within 5 minutes). [10i] confirms. On `204`, sign out and go to Landing. Errors: `invalid_credentials`, `reauth_required` → "Masuk ulang dengan Google dulu."
- Fix the typo in [10i] ("mengapus" → "menghapus"), and drop the redundant second sentence.

## Commits
1. `feat(app-settings): AccountRepository and Pengaturan`
2. `feat(app-settings): Ubah username`
3. `feat(app-settings): Ubah email and kata sandi with token swap`
4. `feat(app-settings): text size and saved tema`
5. `feat(app-settings): Keluar, Tentang, Legal`
6. `feat(app-settings): Hapus akun with password or Google re-auth`
7. `test(app-settings): token swap keeps session, google-only rows hidden, text scale applied, delete needs checkbox`

## Done when
- Change the password, and this phone stays signed in. Signing in with the old password then fails.
- Text size Besar scales every screen without overflow on the 412 × 915 emulator.
- Delete a password account and a Google-only account, and both return to Landing.
