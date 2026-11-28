# 11 · `feature/app-broadcaster`

**Goal:** the broadcaster shell: list, write, send or schedule, view, edit and cancel broadcasts.

Screens: [17] `Siaran`, [18] `SiaranTulis`, [20] `SiaranKirim`, [21] `SiaranTerjadwal`, [22] `SiaranTerkirim`, [23] `SiaranAkun`.

## Endpoints
| Method | Path | Use |
|---|---|---|
| GET | `/api/v1/broadcaster/broadcasts?cursor=` | [17] `recipient_count`, `scheduled`, paged `sent` |
| POST | `/api/v1/broadcaster/broadcasts` | [20] send now (`send_at: null`) or schedule |
| GET | `/api/v1/broadcaster/broadcasts/{id}` | [21]/[22] detail |
| PATCH | `/api/v1/broadcaster/broadcasts/{id}` | "Ubah" from [21] |
| POST | `/api/v1/broadcaster/broadcasts/{id}/cancel` | "Batalkan" from [21] |

## Rules
- Shell tabs: Siaran / Tulis / Akun (`MainNav` broadcaster variant). The header avatar shows the broadcaster's letter.
- [17]: "Ke semua pengguna · N akun" (`recipient_count`, `id_ID` thousands). "Terjadwal" rows show the time and a countdown ("6j 12m lagi"). "Terkirim" rows show the category tag and time. Tap → [21] or [22] by `effective_status`.
- [18] step 1: Kategori (Pembaruan/Berita/Info/Tips), Judul with a counter /60, Ringkasan /120, Isi lengkap (optional). "Lanjut Jadwalkan" is disabled with "Isi judul dan ringkasan dulu" until both are filled. The draft lives in a view model shared with [20].
- [20] step 2: "Kirim sekarang" / "Jadwalkan" radios. Tanggal (date picker) + Jam (WIB) `HH:MM`, sent as RFC 3339 with `+07:00`. A time in the past → the alert "Waktunya sudah lewat" locally. The server's `422 time_passed` shows the same. Summary card + "Ubah pesan". The confirm sheet "Ya, kirim" / "Ya, jadwalkan" shows "N penerima".
- [21]: status card (Terjadwal + countdown, or Dibatalkan with who/when), recipients, message. "Batalkan" → sheet → cancel. "Ubah" → [18] prefilled, then [20] → PATCH (send only changed fields; "Kirim sekarang" = `send_at: null`). `409 not_editable` → reload and show its status.
- [22]: sent detail, the note "Siaran yang sudah terkirim tidak bisa diubah atau ditarik. Untuk meralat, kirim siaran baru.", "Buat siaran baru".
- [23] Akun: reuses branch 10's screens (username, email, password, Tampilan, Tentang, Legal, Keluar), plus the "Penyiar" badge. No Hapus akun.

## Commits
1. `feat(app-broadcaster): BroadcasterRepository and Siaran list`
2. `feat(app-broadcaster): Tulis step 1 and Kirim step 2 with schedule`
3. `feat(app-broadcaster): Terjadwal with Ubah and Batalkan, Terkirim`
4. `feat(app-broadcaster): Akun tab from settings screens`
5. `test(app-broadcaster): WIB send_at encoding, past time blocked, PATCH sends only changes, not_editable reload`

## Done when
- From a promoted account: schedule one for 2 minutes ahead, edit it, and after 2 minutes see it under Terkirim and in a normal user's Notifikasi. Cancel another one, and it's gone from both lists.
