# 06 · `feature/app-catat`

**Goal:** the Catat tab: type sales and commands, see Hasil baca live, Simpan as one batch.

Screens: [04] `AppCatat`, [05] `AppCatatIsi`, [13] `CatatLinter`, [12] `CatatKonfirmasi`, [14] `CatatTersimpan`, [02] `AppCatatTanpaProduk`, [30] `TanpaInternet`. Dropped: [31] `CatatOffline`.

## Endpoints
| Method | Path | Use |
|---|---|---|
| GET | `/api/v1/products` | The dictionary (from the product cache, branch 03) |
| POST | `/api/v1/catat` | Simpan `{client_uuid, raw_text, ops}` |
| GET | `/api/v1/transactions?date=<today>&limit=1` | [14] "Hari ini: N transaksi · RpX" from `day` |
| POST | `/api/v1/transactions/{id}/void` | [14] "Urungkan" |

## Rules
- Header: "Catat" and today in WIB ("Selasa, 17 Nov 2026"). Bell and avatar from `AppHeader`.
- The box: Roboto Mono 17/32, line numbers, a red number and wavy underline on error lines ([05]). The drag handle resizes it between 168 and 480 px (also ArrowUp/ArrowDown by 32). Placeholder "Tulis jualan di sini".
- Hasil baca: run `lint()` from branch 05 on every change (debounce 150 ms). The header says "Hasil baca · N perlu dicek" or "Hasil baca · N salah · M peringatan". Fix buttons apply `Fix.apply` to the text.
- Bottom bar: "Total" / "Total jualan" with `rupiah(total)`, and Simpan. With errors, Simpan is disabled, the bar says "Betulkan N baris dulu", and "Ke baris N" scrolls to the first error ([13]).
- **Simpan:** a new `client_uuid` per attempt that has new text. If `needsConfirm`, show [12] first ("Periksa lagi" / "Simpan semua"). Otherwise save straight away.
- **Success (201/200):** apply `products_changed`/`products_deleted` to the cache, clear the box, upload pending photos (branch 04), and show [14]: the "Baru saja disimpan" card (time, item count, total, summary, "Lihat atau ubah" → [15] from branch 07, a no-op link until then) and "Hari ini …". A sales-only batch also gets the snackbar "Tersimpan · RpX [Urungkan]" (decisions, planner's calls). Urungkan voids the sale and puts the text back in the box.
- **422 `lines_invalid`:** `mapServerLines`, then show the errors in Hasil baca. Keep the text.
- **NetworkException:** keep the text and the same `client_uuid`, and show [30] as a full-screen route with "Coba lagi" (retries the same request). New copy: "Tidak ada internet" / "Tulisanmu di Catat masih ada. Sambungkan internet lalu coba lagi." plus the 3 tips. No "Tetap catat jualan".
- **[02] no products** (cache empty): the box is disabled with "Tambah barang dulu supaya bisa dicatat", the card "Belum ada barang" with "Tambah barang" (→ [03]) and "Ketik perintah". Ketik perintah enables the box with the hint "Satu barang per baris: **buat produk nama harga 2000 stok 30**". Hasil baca then lists new products with a photo button per row. The bar shows "Barang baru N". A batch of only `buat produk` lines still goes through [12].
- The box text lives in the Catat view model, so it survives tab switches. Branch 10 reads its unsaved line count for the Keluar sheet.

## Commits
1. `feat(app-catat): CatatRepository`
2. `feat(app-catat): editor with line numbers, error marks and resize handle`
3. `feat(app-catat): live Hasil baca with fixes and save bar`
4. `feat(app-catat): Simpan, confirm sheet for commands, server line errors`
5. `feat(app-catat): Baru tersimpan card, today summary, Urungkan`
6. `feat(app-catat): no-products state with command mode`
7. `feat(app-catat): no-internet screen with retry on the same client_uuid`
8. `test(app-catat): save sales-only skips confirm, commands show confirm, lines_invalid mapping, retry reuses client_uuid, urungkan voids`

## Done when
- New account: Ketik perintah, `buat produk nasi goreng harga 15000 stok 20`, Simpan → confirm → saved, and Produk shows it.
- `nasi goreng 2` + `es teh manus 3` (with Es teh manis existing) shows the fix, and after tapping it Simpan saves without a sheet, with the correct stock in Produk.
- A sale over stock shows "Stok cuma …", and both fixes work.
- Backend stopped during Simpan → [30]. Start the backend, tap Coba lagi → saved once (check that the transaction count went up by one only).
