# 07 · `feature/app-history`

**Goal:** the Histori tab and everything about one transaction: month summary, per-day cards, a day's list, detail, edit (revise) and cancel (void).

Screens: [06] `HistKartuPanah`, [33] `HistoriKosong`, [14] `PilihBulan` (sheet), [13] `PilihTanggal` (sheet), **new: Day list**, [15] `TransaksiDetail`, [16] `TransaksiUbah`, [17] `TransaksiBatal` (sheet).

## Endpoints
| Method | Path | Use |
|---|---|---|
| GET | `/api/v1/analytics/months` | Empty check ([33] when `[]`), and the limits for PilihBulan |
| GET | `/api/v1/analytics/month?month=` | "Penjualan bulan ini" (revenue, transaction_count, through_day), Terlaris top 3 |
| GET | `/api/v1/analytics/month/days?month=&cursor=` | "Per hari" cards, "Lihat semua N hari" loads more |
| GET | `/api/v1/analytics/days/{date}/items` | A day card expanded (top 3 + "Barang lain" + Total) |
| GET | `/api/v1/transactions?date=&cursor=` | Day list |
| GET | `/api/v1/transactions/{id}` | Detail |
| POST | `/api/v1/transactions/{id}/revise` | Ubah `{client_uuid, items:[{item_id,quantity}|{product_id,quantity}]}` |
| POST | `/api/v1/transactions/{id}/void` | Batalkan (no body) |

## Rules
- `SegmentedTabs` Histori / Analitik at the top. Analitik is branch 08 (a placeholder until then).
- `MonthStepper` at the bottom ("Bulan November 2026", prev/next). Next is disabled for the current month, prev for the first month in `/analytics/months`. Tapping it opens PilihBulan: a year switcher and a 12-month grid, months outside the range disabled and struck through, with the note "Catatan dimulai <first month>. Bulan yang belum lewat belum bisa dipilih."
- Summary subtitle: "641 transaksi · s.d. 17 Nov" (`through_day`).
- Day cards (`DayCard`, shared with 08): "Hari ini" / "Sen, 16 Nov", "N transaksi", revenue. Only one is expanded at a time, and items load on expand. The expanded card ends with "Lihat N transaksi" → Day list.
- **Day list (new, not in the design):** `BackHeader` with the long date and a calendar button that opens PilihTanggal (a month grid, days with no sales or in the future disabled, the selected day's sales shown under the grid). Header card from `day` (count, revenue). Rows: WIB time, `summary`, `total`, and a "Dibatalkan" tag + struck-through total for `voided`. Paged with `next_cursor`. Tap → Detail.
- Detail [15]: items (avatar, name, `qty × unit_price`, line total), Total, "Ditulis di Catat" `raw_text`, "Dicatat oleh <username>", "Riwayat ubahan" from `history[]` ("Belum pernah diubah" when empty; otherwise each older version with `revised_at`, total and items). A voided row shows "Dibatalkan" and hides both actions. A replaced row (`replaced_by_id` set) links to its newer version.
- Ubah [16]: a stepper per item (min 1), a delete per item, "Tambah barang ke transaksi" (a product picker sheet, planner's call). The impact box shows the old total struck through, the new total, and "Stok Nasi goreng kembali 1 (18 jadi 19) …" from the cached stock. "Simpan perubahan" is disabled until something changes. Send kept items as `item_id` and added ones as `product_id`. `lines_invalid` marks rows by `line_no` = index + 1. On `201`, replace the detail with the new transaction and refresh the product cache.
- Batalkan [17]: "Jualan hari ini" before → after (day revenue − total), "Stok <name> kembali +qty" for items whose product still exists, and the note "Tetap terlihat di Histori dengan tanda Dibatalkan, tapi tidak dihitung lagi." "Ya, batalkan" → void → back to the Day list, refreshed. `409 already_voided` → reload detail.
- [33] empty: "Belum ada jualan" + "Catat jualan pertama" → Catat.
- Wire [14] "Lihat atau ubah" (branch 06) to Detail.

## Local seed script (`pensil_warung/tool/seed_local.sql`)
Gives a real account months of history so Histori, the pickers and Analitik (branch 08) can be checked by hand.
- Run: register in the app first, then `psql "$LOCAL_DATABASE_URL" -v email=you@example.com -f tool/seed_local.sql`.
- **Guards (fail before writing):** `inet_server_addr()` must be null (socket) or loopback, so it can't touch Aiven. The user must exist. The user must have no transaction before today ("already seeded").
- One transaction for the whole script. Inserts only, following `docs/database.md`: products are inserted with their stock (the trigger writes the `initial` movement), restocks are `stock_movements` rows, sales are a `transactions` row and then its `transaction_items` (the trigger takes the stock). Never `UPDATE products.stock`.
- Data (deterministic, `setseed(0.42)`):
  - The design's 12 products with its prices: Es teh manis 5000, Nasi goreng 15000, Kopi susu 6000, Gorengan 2000, Mie goreng 12000, Es jeruk 6000, Nasi telur 10000, Air mineral 4000, Indomie rebus 8000, Ayam goreng 18000, Teh hangat 5000, and Teh botol 5000 (never sold, for "Belum terjual").
  - Restocks large enough that no sale fails, spread over time so Riwayat stok has entries, plus a few `adjustment` rows with notes ("basi", "tumpah").
  - Sales from 1 June 2026 (WIB) to yesterday: 20–45 transactions a day, 1–4 lines each, Saturdays busiest, Mondays quietest, about one day in ten with no sales. `occurred_at` between 06:00 and 22:00 WIB. `raw_text` is "<name> <qty>" lines, `client_uuid` is `uuidv7()`, and totals use `round(quantity * unit_price)`.
  - About 2 % of sales voided the documented way (`status = 'voided'`, `voided_at`), and one revision chain (`replaces_id`) to show "Riwayat ubahan".
- Commit it as the first commit of this branch. Branch 08 uses it as is.

## Commits
0. `chore(app): local seed script for past sales`
1. `feat(app-history): TransactionRepository and AnalyticsRepository (month, days, day items, months)`
2. `feat(app-history): Histori tab with summary, top 3, per-day cards, month stepper and picker`
3. `feat(app-history): Day list with date picker`
4. `feat(app-history): transaction Detail with history`
5. `feat(app-history): Batalkan sheet and void`
6. `feat(app-history): Ubah with revise and product picker`
7. `test(app-history): void math, revise body shape, lines_invalid rows, voided and replaced detail states, empty state`

## Done when
- Make 3 sales in Catat, see today's card, expand it, open the Day list and a Detail.
- Ubah one (change qty, add an item), save, and see "Riwayat ubahan" with the old version. Stock in Produk matches.
- Batalkan another, and it shows as Dibatalkan, with the day revenue down and the stock back.
