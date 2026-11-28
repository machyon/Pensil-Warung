# Decisions (agreed 2026-11-28)

| Topic | Decision |
|---|---|
| Platform | Android only. Other platform folders stay but are not built or tested |
| Architecture | Flutter's official MVVM guide: `provider` + `ChangeNotifier` view models, concrete repositories, `go_router` |
| Data | The real API from the first commit, on a local `cargo run` backend (`http://10.0.2.2:3000` from the emulator). No fake repositories. Tests mock HTTP with `package:http/testing` `MockClient` |
| Dev database | Local Postgres 18: database `pensil_warung_dev`, role `pensil_dev` (URL in `backend/.env`). The Aiven URL is kept commented out there. **Never run the backend or `migrate` against Aiven from app work.** (On 2026-11-28 the branch 01 agent migrated Aiven to V4 by mistake, so V4 is frozen there now) |
| Backend faults | Log every failed request with its `x-request-id`. A backend fault goes into `docs/app_plan/backend_issues.md`, and the user is told. App branches never edit `backend/` |
| Google sign-in | In v1, and it's **tested first** (branch 02, commit 1) so the user can sort out OAuth setup early. Client id comes from `pensil_warung/.env` |
| Offline | No offline queue (the backend has no support). [30] `TanpaInternet` is built with only "Coba lagi" and new copy. [31] `CatatOffline` is dropped. Catat text stays in the box (in memory) when a save fails |
| Theme | Text size (Kecil/Sedang/Besar) works through a `TextScaler`. The Tema row stays and saves the choice on the phone, but the app stays light until a dark design exists |
| Day list | A new screen, not in the design: one day's transactions (GET `/transactions?date=`), opened from "Lihat N transaksi" and from [13] `PilihTanggal`. A row opens [15] `TransaksiDetail` |
| Confirm sheet | [12] `CatatKonfirmasi` appears only when the batch has a command line (create, set price, restock, adjust down, delete). A sales-only Simpan saves straight away and shows [14] `CatatTersimpan` |
| Command grammar | The API grammar (`docs/api.md`, "Command grammar"). The design's `baru …`, `harga …` and `buang …` are placeholders: their hint and example text is rewritten to `buat produk kerupuk harga 2000 stok 30`, `ubah harga …` and `hapus stok … alasan …` |
| Email change | Immediate, with the password (`PATCH /me/email`). [10c] `VerifikasiEmail` is dropped. The returned token is swapped in |
| Design leftovers | "Ubah zona waktu di Akun" removed (WIB is fixed). "hampir habis" removed (no low stock in v1). Trend shows 12 bars, not 6. Username rule text says 3–30 characters (the API rule) with no live availability check |

## Planner's calls (change any you disagree with)
These fill gaps the design leaves open. They were not asked about one by one.

| Topic | Call |
|---|---|
| Password rules [10d] | Show and check only "Minimal 8 karakter" and that the repeat matches. "Ada huruf dan angka" and "Beda dari kata sandi lama" are dropped (the backend doesn't enforce them) |
| Urungkan [14] | Shown only after a sales-only save, and it voids that sale. After a batch with commands there is no Urungkan, because the commands can't be undone |
| Photo before save | [03] and Catat's command mode let you pick a photo per new row. It is kept on the phone and uploaded after the save returns the product id |
| Add item in revise [16] | "Tambah barang ke transaksi" opens a bottom sheet with a searchable product list (not drawn in the design) |
| Notification body | Tapping a notification opens a bottom sheet with its `body` (not drawn). Opening marks it read |
| Tentang [10f] | Version from `package_info_plus`. "Lisensi sumber terbuka" opens Flutter's `showLicensePage`. "Cek pembaruan" and "Beri nilai" are hidden until there is a Play Store listing |
| Legal [10g] | Built with the design's sections filled with lorem ipsum. The real text is written later (by AI, after the frontend is done). "Buka di browser" is hidden until a URL exists |
| Hapus akun, Google-only | The password field is replaced by "Masuk ulang dengan Google", which gets a fresh `id_token` |
| Analytics gates | Follow [34] `AnalitikKosong`: weekday chart after 14 days with sales (API sends `null`), top items after 7 days (client gate), "Dibanding bulan lalu" when `previous.change_pct` is not null |

## Answered 2026-11-28
| Topic | Decision |
|---|---|
| Legal text | Lorem ipsum for now. Real Syarat & Ketentuan and Kebijakan Privasi are written by AI after the frontend is finished |
| Seed data | `pensil_warung/tool/seed_local.sql` (branch 07), run with `psql` against the **local** DB only. It refuses any non-loopback server. Inserts only (never `UPDATE products.stock`). Details in `branches/07-app-history.md` |
| App id | `com.machyons.pensil_warung`, already set in `android/app/build.gradle.kts`. Don't change it |
| Launcher icon | The design's logo, `assets/images/logo_pensil_warung.svg` (branch 12) |
| Production API URL | Not decided. The app must work with any https base URL given through `API_BASE_URL`: no hard-coded host, cleartext only in debug, and every URL (including photo URLs) taken from the API or the base URL |

## Open questions
- Production API URL (Render), needed only at release.
