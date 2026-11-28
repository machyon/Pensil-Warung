# App plan (v1)

The Flutter client in `pensil_warung/`. The plan is split into small files, so read only what your task needs:

1. `decisions.md`: what was agreed and why (short). Read it once.
2. `conventions.md`: folder layout, coding rules, packages, error, logging and test patterns. Read it before writing any code.
3. `branches/NN-*.md`: one file per branch, holding its screens, endpoints, rules, commits and done-when checks. Read only the branch you're working on.
4. `backend_issues.md`: backend faults found while building the app. Append to it, never fix the backend from an app branch.

The design source is the "Prototype" canvas, page Hi-Fi: https://claude.ai/code/artifact/6b2fbac6-7e39-4e12-927c-37523595267d. Screens are named by their file, `project/<Name>.dc.html`, with the canvas number in brackets (for example `AppCatat` [04]). The API is `docs/api.md`.

## Workflow
- The app talks to the **real local backend from the first commit**. There are no fake repositories. Start it with `cd backend && cargo run -- migrate && cargo run` before running the app.
- Branch off `develop`, then open a PR into `develop`.
- Use conventional commits with a scope (`feat(app-catat): …`, `chore(app): …`, `test(app-catat): …`), following the commit list in the branch file.
- Work on the branches in order, since each one depends on the ones above it.
- If a request fails, read the app log (`[api]` lines) and the backend log for the same `x-request-id`. If the backend is at fault, add an entry to `backend_issues.md` and tell the user (see `conventions.md`, Errors).

## Branches
| # | Branch | File | Depends on |
|---|---|---|---|
| 1 | `chore/app-foundation` | `branches/01-app-foundation.md` | none |
| 2 | `feature/app-auth` | `branches/02-app-auth.md` | 1 |
| 3 | `feature/app-products` | `branches/03-app-products.md` | 2 |
| 4 | `feature/app-product-photos` | `branches/04-app-product-photos.md` | 3 |
| 5 | `feature/app-catat-parser` | `branches/05-app-catat-parser.md` | 1 |
| 6 | `feature/app-catat` | `branches/06-app-catat.md` | 3, 5 |
| 7 | `feature/app-history` | `branches/07-app-history.md` | 6 |
| 8 | `feature/app-analytics` | `branches/08-app-analytics.md` | 7 |
| 9 | `feature/app-notifications` | `branches/09-app-notifications.md` | 2 |
| 10 | `feature/app-settings` | `branches/10-app-settings.md` | 2 |
| 11 | `feature/app-broadcaster` | `branches/11-app-broadcaster.md` | 10 |
| 12 | release `app-v0.1.0` | `branches/12-app-release.md` | all |
