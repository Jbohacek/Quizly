# Quizly: project brief for the coding agent

Read this whole file before doing any work. It is the single source of truth for **what** to build and **how** to work.
Progress is tracked in [`STAGES.md`](./STAGES.md).

---

## 1. What Quizly is

Quizly is a private **Android flashcard app in Czech**. It keeps the user learning with points, a daily streak, real-life rewards bought in a shop, and warm, friendly notifications. One admin manages everything in a web dashboard.

- **Owner / approver:** Jakub
- **Domain:** `https://quizly.jbohacek.cz`. REST API at `/api`, admin dashboard at `/admin`.
- **People:** 1 admin (dashboard only) + a few app users (phone only). All accounts are created by the admin.
- **Language:** the UI is **Czech only** (no i18n). Code, identifiers, comments, commits, PRs and docs are in **English**.
- **Builder:** an AI coding agent (you) works stage by stage under Jakub's supervision.

---

## 2. How you work (rules)

1. Work **only on the current stage** in `STAGES.md`. Never start the next stage until Jakub says **"good"**.
2. One branch per stage: `etapa-<n>-<slug>` (e.g. `etapa-2-api`), branched from `main`. Open a PR to `main`. Make small, meaningful commits.
3. At the end of a stage:
   1. tick the finished tasks in `STAGES.md` (in the same PR),
   2. post a summary: what was built, how to run or try it, known issues, PR link,
   3. **stop and wait** for Jakub.
4. **"good"** → Jakub merges, and you tick the stage's gate box only when told. **"bad" + feedback** → fix it in the same PR and ask again.
5. **Never commit secrets** (`.env`, keystores, tokens, passwords). Use `.env.example` and GitHub Secrets.
6. **Never deploy** to Jakub's server yourself. Prepare the files and step-by-step instructions; Jakub deploys through Portainer.
7. If something is ambiguous or contradicts itself, **ask before building on it**. If Jakub can't answer, choose the simplest option, record it in §14 *Decisions log* and mention it in the PR.
8. **Don't add features that aren't in this file.** Put ideas under "Ideas for later" in the PR description.
9. When a decision changes, update this file in the same PR and add a line to §14.
10. **Tests:** business logic (FSRS, points, streak, claims, YAML import, notification scheduling) must have unit tests. CI must be green before you ask for review.
11. **Czech copy is gender-neutral.** Users can be any gender and the app has none. Avoid past tense and adjectives that agree with the user's or the app's gender: write "Zasloužíš si ji", not "Zasloužil sis ji"; "máš můj obdiv", not "jsem na tebe pyšný".
12. **Czech formatting:** thousands with a non-breaking space (`1 457`), decimal comma (`1,1×`), percent with a space (`83 %`), dates like `31. 10.`.

---

## 3. Tech stack

| Part | Technology |
| --- | --- |
| API | ASP.NET Core on **.NET 10**, REST, JSON, JWT bearer auth for the app |
| Admin dashboard | **Blazor** (Interactive Server render mode) hosted **in the same ASP.NET Core app**, cookie auth, at `/admin` |
| Database | **PostgreSQL 18** (`postgres:18` in compose) via **EF Core 10** + Npgsql, code-first migrations applied on startup |
| Android app | **Flutter** (Dart), Android only, minimum **Android 8.0 (API 26)** |
| Hosting | Docker Compose stack in **Portainer** on Jakub's server, behind **Nginx Proxy Manager** (handles HTTPS) |
| CI/CD | **GitHub Actions**: tests, Docker image to **GitHub Container Registry** (private), signed release **APK** as an artifact |
| Distribution | APK sideloaded onto the phone. Not on Google Play. |

---

## 4. Repository layout

Final layout and package lists: [`docs/architecture.md`](./docs/architecture.md). Summary:

```
/
├─ CLAUDE.md                 ← this file
├─ STAGES.md                 ← checklist of stages
├─ README.md
├─ src/
│  ├─ Quizly.Domain/         entities, enums, pure logic (FSRS, points, streak)
│  ├─ Quizly.Application/    use-case services shared by REST and Blazor
│  ├─ Quizly.Infrastructure/ EF Core DbContext, migrations, persistence
│  └─ Quizly.Web/            ASP.NET Core host: /api endpoints, /admin Blazor, auth
├─ tests/
│  └─ Quizly.Tests/          xUnit
├─ app/                      Flutter project
├─ deploy/                   docker-compose.yml, .env.example, backup.sh, README-deploy.md
├─ docs/                     spec, api, yaml-format, notifications, notification-texts, architecture, design/, fsrs/
└─ .github/workflows/        api.yml, app.yml
```

---

## 5. Features and business rules

### 5.1 Cards and decks
- A **card** is a question plus an answer, **plain text only** for now (no Markdown, no images). Suggested limits: question ≤ 500 chars, answer ≤ 2 000 chars.
- Cards are grouped into **decks**: name, description, color, sort order.
- **Every app user sees every deck** and picks what to study. The admin does not assign decks.
- The admin can CRUD decks and cards, and edit a whole deck as **YAML** (§8). AI-assisted deck creation inside the dashboard comes later and is **out of scope**.

### 5.2 Study session (app)
- The user picks one deck, or **"Učit se vše"** (all decks).
- **Session queue** = due cards (`due ≤ now`, most overdue first) + new cards up to today's remaining allowance. "Nové karty denně" is a user setting, default 5, counted per day across all decks.
- The card shows the question. **Tapping flips it** to the answer (3D flip). The user may grade from either side.
- **Swipe right / "Vím"** = Know → FSRS rating **Good (3)**.
- **Swipe left / "Nevím"** = Don't know → FSRS rating **Again (1)**.
- **"Přeskočit"** = Skip → no points, no FSRS rating, nothing sent to the server. The card moves to the end of the current session queue.
- **Vím / Nevím / Přeskočit buttons** are shown in addition to swipes.
- A card answered **"Nevím"** is added once more to the end of the same session. The second answer is a normal review.
- The session screen shows "Karta X z Y", points earned this session, the current multiplier, and what each answer is worth ("← Nevím · +2 | Vím · +11 →").
- **End screen ("Hotovo")** shows: cards done, % correct, points earned with a breakdown, new balance, streak update, and progress toward the nearest wishlist item.

### 5.3 FSRS (spaced repetition)
- Runs **on the server**. Implement **FSRS-6**, ported from **py-fsrs 6.3.2**, with **default parameters**, **desired retention 0.9** and **fuzz off**. Exact rules: [`docs/spec.md`](./docs/spec.md) §3; reference vectors in `docs/fsrs/`.
- Port carefully and **unit-test against reference values** produced by the reference implementation.
- Only two ratings are used: **Again (1)** and **Good (3)**.
- Per user × card store: state (Learning / Review / Relearning; a card with no stored state is New), stability, difficulty, due, last review, reps, lapses, plus anything the chosen FSRS version needs (e.g. learning step).
- Keep every review in `ReviewLog` for stats and possible future parameter optimization.

### 5.4 Points
- **Know: 10 × multiplier. Don't know: 2 × multiplier. Skip: 0.**
- **Rounding:** to the nearest integer, halves away from zero (2 × 1.1 = 2.2 → **2**; 10 × 1.1 → **11**). Confirmed at the Etapa 0 gate.
- **Multiplier** = `min(2.0, 1.0 + 0.1 × floor(streak / 7))`. `streak` is the current streak at the moment of the review; today counts once today's goal has been reached.

```
points = round(base × min(2.0, 1.0 + 0.1 × floor(streakDays / 7)))
```

- **Milestone bonuses** (not multiplied): 7 days **+50**, 30 days **+200**, 100 days **+1 000**, 365 days **+5 000**. They are awarded when the streak reaches the milestone, and a new streak can earn them again.
- Points are a **ledger** (`PointsEntry`); balance = sum of entries. Reasons: `review`, `milestone`, `claim`, `refund`. A cached balance is allowed, but the ledger is the truth.
- Everything is **calculated on the server**. The app only displays server values.

### 5.5 Daily goal and streak
- **A day** is a calendar day in **Europe/Prague** (midnight to midnight, DST-aware), always computed explicitly regardless of server timezone.
- **Daily goal** ("Denní cíl", user setting, default **20**) = number of **graded answers** (Vím or Nevím; skips don't count) across all decks that day.
- A day is **met** when graded answers ≥ goal. Changing the goal takes effect immediately; a day that is already met stays met (a raised goal applies from tomorrow, a lowered goal can complete today).
- **Streak** = consecutive met days, ending today if today is already met, otherwise ending yesterday. Today isn't lost until the day ends. One fully missed day resets the streak to 0.
- Store the **best streak** (record) per user.

### 5.6 Shop and claims
- **Items** are real-life rewards (e.g. "Jít na pizzu") with name, description, price in points, **stock**, active flag and sort order. **No cooldowns.** Stock 1 means the item can be claimed only once.
- **One shared shop**; each user has their own balance.
- **Claim** requires balance ≥ price and stock ≥ 1. In **one DB transaction**: create `Claim(Pending)`, add `PointsEntry(−price, claim)`, decrement stock. Prevent overselling with a row lock or optimistic concurrency.
- The **admin confirms** a claim (Confirmed, final) **or rejects** it (Rejected → `PointsEntry(+price, refund)` and stock +1).
- **Sold out** (stock 0): the item stays visible as **"Vyprodáno"** and can't be bought. **Inactive** items are hidden in the app.
- **Wishlist ("Seznam přání"):** the user hearts items. The app shows progress toward them and sends a notification when the balance first reaches a wishlist item's price.
- **"Moje nákupy"** shows the user's claims with a status: *Čeká na schválení / Schváleno / Zamítnuto (body vráceny)*.

### 5.7 Users and authentication
- **Admin:** a single account whose username and password come from env vars (`ADMIN_USERNAME`, `ADMIN_PASSWORD`; the password is hashed in memory at startup). Dashboard only, cookie auth, login page `/admin/login`, rate-limited.
- **App users** are created by the admin (username, display name, password, default daily goal and new cards per day). **No self-registration.** Usernames are lowercase letters and digits, unique.
- **Login:** username + password → **access token** (JWT, ~60 min) + **refresh token** (rotating, ~90 days, stored hashed in the DB). The app keeps tokens in secure storage, and the user **stays logged in until logout**.
- The admin can **reset a password** (generates a new one, shown once) and **deactivate or activate** a user. A deactivated user can't log in or refresh.
- A user can **change their own password** in Nastavení (current + new, 8–128 chars). Every other device is signed out; this one stays logged in. A forgotten password is still reset by the admin.
- Hash passwords with ASP.NET Core `PasswordHasher<T>`. Rate-limit `/api/auth/login`.

### 5.8 Notifications (local, scheduled on the phone)
- Use `flutter_local_notifications`. Request `POST_NOTIFICATIONS` on Android 13+. Prefer **inexact** scheduling; use exact alarms only if needed and handle the Android 12/14 permission rules.
- **Texts come from the API** (`GET /api/notification-texts`), are cached on the device, and are picked at random per category, avoiding recent repeats.
- **Tone:** warm, friendly, supportive, **emoji welcome**, **never guilt-tripping**, gender-neutral. Examples:
  - "Zvládneš to! Věřím ti ❤️"
  - "Jde ti to skvěle! 💪 Už máš {done} z {goal}. Dáme ještě kousek spolu?"
  - "Dobré ráno! ☀️ Karty na dnešek: {due}. Uvař si kafe a pojďme na to spolu ☕"
  - "{streak} dní v řadě! 🎉 Tohle je paráda, máš můj obdiv!"
  - "Vítej zpátky 💚 Série se přerušila, to se stává každému. Začneme znovu, spolu to dáme!"
- **Czech plurals:** a number placeholder goes where the grammar doesn't depend on the number (after a colon, in "{done} z {goal}"), because 1 karta · 2 karty · 5 karet. Rules: `docs/notification-texts.md`.
- **Placeholders:** `{due}`, `{left}` (cards left to the goal), `{done}`, `{goal}`, `{streak}`, `{multiplier}`, `{item}`, `{points}`. If a value is unknown, pick a text in the same category without placeholders.
- **≥ 50 texts** are written in Etapa 1 (`docs/notification-texts.md`), seeded into the DB, and editable by the admin.

| Category | When it fires |
| --- | --- |
| `morning` | Daily at the user's morning time (default 08:00), with the due count |
| `evening` | At the user's evening time (default 18:30), only if the goal isn't met yet |
| `last_call` | At 21:00 (setting) if the goal isn't met and streak > 0 |
| `milestone` | Right after the streak reaches 7 / 30 / 100 / 365 days |
| `wishlist` | When the balance first reaches a wishlist item's price |
| `comeback` | The next morning after a streak breaks |

- Reaching the daily goal **cancels** today's `evening` and `last_call`.
- **Quiet hours** (default 22:00–07:00): nothing is shown, and anything scheduled inside them is skipped.
- **"Chytré časy"** (smart times, default on): the evening reminder moves toward the user's typical study time (median session start over the last 14 days, rounded to 15 min, clamped to 17:00–20:30).
- Background refresh (WorkManager, ~daily) updates due counts and texts so notifications stay accurate when the app isn't opened.

### 5.9 Stats screen ("Statistiky", phone)
- **Tiles:** current streak + record, success rate over the last 30 days with a sparkline, total reviews, total points earned.
- **Activity heatmap:** last 17 weeks, Monday-first columns. Levels relative to the user's goal: 0 none · 1 below goal · 2 goal to 1.25× · 3 1.25 to 1.5× · 4 above 1.5×. Today is outlined.
- **Cards per day:** last 14 days as bars, with a dashed goal line.
- **"Kdy ti to jde nejlíp":** success % per weekday, plus the best 2-hour time window (with a minimum sample size).
- **Deck progress:** share of *Zvládnuto* (FSRS Review state with stability ≥ 21 days), *Učím se* (Learning/Relearning, or Review with stability < 21 days) and *Nové* (never reviewed).
- **Filter:** all decks or one deck.

### 5.10 Admin dashboard (`/admin`, Blazor, Czech)
- **Přehled:** tiles (pending claims, users active today, reviews today + success, points in the last 7 days); pending claims table with **Schválit / Zamítnout**; "Uživatelé dnes" table (streak + multiplier, today's goal progress, points, last active); quick actions.
- **Balíčky:** deck list; deck detail with tabs **Karty** (cards CRUD), **YAML** (§8), **Nastavení** (name, description, color, order, delete).
- **Obchod:** items table (price, stock left of initial, pending, on wishlists, status); edit form; **purchase history** with filters (Vše / Čeká / Schváleno / Zamítnuto) and actions on pending claims.
- **Uživatelé:** table (username, display name, points, streak + record, total reviews, success, last active); actions **Upravit / Reset hesla / Aktivovat–Deaktivovat**; new-user form (generated password shown once, default goal, new cards per day).
- **Texty upozornění:** texts per category; add / edit / delete / activate; preview with sample placeholder values.
- The layout is responsive: the sidebar stacks on narrow screens.

### 5.11 Connectivity and sync
- **An internet connection is required.** The server is the source of truth for progress, points, streaks and stats.
- The app gets the session from the server and posts reviews in small batches (after each card, or every few cards). Each review carries a **client-generated UUID** (idempotency), so retries never award points twice.
- The server uses its **receive time** for the review timestamp and the day boundary.
- On transient errors the app retries. When offline it shows "Jsi offline" and pauses the session.

---

## 6. Data model (EF Core / PostgreSQL)

Integer identity keys, except `ReviewLog.Id`, which is the client UUID. Timestamps are UTC (`timestamptz`); day-level dates are Prague `date`. Final types, constraints and indexes are in [`docs/spec.md`](./docs/spec.md) §2.

| Entity | Fields | Notes |
| --- | --- | --- |
| `User` | Id, Username (unique), DisplayName, PasswordHash, IsActive, CreatedAt, LastActiveAt, CurrentStreak, BestStreak, LastGoalMetDate | streak fields are a cache derived from DailyActivity |
| `UserSettings` | UserId (PK/FK), DailyGoal = 20, NewCardsPerDay = 5, NotificationsEnabled, MorningTime = 08:00, EveningTime = 18:30, LastCallTime = 21:00, QuietFrom = 22:00, QuietTo = 07:00, SmartTimes = true | 1:1 with User |
| `RefreshToken` | Id, UserId, TokenHash, ExpiresAt, CreatedAt, RevokedAt, ReplacedById | rotation |
| `Deck` | Id, Name, Description, Color, SortOrder, CreatedAt, UpdatedAt | |
| `Card` | Id, DeckId, Question, Answer, SortOrder, CreatedAt, UpdatedAt | Id is the stable id used in YAML |
| `CardState` | (UserId, CardId) PK, State, Stability, Difficulty, Due, LastReview, FirstReview, Reps, Lapses, Step | FSRS memory state; no row = new card |
| `ReviewLog` | Id (uuid from client), UserId, CardId, Rating, StateBefore, ReviewedAt, Day, Multiplier, PointsAwarded, ElapsedDays, ScheduledDays | append-only |
| `DailyActivity` | (UserId, Date) PK, GradedCount, CorrectCount, Points, Goal, GoalMet, GoalMetAt | updated on each review; drives streak, heatmap, charts |
| `PointsEntry` | Id, UserId, Amount, Reason, ReferenceId, CreatedAt | balance = SUM(Amount) |
| `ShopItem` | Id, Name, Description, Price, InitialStock, Stock, IsActive, SortOrder, concurrency token | |
| `Claim` | Id, UserId, ShopItemId, RequestId (uuid from client), Price, Status (Pending/Confirmed/Rejected), CreatedAt, DecidedAt | RequestId makes a retried claim safe |
| `WishlistEntry` | (UserId, ShopItemId) PK, CreatedAt, NotifiedAt | |
| `NotificationText` | Id, Category, Text, IsActive, CreatedAt, UpdatedAt | seeded with ≥ 50 texts |

Deleting a card cascades to its `CardState` and `ReviewLog`. The admin UI warns about this (§8).

---

## 7. REST API

Full contract with examples, error codes and the sync rules: [`docs/api.md`](./docs/api.md). Overview:

Everything is under `/api`: JSON, camelCase, errors as RFC 7807 ProblemDetails. OpenAPI/Swagger at `/api/docs` (Development, or behind admin auth in Production). Timestamps are ISO 8601 UTC; days are `YYYY-MM-DD` in Europe/Prague.

**App endpoints** (JWT bearer):

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/api/auth/login` | username + password → access + refresh token |
| POST | `/api/auth/refresh` | rotate the refresh token |
| POST | `/api/auth/logout` | revoke the refresh token |
| GET | `/api/me` | profile, balance, streak, best streak, multiplier, today's progress |
| GET / PUT | `/api/me/settings` | user settings (§6 UserSettings) |
| POST | `/api/me/password` | change my password (current + new) → new token pair, other devices signed out |
| GET | `/api/decks` | decks with counts: total, due now, new available, % mastered |
| GET | `/api/decks/{id}/cards` | one deck with counts and every card (question, answer, my status: new / learning / mastered) |
| GET | `/api/session?deckId={id}` | session queue (omit `deckId` for all decks) |
| POST | `/api/reviews` | batch `[{ id: uuid, cardId, rating: "know" \| "dontKnow" }]` → points per review + updated summary (balance, streak, multiplier, today, milestone events) |
| GET | `/api/stats?deckId={id}` | tiles, heatmap, daily bars, weekday, best time, deck progress |
| GET | `/api/shop` | items with stock and wishlist flags, plus balance |
| POST | `/api/shop/{itemId}/claim` | create a claim |
| GET | `/api/claims` | my claims |
| PUT / DELETE | `/api/wishlist/{itemId}` | add to / remove from wishlist |
| GET | `/api/notification-texts` | active texts grouped by category (ETag) |
| GET | `/api/health` | health check (no auth) |

**Admin endpoints** (`/api/admin/*`, admin auth) mirror the dashboard: `users` (+ `reset-password`, `activate`, `deactivate`), `decks`, `decks/{id}/cards`, `decks/{id}/yaml` (GET export, POST preview, PUT apply), `shop-items`, `claims` (+ `confirm`, `reject`), `notification-texts`, `overview`.
Blazor pages call the **application services directly**; the REST endpoints use the same services.

---

## 8. Deck YAML format (v1)

```yaml
# Quizly balíček · formát v1
deck:
  name: C# základy
  description: Základní pojmy jazyka C#
  color: "#BAD69B"
cards:
  - id: 101
    question: Jaký je rozdíl mezi struct a class v C#?
    answer: struct je hodnotový typ, class je referenční typ.
  - id: 102
    question: Co dělá klíčové slovo async?
    answer: |
      Označí metodu, ve které můžeš použít await.
      Metoda pak vrací Task.
  - question: Co je record v C#?          # no id = new card
    answer: Typ s hodnotovou rovností pro neměnná data.
```

**Rules**
- **Export** always includes `id` on every card. File order = card sort order.
- **Import is always a preview (dry run) first.** It shows counts and lists of *new / changed / deleted / unchanged* cards, plus **validation errors with line numbers**. Errors block saving.
- Validation covers: invalid YAML, missing `question` or `answer`, duplicate `id`, an `id` that belongs to another deck, unknown keys, text over the length limit.
- A card **with an `id`** is updated and users' progress is kept. A card **without an `id`** becomes a new card.
- An existing card whose `id` is **missing from the YAML is deleted together with all users' progress**. This needs an **explicit confirmation** that lists those cards ("Smazat 3 karty i s postupem uživatelů?").
- `deck:` fields update the deck. Multiline text uses YAML block scalars (`|`). Plain text only.
- Use YamlDotNet; keep UTF-8 Czech characters intact.
- "Importovat YAML" on the deck list creates a **new deck** from a file whose cards have no ids.
- Workflow: copy the YAML out → let an AI agent add or edit cards (it must keep the `id`s) → paste it back → preview → save.

---

## 9. Design

**Reference:** the Design canvas "Quizly — Design Proposal" on claude.ai (`https://claude.ai/artifact/6CoK7qTg7jdSzq2MYzoq2a`, private to Jakub) has 10 phone screens and 4 admin pages. A saved copy is in the repo at [`docs/design/quizly-design-proposal.html`](./docs/design/quizly-design-proposal.html) (open it in a browser). The admin **Texty upozornění** page, missing from the canvas, is in [`docs/design/admin-texty-upozorneni.html`](./docs/design/admin-texty-upozorneni.html). If you can't open either, this section has everything you need.

### 9.1 Phone (dark theme)

| Token | Value | Use |
| --- | --- | --- |
| `bg` | `#111218` | screen background |
| `surface` | `#1B1D27` | cards, panels |
| `surface2` | `#252836` | chips, stepper buttons, pills |
| `border` | `#2F3242` | 1 px borders, dividers |
| `text` | `#F4F2EC` | primary text |
| `textMuted` | `#A0A4B5` | secondary text |
| **`primary`** | **`#BAD69B`** | **main color**: CTA buttons, active nav, streak, progress, Know, toggles, logo |
| `onPrimary` | `#15200C` | text and icons on primary |
| `primaryLight` | `#D9EBC6` | hover / pressed accents |
| `dontKnow` | `#FF8A8A` | Nevím, destructive (logout) |
| `points` | `#FFCB52` | points, balance, wishlist |
| `multiplier` | `#C4BAFF` | multiplier chip, "Učím se" |
| `info` | `#8FC7F0` | secondary deck color, milestone tag |
| `cardFace` | `#F4F2EC` with text `#111218` | flashcard face |

Heatmap levels: `#252836`, `#33402A`, `#4F6A3A`, `#7FA05E`, `#BAD69B`.

### 9.2 Admin (light theme)
bg `#F5F4F0` · surface `#FFFFFF` · border `#E3E1DA` · text `#16171D` · muted `#5E6170` · sidebar `#16171D` (active item `#2A2C38` + primary text) · primary buttons `#BAD69B` with text `#15200C` · bars and stripes on light backgrounds `#8FB06A` · links `#4F6B33` (hover `#3B5226`).
Status chips: pending `#FFF1D6` / `#8A5300` · confirmed `#E3F4E6` / `#1F7A3A` · rejected `#FDE8E6` / `#B42318`.

### 9.3 Type, shape, motion
- **Fonts:** *Bricolage Grotesque* (headings, big numbers), *Manrope* (body), *JetBrains Mono* (YAML editor). All support Czech diacritics. **Bundle them** in the app.
- Radii: cards 20–28 px, buttons 14–20 px. Touch targets ≥ 44 px. Text contrast ≥ 4.5:1.
- Icons: simple stroke icons (Lucide or Material Symbols Rounded). Emoji appear **only inside text** (notifications, celebrations), never as UI icons.
- **Animations are part of the motivation:** 3D card flip; swipe with rotation and a "VÍM" / "NEVÍM" stamp; floating "+11" points; rolling counters; confetti on reaching the goal or a milestone; streak flame pulse; goal ring fill. Respect the system "reduce motion" setting.

### 9.4 Phone screens
1. **Přihlášení:** logo, username, password with show toggle, "Přihlásit se", note "Účet ti založí správce aplikace. Zapomenuté heslo ti také resetuje správce."
2. **Domů:** date + greeting, points pill (→ shop), streak card (days, multiplier, Mon–Sun week strip, "Za 2 dny násobič stoupne na 1,2×"), daily goal ring `13/20`, CTA **"Učit se vše · 23 karet"**, deck list (due count, mastered bar; tap → deck detail). Bottom nav: **Domů / Statistiky / Obchod / Nastavení**.
   - **Balíček** (deck detail, added after the canvas): name, description, tiles (cards, due, new today, % mastered), **"Učit se · N karet"**, and every card with a status chip (*Nová / Učím se / Zvládnuto*); tapping a card shows its answer.
3. **Učení, otázka:** close button, progress bar "Karta 8 z 23", session points, deck/mode/multiplier chips, card stack, hint row, buttons **Nevím / Přeskočit / Vím**.
4. **Učení, odpověď:** flipped card mid-swipe with the "VÍM" stamp and floating "+11".
5. **Hotovo:** streak circle, **"Denní cíl splněn!"**, tiles (cards, % correct, points), points breakdown, new balance, wishlist progress card, "Učit se dál" / "Hotovo".
6. **Statistiky:** see §5.9.
7. **Obchod:** balance, "Šetříš na" wishlist card, tabs **Odměny / Moje nákupy**, item grid (name, stock line, price, **Koupit** or "Chybí X" / "Vyprodáno", heart), my claims with status chips.
8. **Potvrzení nákupu** (bottom sheet): title, description, price / balance / after purchase, info that points are deducted now and the admin approves; **Zrušit / Koupit za X**.
9. **Nastavení:** account ("Tvůj účet"), **Změnit heslo** (current, new, new again), **Denní cíl** stepper, **Nové karty denně** stepper, notifications toggle, morning / evening / last-call times, quiet hours, **Chytré časy** toggle, "Odhlásit se", version.
10. **Upozornění:** examples of every notification category (§5.8).

### 9.5 Czech UI glossary (use these exact terms)
Balíček (deck) · Karta · Vím · Nevím · Přeskočit · Série (streak) · Násobič (multiplier) · Denní cíl · Body · Obchod · Odměna · Seznam přání · Moje nákupy · Čeká na schválení · Schváleno · Zamítnuto · Vyprodáno · Statistiky · Nastavení · Upozornění · Tichý režim · Chytré časy · Přehled · Uživatelé · Texty upozornění.

---

## 10. Deployment

- `deploy/docker-compose.yml`: service **`quizly`** (`ghcr.io/<owner>/quizly:<tag>`) and **`db`** (`postgres:18`), named volume for the database, internal network. `quizly` publishes one port (e.g. 8080) for Nginx Proxy Manager.
- `deploy/.env.example`: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `ConnectionStrings__Default`, `Jwt__SigningKey` (≥ 32 random bytes), `Jwt__Issuer`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`, `PUBLIC_BASE_URL=https://quizly.jbohacek.cz`.
- Behind the proxy: enable **ForwardedHeaders** (X-Forwarded-For/Proto). Persist **Data Protection keys** to a volume (Blazor circuits and cookies must survive restarts).
- Migrations run on startup. Health check at `/api/health`.
- **Backups:** `deploy/backup.sh` runs a nightly `pg_dump` and keeps 14 days, with restore steps in `deploy/README-deploy.md`.
- **Updates:** a new image tag → Jakub pulls and redeploys the stack in Portainer.
- Nginx Proxy Manager forwards `quizly.jbohacek.cz` (HTTPS, Let's Encrypt) to the `quizly` port, with websockets enabled (Blazor Server needs them).

---

## 11. CI/CD (GitHub Actions)

- **`api.yml`:** on PR → restore, build, test. On push to `main` → build and push the Docker image to GHCR (tags: commit SHA + `latest`).
- **`app.yml`:** on PR → `flutter analyze` + `flutter test`. On push to `main` or a tag → build a **release APK signed with a fixed keystore** from GitHub Secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`), upload it as an artifact, and attach it to the GitHub Release on tags.
  The **same key on every build**, so a new APK installs over the old one without losing the login.
- The API base URL is passed at build time: `--dart-define=API_BASE_URL=https://quizly.jbohacek.cz`.

---

## 12. Flutter app guidelines

Final package list and structure: [`docs/architecture.md`](./docs/architecture.md) §3.

- Packages: `flutter_riverpod` (state), `go_router` (routing), `dio` (HTTP with an auth interceptor that refreshes on 401), `flutter_secure_storage` (tokens), `flutter_local_notifications` + `timezone`, `workmanager` (background refresh), `fl_chart` (charts), `flutter_animate` (animations), `confetti`.
- Structure: `lib/core/` (api client, theme tokens, models, strings) and feature folders `auth`, `home`, `session`, `stats`, `shop`, `settings`, `notifications`.
- All UI strings live in **one Czech strings file**; no i18n framework.
- Keep notification scheduling logic in pure Dart so it can be unit-tested.

---

## 13. Open decisions and unconfirmed assumptions

Jakub confirmed these defaults at the Etapa 0 gate (2026-10-31). Raise any of them again in Etapa 1 if the spec work shows a problem.

| # | Topic | Default |
| --- | --- | --- |
| 1 | Points rounding | nearest integer, halves away from zero |
| 2 | YAML import deleting cards | allowed, with explicit confirmation |
| 3 | Manual points adjustment by admin | not in scope |
| 4 | Vím / Nevím buttons next to swipes | keep |
| 5 | Re-show a "Nevím" card once later in the same session | yes |
| 6 | Milestone bonus amounts / re-earnable per new streak | 50 / 200 / 1 000 / 5 000; yes |
| 7 | Minimum Android version | 8.0 (API 26); check against Jakub's phone |
| 8 | Daily goal counts graded answers across all decks | yes |
| 9 | Assumptions from the plan: server-side calculation, Prague midnight, multiplier only on card points, claims reserve points and stock, sold-out items stay visible, admin resets passwords, GHCR, APK via Actions | as written above; confirmed at the Etapa 0 gate |

---

## 14. Decisions log

| Date | Decision |
| --- | --- |
| 2026-10-31 | Requirements gathered; stack (ASP.NET Core 10 + Blazor, PostgreSQL, Flutter, Docker/Portainer, NPM) and stages agreed. |
| 2026-10-31 | Single admin from env vars; app users created by admin; username + password; stay logged in. |
| 2026-10-31 | Every user sees every deck; deck editing via YAML; AI deck builder later. |
| 2026-10-31 | Shop = real-life rewards with stock, no cooldowns; every claim needs admin confirmation. |
| 2026-10-31 | Notifications are local on the phone; texts editable on the dashboard. |
| 2026-10-31 | Main color `#BAD69B`; notifications warm and friendly with emoji, gender-neutral Czech. |
| 2026-10-31 | Design proposal canvas created (10 phone screens, 4 admin pages), awaiting approval. |
| 2026-10-31 | Repo is `Jbohacek/Quizly`. Line endings are LF everywhere (`.gitattributes`, `.editorconfig`), except `.cmd`/`.bat`/`.ps1`. |
| 2026-10-31 | Saved copy of the design proposal committed to `docs/design/quizly-design-proposal.html`. |
| 2026-10-31 | Etapa 0 approved by Jakub; plan and §13 defaults confirmed as written. |
| 2026-10-31 | FSRS-6 (py-fsrs 6.3.2 port), fuzz off. |
| 2026-10-31 | A met day stays met when the goal is raised; the new goal applies from tomorrow. Lowering it can complete today. |
| 2026-10-31 | Admin "Texty upozornění" designed as a standalone mockup in `docs/design/` (the canvas stays unchanged). |
| 2026-10-31 | Etapa 1 spec: PostgreSQL 18, snake_case naming; data model additions `card_states.first_review`, `review_logs.state_before/day`, `daily_activities.goal_met_at`, `claims.request_id` (idempotent claims). |
| 2026-10-31 | Points use the streak just before the review; the review that meets the goal still uses the old multiplier. |
| 2026-10-31 | Notifications use inexact scheduling only (no exact-alarm permission); the planner is pure Dart. |
| 2026-10-31 | Refresh-token rotation has a 60 s retry grace so flaky networks don't log the user out. |
| 2026-10-31 | Number placeholders in notification texts are placed so Czech plurals stay correct; the §5.8 examples were rephrased accordingly. |
| 2026-10-31 | The wishlist "reached" event is checked in review and settings responses only (a refund's event arrives with the next review). |
| 2026-10-31 | Etapa 1 approved and merged (PR #1). |
| 2026-10-31 | Swagger UI is a small page loading `swagger-ui-dist` from a CDN over the built-in OpenAPI document; no Swashbuckle (known issues on .NET 9+). |
| 2026-10-31 | `POST /api/admin/auth/login` sets the admin cookie for REST and Swagger use until the Blazor login page exists (Etapa 4). |
| 2026-10-31 | Tests run on Microsoft.Testing.Platform (xUnit v3, `global.json` `test.runner`), integration tests on PostgreSQL 18 via Testcontainers. |
| 2026-10-31 | Time comes from the .NET `TimeProvider` (tests use `FakeTimeProvider`) instead of a custom `IClock`. |
| 2026-10-31 | Data Protection keys persist to `/data/keys` (volume) already in Etapa 2, because the admin cookie needs them. |
| 2026-10-31 | Etapa 2 approved and merged (PR #2). |
| 2026-10-31 | JWT lifetimes are validated with the injected `TimeProvider`, the same clock that issues them. |
| 2026-10-31 | Any existing card may be answered via `POST /api/reviews`; the new-card allowance only shapes the session queue. |
| 2026-10-31 | A repeated claim `requestId` returns 200 with the original claim; a new claim returns 201. |
| 2026-10-31 | `GET /api/decks` and admin `GET/POST /api/admin/claims[/{id}/confirm\|reject]` are built in Etapa 3 with the logic they expose. |
| 2026-10-31 | Etapa 3 approved and merged (PR #3). |
| 2026-10-31 | Dashboard routes: `/admin`, `/admin/balicky[/{id}]`, `/admin/obchod`, `/admin/uzivatele`, `/admin/texty-upozorneni`; login is a static server-rendered form, the rest Interactive Server. |
| 2026-10-31 | Dashboard pages open a fresh DI scope (DbContext) per operation; a circuit-long DbContext would show stale data. |
| 2026-10-31 | Default auth scheme forwards by path: `/api/*` → JWT, everything else → admin cookie. |
| 2026-10-31 | YAML export writes multi-line text as `\|-` and quotes values other tools could read as numbers/booleans/null. |
| 2026-10-31 | Fonts are bundled from the saved design (OFL, `wwwroot/fonts/LICENSES.txt`). Npgsql GSS encryption is disabled (password auth only). |
| 2026-11-01 | Etapa 4 approved and merged (PR #4). Live at `https://quizly.jbohacek.cz` (NPM → host port 8181 → container 8080). |
| 2026-11-01 | App: Flutter 3.47 / Dart 3.13, Riverpod 3, go_router 18, application id `cz.jbohacek.quizly`. `versionCode` = CI run number, `versionName` from `pubspec.yaml`. |
| 2026-11-01 | App fonts are static TTF weights cut from the Google Fonts variable fonts (OFL); the design bundle only has woff2, and Flutter doesn't map `FontWeight` to a variable `wght` axis. |
| 2026-11-01 | Nastavení shows "Tvůj účet" instead of "Přihlášen jako" (gendered past participle, §2.11). |
| 2026-11-01 | Jakub (Etapa 5 review): users can change their own password, and can browse a deck's cards. `POST /api/me/password` deletes the user's refresh tokens (deleted, not revoked, so another device's next refresh isn't taken for token theft) and returns a new pair; wrong current passwords count toward the login throttle. `GET /api/decks/{id}/cards`; tapping a deck on Domů opens its detail instead of starting a session; answers are hidden until a card is tapped. |
| 2026-11-01 | Until Etapa 6 the Statistiky and Obchod tabs show an "Už brzy" placeholder; the home week strip, floating "+N", confetti and wishlist card on Hotovo come with Etapa 6. |
| 2026-11-01 | Plain HTTP only in debug builds (local API); release builds are HTTPS only. `android:allowBackup="false"` (Keystore-encrypted tokens can't be restored on another device). |
| 2026-11-01 | `flutter_localizations` is used only for Material's own Czech texts (text selection menu etc.); all app strings stay in `lib/core/strings.dart`. |
| 2026-11-01 | Etapa 5 approved and merged (PR #5); signing secrets in place, release APK builds on `main`. |
| 2026-11-01 | Etapa 6 needs no API change. The Domů week strip comes from the current week of the `/api/stats` heatmap (level 2+ = goal met), loaded with Domů; it's left out if the stats fail. |
| 2026-11-01 | "Šetříš na" (Obchod and Hotovo) shows the hearted reward with the fewest points missing; when every hearted reward is affordable, the cheapest one with "Už na to máš!". A reward reached during the session wins on Hotovo. Its "pošleme ti upozornění" sentence comes with the notification in Etapa 7. |
| 2026-11-01 | Hotovo says "to je zhruba N × Vím" (points missing ÷ the current Vím value) instead of the canvas's "zítra N karty", which assumed tomorrow's multiplier. |
| 2026-11-01 | "Kdy ti to jde nejlíp" shows the best weekday and the best 2-hour window as two sentences (they're independent stats); the canvas's "Připomínky se tomu přizpůsobí" is left out, since Chytré časy use the median start time. |
| 2026-11-01 | Obchod: tapping a reward card also opens the purchase sheet (it shows the description); after a purchase the Moje nákupy tab opens. Price and button sit on separate rows, because "Chybí 1 436" doesn't fit next to the price on a phone. |
| 2026-11-01 | Motion: the streak flame breathes while a streak is going, confetti plays when the goal or a milestone is reached in a session. All animations (and the floating "+N") are off with the system's reduce-motion setting. |
