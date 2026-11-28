# 04 · `feature/app-product-photos`

**Goal:** take or pick a product photo, crop it square, upload it.

Screens: [21] `FotoPilih` (sheet), [22] `FotoPotong`.

## Endpoints
| Method | Path | Use |
|---|---|---|
| PUT | `/api/v1/products/{id}/photo` | Multipart upload of the cropped image (see `docs/api.md`, Photos, for the field name and limits) |
| DELETE | `/api/v1/products/{id}/photo` | "Hapus foto" |

## Rules
- `image_picker` for "Ambil foto" (camera) and "Pilih dari galeri". `crop_your_image` for [22]: a square frame, drag to move, a zoom slider ("Perbesar foto"), "Putar 90 derajat", "Ulangi" (back to the sheet), "Pakai foto".
- Encode the crop as JPEG, at most 1024 px on a side, before upload. The server resizes again.
- "Hapus foto" appears only when the product has a photo.
- Entry points: [18] Detail avatar button, [19] Ubah "Tambah foto", [03] Tambah barang row button.
- [03] and Catat's command mode (branch 06): the product doesn't exist yet, so keep the cropped bytes on the row and upload them after the save returns the id (decisions, planner's calls). An upload failure after a save keeps the product and shows "Foto belum terunggah" with a retry on Detail.
- `photo_url` is a presigned URL that expires. Load it with `Image.network`, and on a load error refresh the product once.
- Android: camera permission text, and `image_picker`'s manifest setup.

## Commits
1. `feat(app-photos): FotoPilih sheet with camera and gallery`
2. `feat(app-photos): FotoPotong square crop, zoom, rotate`
3. `feat(app-photos): upload and delete photo, show in ProductAvatar`
4. `feat(app-photos): photos on new rows, uploaded after save`
5. `test(app-photos): upload sends multipart, delete hides button, retry after failed upload`

## Done when
- A camera photo and a gallery photo both upload and show in the list, detail and Catat results. Hapus foto goes back to the initials.
