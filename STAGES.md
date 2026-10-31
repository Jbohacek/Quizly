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
| 1 | Spec and design | `etapa-1-spec` | In progress (design drafted) |
| 2 | API foundation | `etapa-2-api` | Not started |
| 3 | Learning and game logic | `etapa-3-logic` | Not started |
| 4 | Admin dashboard and first deploy | `etapa-4-admin` | Not started |
| 5 | Android app core | `etapa-5-app` | Not started |
| 6 | Motivation layer | `etapa-6-motivation` | Not started |
| 7 | Notifications | `etapa-7-notifications` | Not started |
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
- [ ] **(Jakub)** Approve the design, or list changes
- [ ] Design for the admin "Texty upozornění" page (missing from the canvas)

**Spec documents**
- [ ] `docs/spec.md`: final data model with field types, constraints, indexes, cascade rules
- [ ] `docs/api.md`: every endpoint with request/response examples and error codes
- [ ] Sync contract: session fetch, review batches, idempotency, retry and offline behavior
- [ ] `docs/yaml-format.md`: format v1, validation rules, merge/delete rules, examples
- [ ] FSRS: chosen version, default parameters, reference test vectors
- [ ] Points, streak and milestone rules with worked examples (rounding, midnight, DST days, missed day, goal change)
- [ ] `docs/notification-texts.md`: ≥ 50 Czech texts across all 6 categories, placeholders, gender-neutral check
- [ ] Notification scheduling rules incl. Android 13+ permission and Android 12/14 exact-alarm rules
- [ ] Final repo layout and Flutter package list
- [ ] Resolve the open decisions in `CLAUDE.md` §13 with Jakub

**Gate**
- [ ] Approved by Jakub (screens + spec)

---

## Etapa 2: API foundation

- [ ] Solution and projects per the agreed layout; nullable on, warnings as errors
- [ ] EF Core + PostgreSQL, full data model, initial migration, migrations on startup
- [ ] App auth: login, rotating refresh tokens, logout, JWT, rate limit on login
- [ ] Admin auth from env vars (`ADMIN_USERNAME`, `ADMIN_PASSWORD`)
- [ ] REST CRUD: users (+ reset password, activate/deactivate), decks, cards, shop items, notification texts
- [ ] Seed notification texts; optional demo deck in Development only
- [ ] Validation, ProblemDetails errors, OpenAPI + Swagger UI at `/api/docs`
- [ ] `/api/health`
- [ ] Multi-stage `Dockerfile`, `deploy/docker-compose.yml`, `deploy/.env.example`
- [ ] GitHub Actions `api.yml`: build + test on PR, push image to GHCR on `main`
- [ ] Tests: auth, CRUD, validation

**Gate**
- [ ] `docker compose up` works locally, endpoints work in Swagger, CI green
- [ ] Approved by Jakub

---

## Etapa 3: Learning and game logic

- [ ] FSRS scheduler (port + unit tests against reference vectors)
- [ ] `GET /api/session`: due cards + new-card allowance, one deck or all
- [ ] `POST /api/reviews`: batch, idempotent by client UUID
- [ ] Points with multiplier and rounding, written to the points ledger
- [ ] Daily activity, daily goal, streak + best streak (Europe/Prague day boundary)
- [ ] Milestone bonuses (7 / 30 / 100 / 365)
- [ ] Shop: claim in one transaction (no overselling), confirm, reject (refund + restock)
- [ ] Wishlist endpoints
- [ ] `/api/me` summary and `/api/me/settings`
- [ ] Stats endpoint: tiles, heatmap, daily bars, weekday, best time, deck progress
- [ ] Unit tests: FSRS, points, streak edge cases (midnight, DST, missed day, goal change), claim concurrency, idempotency

**Gate**
- [ ] A full session can be played through Swagger; tests green
- [ ] Approved by Jakub

---

## Etapa 4: Admin dashboard and first deploy

- [ ] Blazor admin layout (sidebar, responsive), login / logout
- [ ] **Přehled:** tiles, pending claims with Schválit / Zamítnout, "Uživatelé dnes"
- [ ] **Balíčky:** list, detail, cards CRUD, deck settings
- [ ] **YAML:** export, copy, download, paste/import, preview diff, validation with line numbers, delete confirmation, apply; import as a new deck
- [ ] **Obchod:** items CRUD, purchase history with filters, confirm / reject
- [ ] **Uživatelé:** list, create (password shown once), edit, reset password, activate / deactivate
- [ ] **Texty upozornění:** CRUD by category + preview
- [ ] Forwarded headers, Data Protection keys on a volume, websockets behind the proxy
- [ ] `deploy/README-deploy.md`: Portainer stack, GHCR registry, NPM proxy host, first login
- [ ] **(Jakub)** DNS record for `quizly.jbohacek.cz`
- [ ] **(Jakub)** Nginx Proxy Manager proxy host + SSL certificate (websockets on)
- [ ] **(Jakub)** GitHub token with `read:packages` added to Portainer as a registry
- [ ] **(Jakub)** Deploy the stack following the guide

**Gate**
- [ ] Jakub creates a real deck and a real user on the live dashboard
- [ ] Approved by Jakub

---

## Etapa 5: Android app core

- [ ] Flutter project, packages, theme tokens, bundled fonts, Czech strings file
- [ ] API client with token refresh; tokens in secure storage
- [ ] **Přihlášení** screen
- [ ] **Domů:** greeting, points pill, streak card, goal ring, CTA, deck list, bottom nav
- [ ] **Učení:** card stack, 3D flip, swipe with stamp, Vím / Nevím / Přeskočit, progress, session points, "Nevím" re-queue
- [ ] Review submission with retry + idempotency; "Jsi offline" state
- [ ] **Hotovo** screen (basic version)
- [ ] **Nastavení:** daily goal, new cards per day, logout
- [ ] GitHub Actions `app.yml`: analyze, test, signed release APK as an artifact
- [ ] **(Jakub)** Create the signing keystore (agent gives the command) and add the 4 GitHub Secrets
- [ ] **(Jakub)** Allow installs from unknown sources and install the APK

**Gate**
- [ ] Jakub studies a real deck on the phone
- [ ] Approved by Jakub

---

## Etapa 6: Motivation layer

- [ ] Points animations: floating "+N", rolling counters, multiplier chip
- [ ] Streak visuals: week strip, flame, milestone celebration with confetti
- [ ] Full **Hotovo** screen: breakdown, new balance, wishlist progress
- [ ] **Obchod:** items, wishlist hearts, "Šetříš na" card, purchase bottom sheet, **Moje nákupy** with statuses
- [ ] **Statistiky:** tiles, heatmap, daily bars with goal line, weekday / best time, deck progress, deck filter
- [ ] Respect "reduce motion"

**Gate**
- [ ] One full day works end to end: study → points → streak → buy → admin confirms → status shows in the app
- [ ] Approved by Jakub

---

## Etapa 7: Notifications

- [ ] Notification permission flow (Android 13+)
- [ ] Download and cache texts; random pick without recent repeats; placeholders
- [ ] Morning, evening and last-call scheduling; cancel when the goal is met
- [ ] Milestone, wishlist and comeback notifications
- [ ] Quiet hours and **Chytré časy**
- [ ] Background refresh (WorkManager) for due counts and texts
- [ ] **Nastavení** wired to all notification options
- [ ] Unit tests for the scheduling logic (pure Dart)

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
