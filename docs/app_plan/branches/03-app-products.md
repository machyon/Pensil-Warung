# 03 · `feature/app-products`

**Goal:** the Produk tab: list, search, detail with stock history, edit, delete, and bulk add.

Screens: [07] `AppProduk`, [35] `ProdukKosong`, [36] `ProdukCariKosong`, [18] `ProdukDetail`, [19] `ProdukUbah`, [20] `ProdukHapus`, [03] `AppTambahBarang`.

## Endpoints
| Method | Path | Screen |
|---|---|---|
| GET | `/api/v1/products?q=` | List (no `q`, it also fills the product cache). Search filters the cached list on the client, no request per key |
| GET | `/api/v1/products/{id}` | Detail |
| GET | `/api/v1/products/{id}/movements?cursor=&limit=` | Detail "Riwayat stok", paged as you scroll |
| GET | `/api/v1/analytics/month/items?month=` | Detail "Terjual bulan ini", "Pendapatan bulan ini", "Terlaris ke-N" (the product's row and its index) |
| POST | `/api/v1/products/bulk` | Tambah barang `{items:[{name, price, stock}]}` |
| PATCH | `/api/v1/products/{id}` | Ubah `{name?, price?, stock?}` (send only changed fields) |
| DELETE | `/api/v1/products/{id}` | Hapus |

## Rules
- List rows: `ProductAvatar`, name, price, "Stok N". Count line "N produk". The "Tambah" button in the nav row (as drawn) opens Tambah barang.
- [36]: search with no match shows `"<q>" tidak ditemukan` and "Tambah "<q>"", which opens Tambah barang with the name filled in.
- [35] empty: "Atau ketik di Catat **buat produk kerupuk harga 2000 stok 30**" (grammar decision).
- Riwayat stok labels by `reason`: `initial` "Stok awal", `restock` "Stok masuk", `adjustment` "Stok keluar" (+ " · <note>" when there is one), `sale` "Terjual", `void_sale` "Batal jual". Signed delta, time as "Hari ini, 14.32" / "Kemarin, 21.40" / "Sen, 16 Nov, 08.00" (WIB).
- Ubah [19]: helper text "Semula Rp15.000. Jualan yang sudah tercatat tetap pakai harga lama." appears only when the price changed. `409 name_taken` shows under Nama. The photo row links to branch 04 (hidden until then).
- Hapus [20]: the sheet text uses the stock and this month's sold count. On `204`, drop it from the cache and pop to the list.
- Tambah barang [03]: rows of name / Rp price / stock, "Tambah barang lain", per-row delete. A row with no price is not sent and says "Belum ada harga, jadi belum ikut disimpan." The footer counts "N barang" ready. Price input formats with dots as you type. `409 name_taken` with `details.index` marks that row. The photo button per row comes in branch 04.
- After any save, refresh the product cache.

## Commits
1. `feat(app-products): ProductRepository with cache`
2. `feat(app-products): Produk list, search, empty and no-match states`
3. `feat(app-products): Detail with month figures and paged stock history`
4. `feat(app-products): Ubah and Hapus`
5. `feat(app-products): Tambah barang bulk add`
6. `test(app-products): search filter, movement labels, bulk skip-without-price, name_taken row`

## Done when
- Add 3 products in bulk, find one by search, edit its price and stock, and see "Stok masuk" or "Stok keluar" in its history. Delete one, and it disappears.
- A duplicate name in bulk marks the right row.
