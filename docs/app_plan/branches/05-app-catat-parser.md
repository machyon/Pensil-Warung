# 05 · `feature/app-catat-parser`

**Goal:** the pure Dart brain of Catat: typed text → ops, fuzzy name matching, and the live "Hasil baca" with errors, warnings and fixes. No UI and no HTTP. Heavily unit-tested.

Design behaviour comes from [05] `AppCatatIsi`, [13] `CatatLinter`, [12] `CatatKonfirmasi` and [02] `AppCatatTanpaProduk`.

## Input and output
`lint(String text, List<Product> products) → LintResult`
- `LintResult { lines: [LineResult], ops: [Op], total: int, saleCount, portionCount, errors, warnings, canSave }`
- `LineResult { lineNo, raw, kind, status: ok|warning|error, message, product?, quantity?, unitPrice?, lineTotal?, stockAfter?, fixes: [Fix] }`
- `Op` serialises to the `POST /catat` op JSON exactly (`docs/api.md`).
- `Fix { label, apply(String text) → String }` returns new box text.

## Grammar (from `docs/api.md`; check prefixes in this order, case-insensitive, extra spaces ignored)
| Line | Op |
|---|---|
| `tambah stok <name> <qty>` | `restock` |
| `hapus stok <name> <qty> [alasan <reason>]` | `adjust_down` with `note` |
| `buat produk <name> harga <price> stok <stock>` | `create_product` |
| `ubah harga <name> <price>` | `set_price` |
| `hapus <name>` | `delete_product` |
| `<name> <qty>` | `sale` |

- `line_no` = the line's number in the box (1-based). Blank lines are skipped but keep their numbers.
- Numbers: digits, with optional dot thousands separators (`2000`, `2.000`). A decimal (`1,5`, `1.5` where the part after the dot isn't 3 digits) is an error, "Jumlah harus bilangan bulat". Quantity 1–999 999 999. Price/stock ≥ 0.
- A sale with no number: **warning**, "Jumlah tidak ditulis, dianggap 1", quantity 1 ([13] line 3).
- `buat produk` with no `harga`: error "Harga belum ditulis", with the example `buat produk kerupuk harga 2000 stok 30`. `stok` missing = 0.

## Matching (`matcher.dart`)
- Key = lowercase, trim, collapse spaces (the same rule as the server's `name_key`).
- Exact key match wins. Otherwise suggest the closest product by Levenshtein distance ≤ 2 (or ≤ 30 % of the length for long names). Error "Barang tidak ada di daftar", fixes "Ganti jadi <Name>" (rewrites the name on that line) and "Jadikan barang baru" (rewrites to `buat produk <name> harga  stok ` and puts the cursor after `harga `).
- Within one text: a `buat produk` line makes the name usable by later lines. A `hapus` line makes it unknown to later lines. Two `buat produk` lines for the same name: error "<Name> sudah ditulis di baris lain". Creating an existing name: error "Nama sudah dipakai".

## Stock and totals (mirror the server, `branches/06-catat.md` in backend_plan)
- Simulate stock line by line from the product cache. `tambah stok` and `buat produk` earlier count toward later checks. A short sale: error "Stok cuma N, kurang M", fixes "Jual N saja" (sets the quantity) and "Tambah stok M dulu" (inserts `tambah stok <name> M` above the line).
- Sale price = the current price, after any earlier `ubah harga` line in the text. `total` = the sum of sale line totals (`hapus stok` lines are not in Total, [12]).
- `canSave` = at least one op and no errors (warnings are fine).

## Confirm summary (for [12])
`ConfirmSummary` from `LintResult`: Jualan (items, portions, total), Barang baru (name, price, stock), Ubah harga (old → new), Stok masuk, Stok keluar (with reason, "Tidak masuk Total"), Hapus barang (remaining stock, with the warning "… hilang dari Produk dan tidak bisa dibatalkan. Riwayat jualannya tetap ada."). `needsConfirm` = any non-sale op.

## Server errors
`mapServerLines(LintResult, details.lines)` attaches each server `{line_no, code, message}` to its box line as an error, so a stock race the client missed still shows on the right line.

## Commits
1. `feat(app-catat): line tokenizer and number parsing`
2. `feat(app-catat): command grammar to ops`
3. `feat(app-catat): name matcher with suggestions`
4. `feat(app-catat): batch simulation for stock, price and totals`
5. `feat(app-catat): fixes and confirm summary`
6. `test(app-catat): every grammar line, decimals, missing qty, fuzzy match, create-then-sell, delete-then-sell, stock fixes, set_price order, server line mapping`

## Done when
- `flutter test test/catat/` passes, with a test for every row of the grammar table and every message above.
- The ops JSON for the `docs/api.md` example request is byte-for-byte equal to the doc's `ops`.
