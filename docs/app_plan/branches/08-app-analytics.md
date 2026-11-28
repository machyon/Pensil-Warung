# 08 · `feature/app-analytics`

**Goal:** the Analitik segment of the Histori tab and the "Semua barang terjual" screen.

Screens: [08] `AnalitikBulan`, [34] `AnalitikKosong`, [09] `BarangTerjual`.

## Endpoints
| Method | Path | Use |
|---|---|---|
| GET | `/api/v1/analytics/month?month=` | Summary, comparison, trend, weekday, top items |
| GET | `/api/v1/analytics/month/days?month=&limit=31` | Days with sales (the count drives the gates) and the Per hari cards |
| GET | `/api/v1/analytics/days/{date}/items` | Day card expand (shared `DayCard`) |
| GET | `/api/v1/analytics/month/items?month=&q=` | Barang terjual |

## Rules
- Header "Laporan Analitik". The month comes from the shared `MonthStepper` (same month state as the Histori segment).
- Summary: revenue, then "▲ 8% dari 1–17 Okt · 641 transaksi" from `previous.change_pct` (▼ when negative, hidden when `null`).
- Trend: **12 bars** from `trend` (decisions), labels "Jun", values compact ("28,7jt"). The viewed month is highlighted. Tapping a bar switches the month (disabled for months before the first sale).
- Hari paling ramai: from `weekday_avg` (1 = Monday). "<Best> biasanya paling laris", "Rata-rata RpX. Paling sepi hari <worst>, RpY." The average shown = the mean of the 7 values. Footnote "Rata-rata dari N hari di <bulan>." Drop the line "Ubah zona waktu di Akun" and keep "Hari dihitung dalam WIB."
- Barang terlaris: top 3 of `top_items` with photo (`product_id` → product cache), "N terjual · RpX", "Stok N" (hidden when `stock` is null). Sentence: "<Top revenue item> menyumbang P% penjualan, walau <top qty item> paling banyak terjual." when they differ, else "<Name> paling laris bulan ini." "Lihat semua barang" → [09].
- **[34] gates (planner's calls):** days with sales < 14 → the "Laporan lengkap sedang disiapkan" card with the progress bar "N dari 14 hari · M hari lagi", and under "Akan muncul nanti": Hari paling ramai (after 14 days), Dibanding bulan lalu ("Mulai <next month>" while `change_pct` is null), Barang terlaris (after 7 days). Sections whose gate has passed show normally.
- [09] Barang terjual: "Terjual" total_qty, "Pendapatan", a share bar of the top 5 + "Lainnya" with %, search (`q`, debounced 300 ms), rows with `share_pct` · revenue, "N terjual", "Stok N". "Belum terjual bulan ini" lists `unsold`. No "hampir habis".

## Commits
1. `feat(app-analytics): Analitik summary, comparison and 12-month trend`
2. `feat(app-analytics): weekday chart and top items`
3. `feat(app-analytics): not-enough-data gates`
4. `feat(app-analytics): Barang terjual with search and unsold`
5. `test(app-analytics): gate thresholds, change_pct null and negative, best and worst weekday text, share bar Lainnya`

## Done when
- A fresh account with a few sales shows [34] with the correct day count.
- On an account seeded with `tool/seed_local.sql` (branch 07), the full [08] renders: 12 trend bars from June, the weekday chart, top items with stock, and Barang terjual with Teh botol under "Belum terjual". Tapping a trend bar switches the month.
