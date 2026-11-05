# Quizly REST API (v1)

Base URL: `https://quizly.jbohacek.cz/api`. Rules behind the numbers are in [`spec.md`](./spec.md).

## 1. General

- JSON, camelCase, UTF-8. Instants ISO 8601 UTC (`2026-11-02T07:10:00Z`); days `YYYY-MM-DD` (Prague); times of day `HH:mm`.
- App endpoints need `Authorization: Bearer <accessToken>`. Admin endpoints use the admin cookie (§12).
- Numbers are raw (`1457`, `1.1`). The app formats them in Czech (`1 457`, `1,1×`).
- OpenAPI document at `/api/openapi/v1.json`, Swagger UI at `/api/docs` (open in Development, admin cookie everywhere else). The UI page loads `swagger-ui-dist` from jsDelivr.
- JSON input is strict: exact camelCase names, no numbers in strings, no duplicate properties, required fields must be present. An unreadable body is `400 validation`.

### 1.1 Errors (RFC 7807 ProblemDetails)

```json
{
  "type": "https://quizly.jbohacek.cz/problems/insufficient-balance",
  "title": "Na tuhle odměnu ti zatím chybí body.",
  "status": 409,
  "code": "insufficientBalance",
  "traceId": "00-4bf9…-01"
}
```

`title` is a Czech message the app may show as is. `code` is stable and the app switches on it. Validation errors add `errors`:

```json
{
  "type": "https://quizly.jbohacek.cz/problems/validation",
  "title": "Některé údaje nejsou v pořádku.",
  "status": 400,
  "code": "validation",
  "errors": { "dailyGoal": ["Denní cíl musí být mezi 1 a 500."] }
}
```

| Code | Status | When |
| --- | --- | --- |
| `validation` | 400 | input fails the rules in spec §8 |
| `unauthorized` | 401 | missing, invalid or expired access token; admin endpoint without the admin cookie |
| `invalidCredentials` | 401 | wrong username or password |
| `accountDisabled` | 401 | user is deactivated (login, refresh, any call) |
| `refreshTokenInvalid` | 401 | unknown, expired, revoked or reused refresh token |
| `forbidden` | 403 | authenticated, but not allowed (reserved) |
| `notFound` | 404 | resource doesn't exist (or is an inactive shop item for the app) |
| `soldOut` | 409 | claim with stock 0 |
| `insufficientBalance` | 409 | claim with balance < price |
| `itemInactive` | 409 | claim on an inactive item |
| `claimNotPending` | 409 | confirm/reject a decided claim |
| `concurrencyConflict` | 409 | admin edit of a row changed meanwhile, or YAML base changed |
| `hasClaims` | 409 | deleting a shop item with claims |
| `yamlInvalid` | 422 | YAML preview/apply has errors (body lists them) |
| `deleteNotConfirmed` | 422 | YAML apply deletes cards that weren't confirmed |
| `unsupportedMediaType` | 415 | admin write whose body isn't `application/json` |
| `rateLimited` | 429 | rate limit hit; `Retry-After` header in seconds |
| `serverError` | 500 | unexpected; logged with `traceId` |

### 1.2 Shared objects

**Summary** (returned by `/me`, `/reviews`, settings updates):

```json
{
  "balance": 1457,
  "streak": 13,
  "bestStreak": 21,
  "multiplier": 1.1,
  "nextMultiplier": { "value": 1.2, "inDays": 1 },
  "today": { "date": "2026-11-02", "graded": 13, "correct": 11, "goal": 20, "goalMet": false, "points": 125 },
  "streakBroken": null
}
```

- `nextMultiplier` is `null` at 2.0×.
- `streakBroken` is `{ "previousStreak": 12, "brokenOn": "2026-11-04" }` when the streak was lost (spec §5.5), else `null`.

**Event** (in review and settings responses):

```json
{ "type": "goalMet" }
{ "type": "milestone", "days": 7, "bonus": 50 }
{ "type": "wishlistReached", "itemId": 3, "name": "Jít na pizzu", "price": 1500 }
```

---

## 2. Auth

### POST `/auth/login`

```json
{ "username": "jakub", "password": "••••••••", "deviceName": "Pixel 8" }
```

`200`:

```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIs…",
  "accessTokenExpiresAt": "2026-11-02T08:10:00Z",
  "refreshToken": "kQ3n…base64url…",
  "refreshTokenExpiresAt": "2027-01-31T07:10:00Z",
  "user": { "id": 2, "username": "jakub", "displayName": "Jakub", "shopEnabled": true }
}
```

Errors: `validation`, `invalidCredentials`, `accountDisabled`, `rateLimited`. `deviceName` is optional, used only in logs.

### POST `/auth/refresh`

`{ "refreshToken": "kQ3n…" }` → `200` same shape as login. Errors: `refreshTokenInvalid`, `accountDisabled`, `rateLimited`. Rotation, retry grace and reuse detection: spec §9.1.

### POST `/auth/logout`

`{ "refreshToken": "kQ3n…" }` → `204`. Always `204`, even for an unknown token. Needs no access token.

---

## 3. Me

### GET `/me`

```json
{
  "user": { "id": 2, "username": "jakub", "displayName": "Jakub", "shopEnabled": true },
  "summary": { "…": "Summary, §1.2" },
  "dueNow": 23,
  "forecast": { "nextMorning": "2026-11-03T07:00:00Z", "dueByNextMorning": 31 },
  "smartEveningTime": "19:15",
  "serverTime": "2026-11-02T16:40:12Z"
}
```

- `dueNow` = due cards + `min(unseen cards, remaining new-card allowance)`, i.e. the length of the "Učit se vše" queue.
- `forecast.dueByNextMorning` = cards with `due ≤` the next morning time + tomorrow's new-card allowance (`min(newCardsPerDay, unseen cards)`). For the `morning` notification.
- `smartEveningTime`: median start time of study sessions in the last 14 days, rounded to 15 min and clamped to 17:00–20:30. A session starts with a review that follows a ≥ 30 min gap. `null` with fewer than 3 sessions. Computed even when Chytré časy is off; the phone decides.

### GET `/me/settings`

```json
{
  "dailyGoal": 20, "newCardsPerDay": 5,
  "notificationsEnabled": true,
  "morningTime": "08:00", "eveningTime": "18:30", "lastCallTime": "21:00",
  "quietFrom": "22:00", "quietTo": "07:00",
  "smartTimes": true,
  "fourRatings": false,
  "showInLeaderboard": true
}
```

### PUT `/me/settings`

Body: the full settings object. `200`:

```json
{ "settings": { "…": "…" }, "summary": { "…": "…" }, "events": [ { "type": "goalMet" } ] }
```

Lowering the goal can complete today (spec §5.3), so the response carries a summary and events. Errors: `validation`.

`showInLeaderboard` (#34) may be left out: the stored value stays, so an older app never shows a user who hid themselves.

---

### POST `/me/password`

```json
{ "currentPassword": "••••••••", "newPassword": "••••••••" }
```

`200`: a new token pair, same shape as `/auth/login`. All the user's other refresh tokens are deleted, so every other device is signed out at its next refresh (`refreshTokenInvalid`); this device continues with the returned tokens.

Errors: `validation` (`errors.currentPassword` "Současné heslo nesedí.", `errors.newPassword` length 8–128 or same as the current one), `rateLimited` (wrong current passwords count toward the login throttle per username, spec §9.1).

---

## 4. Decks

### GET `/decks`

```json
{
  "items": [
    { "id": 1, "name": "C# základy", "description": "Základní pojmy jazyka C#", "color": "#BAD69B",
      "totalCards": 120, "dueNow": 14, "newAvailable": 5, "masteredPercent": 38,
      "learningPercent": 25, "unseenCards": 44 }
  ],
  "newAllowanceLeft": 5
}
```

Ordered by deck `sortOrder`. `newAvailable` = `min(unseen cards in the deck, newAllowanceLeft)`. `masteredPercent` / `learningPercent` are the Zvládnuto / Učím se shares (spec §3.5, rounded down); the rest is Nové. `unseenCards` = cards never answered, regardless of the allowance (for "Ještě 5 nových karet"). Decks with 0 cards are included.

---

### GET `/decks/{id}/cards`

```json
{
  "deck": { "id": 1, "name": "C# základy", "…": "same object as in GET /decks" },
  "cards": [
    { "id": 101, "question": "Jaký je rozdíl mezi struct a class v C#?", "answer": "struct je hodnotový typ…", "status": "mastered",
      "masteryPercent": 100, "knowCount": 6, "dontKnowCount": 1, "nextReview": "2026-12-01T08:12:00Z",
      "tags": ["ai_gen", "prednaska_01"] },
    { "id": 140, "question": "Co je record v C#?", "answer": "Typ s hodnotovou rovností…", "status": "new",
      "masteryPercent": 0, "knowCount": 0, "dontKnowCount": 0, "nextReview": null, "tags": [] }
  ]
}
```

Cards in deck order (`sortOrder`, then id). `status` is the mastery bucket (spec §3.5): `new` · `learning` · `mastered`. `masteryPercent` = stability ÷ 21 days (100 once mastered, at most 99 before). `knowCount` / `dontKnowCount` count my correct (Vím, Těžké, Snadné) / Nevím answers, `nextReview` is the card's due time (`null` for a new card). `tags` are the card's tags, sorted (spec §2.5.1; always present, may be empty). `404 notFound` for an unknown deck.

---

### POST `/decks/{id}/cards` · PUT `/decks/{id}/cards/{cardId}` · DELETE `/decks/{id}/cards/{cardId}`

Any user edits the cards of the decks they see (#23), with the dashboard's rules.

```json
{ "question": "Co je record v C#?", "answer": "Typ s hodnotovou rovností.", "tags": ["ai_gen", "prednaska_01"] }
```

- **POST** adds the card at the end of the deck → `201` with the card (`id`, `deckId`, `question`, `answer`, `sortOrder`, `createdAt`, `updatedAt`, `tags`).
- **PUT** changes the text → `200` with the card. Every user's progress on the card is kept.
- **`tags`** is optional: omitted (or `null`) keeps the card's tags (none on a new card), `[]` removes them all, a list replaces them. Names are trimmed, lowercased, de-duplicated and sorted (spec §2.5.1). An invalid name or more than 10 → `400 validation` with `errors.tags`.
- **DELETE** → `204`. The card goes with **every user's progress** on it (spec §2.14); the app asks first.
- Text is trimmed; empty or too long (500 / 2 000) → `400 validation` with `errors.question` / `errors.answer`. A deck the user doesn't see, or a card of another deck → `404 notFound`.

---

## 5. Session

### GET `/session?deckId=1`

Omit `deckId` for "Učit se vše". `extraNew` (0–50, default 0) adds that many new cards over today's allowance ("Ještě 5 nových karet", spec §4.1); out of range → `validation`. `404 notFound` for an unknown deck.

```json
{
  "deckId": 1,
  "multiplier": 1.1,
  "points": { "know": 11, "dontKnow": 2, "hard": 11, "easy": 11 },
  "fourRatings": false,
  "dueCount": 14,
  "newCount": 5,
  "cards": [
    { "cardId": 101, "deckId": 1, "question": "Jaký je rozdíl mezi struct a class v C#?",
      "answer": "struct je hodnotový typ, class je referenční typ.", "kind": "review", "tags": ["ai_gen", "prednaska_01"] },
    { "cardId": 140, "deckId": 1, "question": "Co je record v C#?",
      "answer": "Typ s hodnotovou rovností pro neměnná data.", "kind": "new", "tags": [] }
  ]
}
```

- `kind`: `new` · `learning` · `review` · `relearning`.
- `tags`: the card's tags, sorted (spec §2.5.1). The deck's name comes from `GET /decks` by `deckId`.
- Order is the queue order (spec §4.1). An empty `cards` list means nothing to study.
- `points` are the values at the current multiplier; the multiplier can rise during the session (when the goal is met), and review responses carry the new values.

---

## 6. Reviews

### POST `/reviews`

```json
{
  "reviews": [
    { "id": "6f1c2a7e-3b0c-4f6e-9d51-0a2b7c9e1f42", "cardId": 101, "rating": "know" },
    { "id": "0b9d8c3a-1e2f-4a5b-8c7d-6e5f4a3b2c1d", "cardId": 140, "rating": "dontKnow" }
  ]
}
```

`200`:

```json
{
  "results": [
    { "id": "6f1c2a7e-…", "status": "applied", "pointsAwarded": 11, "multiplier": 1.1 },
    { "id": "0b9d8c3a-…", "status": "applied", "pointsAwarded": 2, "multiplier": 1.1 }
  ],
  "summary": { "…": "Summary, §1.2" },
  "points": { "know": 11, "dontKnow": 2, "hard": 11, "easy": 11 },
  "events": [ { "type": "goalMet" }, { "type": "milestone", "days": 7, "bonus": 50 } ]
}
```

- `rating`: `know` (Vím, FSRS Good), `dontKnow` (Nevím, Again), `hard` (Těžké, Hard), `easy` (Snadné, Easy). Těžké and Snadné are correct and worth a Vím (#19). `fourRatings` in the session (the user's "Těžké a Snadné" setting) tells the app which buttons to show; the server accepts all four either way.
- Items are processed **in order**, in **one transaction**, under a lock on the user row (two batches of one user never interleave).
- `status`:
  - `applied`: processed now.
  - `duplicate`: this `id` was already processed for this user; the original `pointsAwarded`/`multiplier` are returned, nothing changes.
  - `rejected`: not processed, with `code`: `cardNotFound` (card deleted) or `idConflict` (the UUID belongs to another user). The client drops these. `pointsAwarded` and `multiplier` are left out.
- Any existing card may be answered; the new-card allowance only shapes the session queue (an outbox answer sent the next day still counts).
- `points` are the values for the **next** answer (after any multiplier change in this batch).
- Errors for the whole batch: `validation` (empty, > 50 items, bad UUID or rating, duplicate ids in one batch).

---

## 7. Stats

### GET `/stats?deckId=1`

```json
{
  "deckId": null,
  "tiles": {
    "streak": 13, "bestStreak": 21,
    "successRate30d": 83,
    "sparkline": [80, 75, null, 90, "… 30 values …"],
    "totalReviews": 1834,
    "totalPointsEarned": 16420
  },
  "heatmap": {
    "from": "2026-07-13", "to": "2026-11-08", "today": "2026-11-02",
    "weeks": [ [0, 1, 2, 4, 3, 0, 2], "… 17 weeks, Monday first, null after today …" ]
  },
  "daily": { "goal": 20, "days": [ { "date": "2026-10-20", "graded": 24 }, "… 14 days …" ] },
  "weekdays": [ { "weekday": 1, "successRate": 86, "graded": 210 }, "… Monday=1 … Sunday=7 …" ],
  "bestTime": { "from": "18:00", "to": "20:00", "successRate": 91, "graded": 140 },
  "deckProgress": [
    { "deckId": 1, "name": "C# základy", "mastered": 46, "learning": 30, "new": 44 }
  ],
  "totalProgress": { "mastered": 46, "learning": 30, "new": 44 }
}
```

Definitions: spec §10. `successRate` values are whole percent or `null`.

### GET `/leaderboard?period=week&metric=points`

Žebříček (#34). `period`: `week` (default, this Prague study week from Monday 03:00) or `allTime`; `metric`: `points` (default) or `streak`. A streak isn't counted per week, so with `metric=streak` the period is ignored and the response says `allTime`.

```json
{
  "period": "week",
  "metric": "points",
  "entries": [
    { "rank": 1, "userId": 3, "displayName": "Petra", "points": 420, "currentStreak": 9, "cardsStudied": 41 },
    { "rank": 2, "userId": 7, "displayName": "Kuba", "points": 310, "currentStreak": 12, "cardsStudied": 30 },
    { "rank": 2, "userId": 8, "displayName": "Tom", "points": 310, "currentStreak": 4, "cardsStudied": 33 }
  ],
  "currentUserRank": 2
}
```

Every active user with `showInLeaderboard` on, best first; equal values share a rank (1, 2, 2, 4). `points` and `cardsStudied` are for the period; `currentStreak` is the displayed streak. `currentUserRank` is `null` when the caller hid themselves (they aren't in `entries` either). Rules: spec §10.1. Errors: `validation` (unknown `period` or `metric`).

---

## 8. Shop

A user the admin keeps out of the shop (`user.shopEnabled: false` in login and `/me`) gets `403 shopDisabled` from every endpoint of this section, and reviews never report `wishlistReached` for them.

### GET `/shop`

```json
{
  "balance": 1457,
  "items": [
    { "id": 3, "name": "Jít na pizzu", "description": "Pizza dle výběru", "price": 1500,
      "stock": 2, "initialStock": 3, "soldOut": false, "wishlisted": true, "missing": 43 }
  ]
}
```

Active items only, by `sortOrder`. `missing = max(0, price − balance)`.

### POST `/shop/{itemId}/claim`

`{ "requestId": "c2a1…uuid" }` → `201`:

```json
{ "claim": { "id": 17, "itemId": 4, "itemName": "Kino", "price": 1200, "status": "pending",
             "createdAt": "2026-11-02T17:01:00Z", "decidedAt": null },
  "balance": 257 }
```

A repeated `requestId` returns `200` with the same claim. Errors: `notFound`, `itemInactive`, `soldOut`, `insufficientBalance`, `validation`.

### GET `/claims`

`{ "items": [ Claim, … ] }`, newest first. Status values `pending` / `confirmed` / `rejected` → UI "Čeká na schválení" / "Schváleno" / "Zamítnuto (body vráceny)".

### PUT / DELETE `/wishlist/{itemId}`

`204` either way (both idempotent). `PUT` on an inactive or unknown item → `404`.

---

## 9. Notification texts

### GET `/notification-texts`

```json
{
  "version": "3f9a1c",
  "categories": {
    "morning": [ { "id": 1, "text": "Dobré ráno! ☀️ …" } ],
    "evening": [ "…" ], "last_call": [ "…" ], "milestone": [ "…" ], "wishlist": [ "…" ], "comeback": [ "…" ]
  }
}
```

Active texts only. Strong `ETag` = `version` (hash of ids + texts). `If-None-Match` with the current ETag → `304`.

---

## 10. Health

### GET `/health` (no auth)

`200 { "status": "ok" }` when the DB answers; `503 { "status": "unhealthy" }` otherwise.

---

## 11. Sync contract (phone ↔ server)

1. **Session start:** `GET /session`. The phone keeps the returned queue in memory. The server tracks no session state.
2. **Answer:** for Vím / Nevím the phone creates a review `{ id: uuid v4, cardId, rating }`, appends it to the **outbox**, and shows the predicted points (from the last known `points`) at once.
3. **Send:** right after each answer the phone sends **all** outbox items (oldest first, max 50 per request). Only one request is in flight at a time; answers made meanwhile wait for the next request.
4. **Reconcile:** on `200` the phone removes `applied` / `duplicate` / `rejected` items from the outbox, replaces predicted points with `pointsAwarded`, and takes `summary`, `points` and `events` from the response. Server values always win.
5. **Persistence:** the outbox is stored on the device (per user id) so killing the app loses nothing. It's sent on the next start or login of the same user.
6. **Retry:** on timeout (10 s), network error or `5xx`: retry the same batch (same UUIDs) after 1, 2, 4, 8, 15, 30 s, then every 30 s. `429`: wait for `Retry-After`. `4xx` other than 401/429: drop the batch and log it (a client bug).
7. **Offline:** after 2 failed attempts in a row, or when the OS reports no connectivity, the session shows **"Jsi offline"** and pauses (no new answers). It resumes after the next successful request.
8. **Auth:** on `401 unauthorized` the dio interceptor calls `/auth/refresh` once (other requests wait for it) and repeats the request. If refresh fails with `refreshTokenInvalid` or `accountDisabled`, the phone goes to the login screen. The outbox stays for that user.
9. **Idempotency:** a UUID is processed at most once; resending is always safe.
10. **Time:** the server receive time is the review time (spec §4.2). Answers made right before the 03:00 rollover (#40) but received after it count for the new day.
11. **Edits during a session:** the phone keeps showing its copy of a card. A deleted card's review comes back `rejected / cardNotFound` and is dropped silently.
12. **Skip** sends nothing.

---

## 12. Admin endpoints (`/api/admin/*`)

Admin cookie (spec §9.2). Same error format. Writes with a body require `Content-Type: application/json`.

| Method | Path | Body → Response |
| --- | --- | --- |
| POST | `/admin/auth/login` | `{ username, password }` → `204` + cookie; `401 invalidCredentials`; rate-limited |
| POST | `/admin/auth/logout` | → `204` |
| GET | `/admin/auth/me` | → `{ username }` |
 The Blazor dashboard calls the same services directly; these endpoints exist for scripting and tests.

| Method | Path | Body → Response |
| --- | --- | --- |
| GET | `/admin/overview` | → tiles, pending claims, users today (spec §11) |
| GET | `/admin/users` | → list: id, username, displayName, isActive, balance, streak, bestStreak, totalReviews, successRate, lastActiveAt, shopEnabled |
| POST | `/admin/users` | `{ username, displayName, password?, dailyGoal?, newCardsPerDay?, shopEnabled? }` → `201 { user, password }` (generated when omitted, shown once; `shopEnabled` defaults to true) |
| PUT | `/admin/users/{id}` | `{ displayName, dailyGoal, newCardsPerDay, shopEnabled? }` → user |
| POST | `/admin/users/{id}/reset-password` | → `{ password }` (shown once; revokes refresh tokens) |
| POST | `/admin/users/{id}/activate` · `/deactivate` | → `204` |
| GET / POST | `/admin/decks` | `{ name, description, color, sortOrder }` → deck (with `forEveryone`, `userCount`, `archivedAt`: `null` = active) |
| GET / PUT / DELETE | `/admin/decks/{id}` | PUT body as POST; DELETE → `204` (cascades, spec §2.14) |
| POST | `/admin/decks/{id}/archive` · `/restore` | → deck; archive hides it from every app user, restore brings it back with everyone's progress (spec §2.4, #28). Archiving again keeps `archivedAt` |
| GET / POST | `/admin/decks/{id}/cards` | `{ question, answer, sortOrder?, tags? }` → card (with `tags`) |
| PUT / DELETE | `/admin/decks/{id}/cards/{cardId}` | `{ question, answer, sortOrder, tags? }` → card; omitted `tags` keep the card's tags (§4) |
| GET | `/admin/decks/{id}/yaml` | → `text/yaml` export (yaml-format §3) |
| GET / PUT | `/admin/decks/{id}/access` | `{ forEveryone, userIds: [..] }` → the same; who sees the deck in the app (spec §2.4). Unknown user → `400` |
| GET | `/admin/decks/{id}/delete-impact` | → `{ cards, usersWithProgress }` for the delete confirmation |
| POST | `/admin/decks/{id}/yaml/preview` | `{ yaml }` → preview (yaml-format §5) |
| PUT | `/admin/decks/{id}/yaml` | `{ yaml, baseHash, confirmDeleteIds: [..] }` → `200` result |
| POST | `/admin/decks/import/preview` · `/admin/decks/import` | `{ yaml }` → preview / `201` new deck |
| GET / POST | `/admin/shop-items` | `{ name, description, price, initialStock, isActive, sortOrder }` → item (with pending count and wishlist count) |
| PUT / DELETE | `/admin/shop-items/{id}` | PUT body + `version` (concurrency) |
| GET | `/admin/claims?status=pending` | → claims with user and item names |
| POST | `/admin/claims/{id}/confirm` · `/reject` | → claim |
| GET / POST | `/admin/notification-texts` | `{ category, text, isActive }` → text |
| PUT / DELETE | `/admin/notification-texts/{id}` | |
| POST | `/admin/notification-texts/preview` | `{ text }` → `{ rendered }` with sample values (§13) |

The YAML preview and apply responses also carry `kept` (and `counts.kept`), always empty / 0 here; the MCP server uses them ([mcp.md](./mcp.md)).

## 13. Preview sample values

`{due}` 23 · `{left}` 7 · `{done}` 13 · `{goal}` 20 · `{streak}` 14 · `{multiplier}` 1,2× · `{item}` Jít na pizzu · `{points}` 1 457

## 14. MCP server

Not part of the REST API: Claude's deck tools at `/mcp/<secret>` (Streamable HTTP, off by default). See [mcp.md](./mcp.md).

## 15. App updates

How it fits together, setup and releasing: [app-updates.md](./app-updates.md). Both endpoints need the app access token.

### GET `/app/latest`

```json
{ "latest": { "versionName": "1.0.1", "versionCode": 58, "size": 23456789 } }
```

The newest APK the server has, from the newest **full** GitHub release (pre-releases are never offered). `latest` is `null` when there's nothing (updates off, or no full release yet). The app offers the update when `versionCode` is higher than its own. `size` is in bytes.

### GET `/app/apk`

The APK itself: `200` with `Content-Type: application/vnd.android.package-archive` and `Content-Disposition: attachment; filename=quizly-1.0.1-58.apk`. Supports `Range` (`206`) to resume. `404 notFound` when there's no APK.
