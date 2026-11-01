# Quizly: stages (Etapy)

The full brief is in [`CLAUDE.md`](./CLAUDE.md).

**How to use this file**
- The agent ticks `- [x]` on a task when it's done, in the stage's PR.
- Tasks marked **(Jakub)** are done by Jakub.
- The **Gate** box is ticked only after Jakub says **"good"**. Never start the next stage before that.
- Each stage has its own branch and PR.

| Etapa | Name | Branch | Status |
| --- | --- | --- | --- |
| 0 | Preparation | `main` | Approved |
| 1 | Spec and design | `etapa-1-spec` | Approved |
| 2 | API foundation | `etapa-2-api` | Approved |
| 3 | Learning and game logic | `etapa-3-logic` | Approved |
| 4 | Admin dashboard and first deploy | `etapa-4-admin` | Approved |
| 5 | Android app core | `etapa-5-app` | Approved |
| 6 | Motivation layer | `etapa-6-motivation` | Approved |
| 7 | Notifications | `etapa-7-notifications` | Waiting for review |
| 8 | Release and polish | `etapa-8-release` | Not started |

Update the **Status** column when a stage starts, waits for review, or is approved.

---

## Definition of done (every stage)

- [ ] All tasks of the stage ticked, or moved to a later stage with a note
- [ ] CI green, new logic covered by tests
- [ ] `CLAUDE.md` updated if any decision changed (+ a line in its Decisions log)
- [ ] PR description: what was built, how to try it, known issues, ideas for later
- [ ] Summary posted to Jakub, then stop and wait for "good" / "bad"

---

## Etapa 0: Preparation

- [x] Gather requirements (Q&A with Jakub)
- [x] Write the project brief (`CLAUDE.md`)
- [x] Write this stages checklist (`STAGES.md`)
- [x] **(Jakub)** Confirm the plan and the defaults in `CLAUDE.md` §13
- [x] **(Jakub)** Create a private GitHub repo and send `owner/repo` → `Jbohacek/Quizly`
- [x] Initial commit on `main`: `CLAUDE.md`, `STAGES.md`, `README.md`, `.gitignore` (.NET + Flutter), `.editorconfig` (+ `.gitattributes` for LF line endings)

**Gate**
- [x] Approved by Jakub

---

## Etapa 1: Spec and design

No production code in this stage.

**Design**
- [x] Design proposal: 10 phone screens + 4 admin pages (claude.ai Design canvas, saved copy in `docs/design/quizly-design-proposal.html`)
- [x] Apply main color `#BAD69B` and the friendly notification tone
- [x] **(Jakub)** Approve the design, or list changes
- [x] Design for the admin "Texty upozornění" page (missing from the canvas) → `docs/design/admin-texty-upozorneni.html`

**Spec documents**
- [x] `docs/spec.md`: final data model with field types, constraints, indexes, cascade rules
- [x] `docs/api.md`: every endpoint with request/response examples and error codes
- [x] Sync contract (`docs/api.md` §11): session fetch, review batches, idempotency, retry and offline behavior
- [x] `docs/yaml-format.md`: format v1, validation rules, merge/delete rules, examples
- [x] FSRS: chosen version, default parameters, reference test vectors (`docs/spec.md` §3, `docs/fsrs/`)
- [x] Points, streak and milestone rules with worked examples (`docs/spec.md` §5–6) (rounding, midnight, DST days, missed day, goal change)
- [x] `docs/notification-texts.md`: ≥ 50 Czech texts across all 6 categories, placeholders, gender-neutral check
- [x] Notification scheduling rules (`docs/notifications.md`) incl. Android 13+ permission and Android 12/14 exact-alarm rules
- [x] Final repo layout and Flutter package list (`docs/architecture.md`)
- [x] Resolve the open decisions in `CLAUDE.md` §13 with Jakub (confirmed at the Etapa 0 gate; FSRS, fuzz, goal change and design location decided 2026-10-31)

**Gate**
- [x] Approved by Jakub (screens + spec)

---

## Etapa 2: API foundation

- [x] Solution and projects per the agreed layout; nullable on, warnings as errors
- [x] EF Core + PostgreSQL, full data model, initial migration, migrations on startup
- [x] App auth: login, rotating refresh tokens, logout, JWT, rate limit on login
- [x] Admin auth from env vars (`ADMIN_USERNAME`, `ADMIN_PASSWORD`)
- [x] REST CRUD: users (+ reset password, activate/deactivate), decks, cards, shop items, notification texts
- [x] Seed notification texts; optional demo deck in Development only
- [x] Validation, ProblemDetails errors, OpenAPI + Swagger UI at `/api/docs`
- [x] `/api/health`
- [x] Multi-stage `Dockerfile`, `deploy/docker-compose.yml`, `deploy/.env.example`
- [x] GitHub Actions `api.yml`: build + test on PR, push image to GHCR on `main`
- [x] Tests: auth, CRUD, validation

**Gate**
- [x] `docker compose up` works locally, endpoints work in Swagger, CI green
- [x] Approved by Jakub

---

## Etapa 3: Learning and game logic

- [x] FSRS scheduler (port + unit tests against reference vectors)
- [x] `GET /api/session`: due cards + new-card allowance, one deck or all (+ `GET /api/decks`)
- [x] `POST /api/reviews`: batch, idempotent by client UUID
- [x] Points with multiplier and rounding, written to the points ledger
- [x] Daily activity, daily goal, streak + best streak (Europe/Prague day boundary)
- [x] Milestone bonuses (7 / 30 / 100 / 365)
- [x] Shop: claim in one transaction (no overselling), confirm, reject (refund + restock)
- [x] Wishlist endpoints
- [x] `/api/me` summary and `/api/me/settings`
- [x] Stats endpoint: tiles, heatmap, daily bars, weekday, best time, deck progress
- [x] Unit tests: FSRS, points, streak edge cases (midnight, DST, missed day, goal change), claim concurrency, idempotency

**Gate**
- [x] A full session can be played through Swagger; tests green
- [x] Approved by Jakub

---

## Etapa 4: Admin dashboard and first deploy

- [x] Blazor admin layout (sidebar, responsive), login / logout
- [x] **Přehled:** tiles, pending claims with Schválit / Zamítnout, "Uživatelé dnes"
- [x] **Balíčky:** list, detail, cards CRUD, deck settings
- [x] **YAML:** export, copy, download, paste/import, preview diff, validation with line numbers, delete confirmation, apply; import as a new deck
- [x] **Obchod:** items CRUD, purchase history with filters, confirm / reject
- [x] **Uživatelé:** list, create (password shown once), edit, reset password, activate / deactivate
- [x] **Texty upozornění:** CRUD by category + preview
- [x] Forwarded headers, Data Protection keys on a volume, websockets behind the proxy (NPM switch in the guide)
- [x] `deploy/README-deploy.md`: Portainer stack, GHCR registry, NPM proxy host, first login
- [x] **(Jakub)** DNS record for `quizly.jbohacek.cz`
- [x] **(Jakub)** Nginx Proxy Manager proxy host + SSL certificate (websockets on)
- [x] **(Jakub)** GitHub token with `read:packages` added to Portainer as a registry
- [x] **(Jakub)** Deploy the stack following the guide

**Gate**
- [ ] Jakub creates a real deck and a real user on the live dashboard
- [x] Approved by Jakub (live at `https://quizly.jbohacek.cz`, 2026-11-01)

---

## Etapa 5: Android app core

- [x] Flutter project, packages, theme tokens, bundled fonts, Czech strings file
- [x] API client with token refresh; tokens in secure storage
- [x] **Přihlášení** screen
- [x] **Domů:** greeting, points pill, streak card, goal ring, CTA, deck list, bottom nav (week strip moved to Etapa 6 with the other streak visuals)
- [x] **Učení:** card stack, 3D flip, swipe with stamp, Vím / Nevím / Přeskočit, progress, session points, "Nevím" re-queue
- [x] Review submission with retry + idempotency; "Jsi offline" state
- [x] **Hotovo** screen (basic version)
- [x] **Nastavení:** daily goal, new cards per day, logout
- [x] Added at review: **Změnit heslo** in Nastavení (`POST /api/me/password`) and a **Balíček** detail with all cards and their status (`GET /api/decks/{id}/cards`)
- [x] GitHub Actions `app.yml`: analyze, test, signed release APK as an artifact (the APK job runs on `main` once the 4 secrets exist)
- [x] **(Jakub)** Create the signing keystore (agent gives the command) and add the 4 GitHub Secrets
- [x] **(Jakub)** Allow installs from unknown sources and install the APK

**Gate**
- [x] Jakub studies a real deck on the phone
- [x] Approved by Jakub (merged PR #5, signed APK built on `main`, 2026-11-01)

---

## Etapa 6: Motivation layer

- [x] Points animations: floating "+N", rolling counters, multiplier chip
- [x] Streak visuals: week strip, flame, milestone celebration with confetti
- [x] Full **Hotovo** screen: breakdown, new balance, wishlist progress
- [x] **Obchod:** items, wishlist hearts, "Šetříš na" card, purchase bottom sheet, **Moje nákupy** with statuses
- [x] **Statistiky:** tiles, heatmap, daily bars with goal line, weekday / best time, deck progress, deck filter
- [x] Respect "reduce motion"

**Gate**
- [x] One full day works end to end: study → points → streak → buy → admin confirms → status shows in the app
- [x] Approved by Jakub (merged PR #6, 2026-11-01)

---

## Etapa 7: Notifications

- [x] Notification permission flow (Android 13+)
- [x] Download and cache texts; random pick without recent repeats; placeholders
- [x] Morning, evening and last-call scheduling; cancel when the goal is met
- [x] Milestone, wishlist and comeback notifications
- [x] Quiet hours and **Chytré časy**
- [x] Background refresh (WorkManager) for due counts and texts
- [x] **Nastavení** wired to all notification options
- [x] Unit tests for the scheduling logic (pure Dart)

**Gate**
- [ ] Notifications arrive at the right times over a few days of real use
- [ ] Approved by Jakub

---

## Etapa 8: Release and polish

- [ ] Nightly PostgreSQL backup (`deploy/backup.sh`) + a tested restore
- [ ] `README.md` (overview, local development) and runbook (update, rollback, restore, rotate secrets)
- [ ] Fixes from Jakub's testing
- [ ] Final pass over all Czech texts: typos, tone, gender-neutral
- [ ] Accessibility check: contrast, touch targets, TalkBack labels
- [ ] Tag `v1.0.0`, APK attached to the GitHub Release

**Gate**
- [ ] Jakub calls it done 🎉
