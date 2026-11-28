# 09 · `feature/app-notifications`

**Goal:** the bell: the broadcast feed with unread state kept on the phone.

Screens: [32b] `Notifikasi`, [32] `NotifikasiKosong`.

## Endpoints
| Method | Path | Use |
|---|---|---|
| GET | `/api/v1/broadcasts` | Latest 5 sent, newest first |
| GET | `/api/v1/broadcasts/{id}` | `body` for the sheet |

## Rules
- Unread = an id not in the read-id set in `prefs.dart`. The `AppHeader` bell shows a dot when the latest feed has any unread. Refresh the feed on app resume and when the bell screen opens.
- Header subtitle: "N belum dibaca" or "Belum ada". Filter `SegmentedTabs`: Semua / Belum dibaca.
- Row: category tag (`update` Pembaruan, `berita` Berita, `info` Info, `tips` Tips) · relative time ("Baru saja", "N menit lalu", "Hari ini, 09.12", "Kemarin, 20.31"), title, summary, and an unread dot.
- Tap → a sheet with title, summary and `body` (fetched only when `has_body`). Opening marks it read (planner's call).
- Empty [32]: "Belum ada notifikasi" / "Pembaruan aplikasi, berita, dan tips dari Pensil Warung akan muncul di sini."

## Commits
1. `feat(app-notifications): BroadcastRepository and read-state prefs`
2. `feat(app-notifications): Notifikasi feed, filter, empty state, bell dot`
3. `feat(app-notifications): detail sheet marks read`
4. `test(app-notifications): unread count, filter, mark read on open`

## Done when
- A broadcast sent from a broadcaster account (branch 11, or curl) shows with a dot. Opening it clears the dot, and that survives an app restart.
