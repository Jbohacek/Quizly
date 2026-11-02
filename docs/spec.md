# Quizly: technical specification (v1)

This document turns the brief in [`CLAUDE.md`](../CLAUDE.md) into exact rules. When the two disagree, fix one of them in the same PR.

Related documents:
- [`api.md`](./api.md): REST endpoints and the sync contract
- [`yaml-format.md`](./yaml-format.md): deck YAML format
- [`notifications.md`](./notifications.md): notification scheduling rules
- [`notification-texts.md`](./notification-texts.md): seeded notification texts
- [`architecture.md`](./architecture.md): repo layout and packages
- [`fsrs/`](./fsrs/): FSRS reference vectors and their generator

---

## 1. Conventions

- **Instants** are UTC `timestamptz`. The API sends them as ISO 8601 with `Z`.
- **Days** are calendar days in **Europe/Prague**, stored as `date`, sent as `YYYY-MM-DD`.
  - Conversion always goes through the IANA zone `Europe/Prague` (`TimeZoneInfo.FindSystemTimeZoneById("Europe/Prague")`, works on Linux and Windows with ICU). Never use the server's local zone.
  - All "day" logic goes through the injected .NET `TimeProvider` + the `PragueCalendar` helper, so tests can set the time (`FakeTimeProvider`).
- **Times of day** in settings are `time` (no zone), interpreted in Europe/Prague on the phone. API format `HH:mm`.
- **Server time is the truth.** A review's timestamp and day come from the moment the server receives the request, never from the phone.
- **Database naming:** snake_case tables and columns (`EFCore.NamingConventions`).
- **Enums** are stored as short lowercase strings (`varchar`), except the FSRS `state` and `rating`, which are `smallint` with the FSRS numbers.
- **Text** is trimmed on input (leading and trailing whitespace). Line endings are normalized to `\n`. Stored as typed; light formatting is rendered by the app ([yaml-format.md](./yaml-format.md) §10).

---

## 2. Data model

PostgreSQL **18** (`postgres:18` in compose). All FKs are indexed.

### 2.1 `users`

| Column | Type | Null | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | `integer` identity | no | | PK |
| `username` | `varchar(32)` | no | | unique; check `^[a-z0-9]{3,32}$` |
| `display_name` | `varchar(50)` | no | | 1–50 chars after trim |
| `password_hash` | `text` | no | | `PasswordHasher<User>` (PBKDF2, v3 format) |
| `is_active` | `boolean` | no | `true` | |
| `created_at` | `timestamptz` | no | | |
| `last_active_at` | `timestamptz` | yes | | updated on authenticated API calls, at most once per minute |
| `current_streak` | `integer` | no | `0` | cache, see §5 |
| `best_streak` | `integer` | no | `0` | record |
| `last_goal_met_date` | `date` | yes | | last Prague day with `goal_met` |

Users are never deleted in v1; the admin deactivates them.

### 2.2 `user_settings` (1:1 with users)

| Column | Type | Default | Constraint |
| --- | --- | --- | --- |
| `user_id` | `integer` PK, FK → users (cascade) | | |
| `daily_goal` | `integer` | `20` | 1–500 |
| `new_cards_per_day` | `integer` | `5` | 0–100 |
| `notifications_enabled` | `boolean` | `true` | |
| `morning_time` | `time` | `08:00` | |
| `evening_time` | `time` | `18:30` | |
| `last_call_time` | `time` | `21:00` | |
| `quiet_from` | `time` | `22:00` | may be later than `quiet_to` (window over midnight) |
| `quiet_to` | `time` | `07:00` | `quiet_from ≠ quiet_to` |
| `smart_times` | `boolean` | `true` | |

The admin sets `daily_goal` and `new_cards_per_day` when creating a user. The row is created together with the user.

### 2.3 `refresh_tokens`

| Column | Type | Null | Notes |
| --- | --- | --- | --- |
| `id` | `integer` identity | no | PK |
| `user_id` | `integer` FK → users (cascade) | no | index |
| `token_hash` | `bytea` (32 B) | no | SHA-256 of the raw token; unique |
| `created_at` | `timestamptz` | no | |
| `expires_at` | `timestamptz` | no | created + 90 days |
| `revoked_at` | `timestamptz` | yes | |
| `replaced_by_id` | `integer` FK → refresh_tokens (set null) | yes | rotation chain |

Expired or revoked tokens older than 30 days are deleted by a daily cleanup on startup/timer.

### 2.4 `decks`

| Column | Type | Null | Default | Constraint |
| --- | --- | --- | --- | --- |
| `id` | `integer` identity | no | | PK |
| `name` | `varchar(100)` | no | | 1–100 chars |
| `description` | `varchar(500)` | no | `''` | |
| `color` | `char(7)` | no | `'#BAD69B'` | check `^#[0-9A-Fa-f]{6}$`, stored uppercase |
| `sort_order` | `integer` | no | `0` | |
| `for_everyone` | `boolean` | no | `true` | "Pro všechny" |
| `created_at` / `updated_at` | `timestamptz` | no | | |

Index: `(sort_order, id)`.

**`deck_access`** (`deck_id` FK → decks **cascade**, `user_id` FK → users **cascade**; PK both; index `user_id`): the users who see a deck that isn't `for_everyone`.

**Who sees a deck (#18):** an app user sees a deck when it's `for_everyone` or they're in its `deck_access`. Every app endpoint applies this: `/decks`, `/decks/{id}/cards`, `/session` (one deck and all decks), `/me` (due now, the morning forecast), `/stats` (deck filter and deck progress) and `/reviews` (a card of a hidden deck is rejected as `cardNotFound`). Losing access keeps the user's `card_states` and `review_logs`; the deck comes back where it was left. History (streak, heatmap, daily counts, points) is never filtered. The access list is kept while a deck is `for_everyone`, so switching back restores it.

### 2.5 `cards`

| Column | Type | Null | Constraint |
| --- | --- | --- | --- |
| `id` | `integer` identity | no | PK; the stable id used in YAML |
| `deck_id` | `integer` FK → decks (**cascade**) | no | |
| `question` | `varchar(500)` | no | 1–500 chars |
| `answer` | `varchar(2000)` | no | 1–2 000 chars |
| `sort_order` | `integer` | no | |
| `created_at` / `updated_at` | `timestamptz` | no | |

Index: `(deck_id, sort_order, id)`.

### 2.6 `card_states` (FSRS memory per user × card)

A row exists only after the user's **first graded review** of the card. No row = **new** card.

| Column | Type | Null | Notes |
| --- | --- | --- | --- |
| `user_id` | `integer` FK → users (cascade) | no | PK part 1 |
| `card_id` | `integer` FK → cards (**cascade**) | no | PK part 2; index |
| `state` | `smallint` | no | 1 Learning, 2 Review, 3 Relearning (FSRS numbers) |
| `step` | `smallint` | yes | learning/relearning step; null in Review |
| `stability` | `double precision` | no | days |
| `difficulty` | `double precision` | no | 1–10 |
| `due` | `timestamptz` | no | |
| `last_review` | `timestamptz` | no | |
| `first_review` | `timestamptz` | no | drives the new-card allowance (§4.1) |
| `reps` | `integer` | no | graded reviews of this card |
| `lapses` | `integer` | no | Again given while in Review |

Indexes: PK `(user_id, card_id)`; `(user_id, due)`; `(user_id, first_review)`.

### 2.7 `review_logs` (append-only)

| Column | Type | Null | Notes |
| --- | --- | --- | --- |
| `id` | `uuid` | no | PK, generated by the client (idempotency key) |
| `user_id` | `integer` FK → users (cascade) | no | |
| `card_id` | `integer` FK → cards (**cascade**) | no | index |
| `rating` | `smallint` | no | 1 Again (Nevím) or 3 Good (Vím) |
| `state_before` | `smallint` | yes | FSRS state before the review; null for a new card |
| `reviewed_at` | `timestamptz` | no | server receive time (§4.2) |
| `day` | `date` | no | Prague day of `reviewed_at` |
| `multiplier` | `numeric(3,1)` | no | 1.0–2.0 |
| `points_awarded` | `integer` | no | card points only (no milestone bonus) |
| `elapsed_days` | `integer` | no | whole days since the previous review, 0 for the first |
| `scheduled_days` | `integer` | no | whole days until the new due if Review, else 0 |

Indexes: `(user_id, day)`, `(user_id, reviewed_at)`.

### 2.8 `daily_activities`

| Column | Type | Null | Notes |
| --- | --- | --- | --- |
| `user_id` | `integer` FK → users (cascade) | no | PK part 1 |
| `date` | `date` | no | PK part 2, Prague day |
| `graded_count` | `integer` | no | Vím + Nevím |
| `correct_count` | `integer` | no | Vím |
| `points` | `integer` | no | review points + milestone bonuses earned that day |
| `goal` | `integer` | no | the daily goal that applies to this day (§5.3) |
| `goal_met` | `boolean` | no | once true, stays true |
| `goal_met_at` | `timestamptz` | yes | |

Created on the first graded review of the day. A day without a row has 0 activity.

### 2.9 `points_entries` (ledger)

| Column | Type | Null | Notes |
| --- | --- | --- | --- |
| `id` | `bigint` identity | no | PK |
| `user_id` | `integer` FK → users (cascade) | no | |
| `amount` | `integer` | no | check `amount <> 0` |
| `reason` | `varchar(16)` | no | `review` · `milestone` · `claim` · `refund` |
| `reference_id` | `varchar(64)` | no | see below |
| `created_at` | `timestamptz` | no | |

`reference_id` per reason: `review` → review UUID · `milestone` → `"{days}:{yyyy-MM-dd}"` (e.g. `7:2026-11-08`) · `claim` / `refund` → claim id.
Unique index `(user_id, reason, reference_id)`: a safety net, so no event can be booked twice.

**Balance = `SUM(amount)` for the user.** No cached balance in v1 (a few users, indexed sum is fast). Balance can never go negative: only claims subtract, and a claim checks the balance under a lock.

### 2.10 `shop_items`

| Column | Type | Null | Default | Constraint |
| --- | --- | --- | --- | --- |
| `id` | `integer` identity | no | | PK |
| `name` | `varchar(100)` | no | | 1–100 |
| `description` | `varchar(500)` | no | `''` | |
| `price` | `integer` | no | | 1–1 000 000 |
| `initial_stock` | `integer` | no | | 0–10 000 |
| `stock` | `integer` | no | | `0 ≤ stock` |
| `is_active` | `boolean` | no | `true` | |
| `sort_order` | `integer` | no | `0` | |
| `created_at` / `updated_at` | `timestamptz` | no | | |
| `xmin` | system column | | | EF concurrency token for admin edits |

Admin edits: changing `initial_stock` by Δ changes `stock` by Δ too; rejected if `stock` would go below 0. Price changes don't touch existing claims (they store their own price). An item with claims can't be deleted, only deactivated.

### 2.11 `claims`

| Column | Type | Null | Notes |
| --- | --- | --- | --- |
| `id` | `integer` identity | no | PK |
| `user_id` | `integer` FK → users (restrict) | no | |
| `shop_item_id` | `integer` FK → shop_items (**restrict**) | no | |
| `request_id` | `uuid` | no | client-generated, unique; makes the claim call idempotent |
| `price` | `integer` | no | price at the time of the claim |
| `status` | `varchar(16)` | no | `pending` · `confirmed` · `rejected` |
| `created_at` | `timestamptz` | no | |
| `decided_at` | `timestamptz` | yes | |

Indexes: `(status, created_at)`, `(user_id, created_at)`.

### 2.12 `wishlist_entries`

| Column | Type | Null | Notes |
| --- | --- | --- | --- |
| `user_id` | FK → users (cascade) | no | PK part 1 |
| `shop_item_id` | FK → shop_items (cascade) | no | PK part 2 |
| `created_at` | `timestamptz` | no | |
| `notified_at` | `timestamptz` | yes | set when the "balance reached the price" event fired (§6.4) |

### 2.13 `notification_texts`

| Column | Type | Null | Notes |
| --- | --- | --- | --- |
| `id` | `integer` identity | no | PK |
| `category` | `varchar(16)` | no | `morning` · `evening` · `last_call` · `milestone` · `wishlist` · `comeback` |
| `text` | `varchar(300)` | no | placeholders validated (§8) |
| `is_active` | `boolean` | no | |
| `created_at` / `updated_at` | `timestamptz` | no | |

Index: `(category)`. Seeded from `notification-texts.md` (converted to `Seed/notification-texts.json` in Etapa 2) **only when the table is empty**, so admin edits are never overwritten.

### 2.14 Cascades and deletes

| Delete | Effect |
| --- | --- |
| Deck | its cards → their `card_states` and `review_logs` (progress gone). Points and `daily_activities` stay. The UI warns with counts. |
| Card | its `card_states` and `review_logs`. Points and `daily_activities` stay. |
| Shop item | only when it has no claims; wishlist entries cascade. |
| User | not supported in v1 (deactivate instead). |

---

## 3. FSRS

### 3.1 Version and configuration

- **FSRS-6**, ported from the reference implementation **py-fsrs 6.3.2** (`fsrs` on PyPI, `open-spaced-repetition/py-fsrs`).
- Scheduler configuration (fixed in code, not user-editable in v1):

| Setting | Value |
| --- | --- |
| Parameters (w0…w20) | `0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542` |
| Desired retention | 0.9 |
| Learning steps | 1 min, 10 min |
| Relearning steps | 10 min |
| Maximum interval | 36 500 days |
| Fuzz | **off** (deterministic intervals) |

- Ratings used: **Again (1)** for Nevím, **Good (3)** for Vím. Hard and Easy are never produced, but the port keeps them so the formulas match the reference 1:1.

### 3.2 Behaviour in plain words (from the vectors)

- **New card + Vím** → Learning step 1, due in 10 min. **Vím again** → Review, due in 2 days.
- **New card + Nevím** → Learning step 0, due in 1 min. Then Vím → step 1 (10 min) → Review (1 day).
- **Review + Nevím** → Relearning, due in 10 min, `lapses + 1`. Then Vím → Review again with a much lower stability.
- A card answered on time with Vím roughly grows 2 d → 11 d → 46 d → 163 d (easy card).
- Learning cards that become due during a session are **not** added to that session (the queue is fixed when the session is fetched, §4.1). They show up in the next session.

### 3.3 Porting notes (match py-fsrs exactly)

- A never-reviewed card is `Learning`, step 0, stability/difficulty null. In Quizly this is "no `card_states` row"; the scheduler gets that in-memory state.
- `days_since_last_review` and retrievability use **whole days, floored** (`(t - lastReview).days`).
- Same-day reviews (`< 1` day since the last review) of Learning/Review/Relearning cards use **short-term stability** (w17–w19).
- Review intervals: `round(S / FACTOR × (R^(1/DECAY) − 1))` with Python's `round` = **round half to even** → `Math.Round(x, MidpointRounding.ToEven)`. Then clamp to `[1, maximum_interval]`.
- `DECAY = −w20`, `FACTOR = 0.9^(1/DECAY) − 1`.
- Clamp difficulty to `[1, 10]` and stability to `≥ 0.001` exactly where py-fsrs does.
- Use `double` throughout. Tests compare stability/difficulty with tolerance `1e-9` (relative) and due times exactly.

### 3.4 Reference vectors

- [`fsrs/fsrs6-reference-vectors.json`](./fsrs/fsrs6-reference-vectors.json): 8 cases, 61 reviews. Each step has the review time, rating, state before, retrievability before, `elapsedDays`, `scheduledDays` and the full state after.
- Cases: `good_only`, `again_first`, `again_twice_in_learning`, `lapse_and_relearn`, `repeated_lapses`, `overdue_reviews`, `same_day_in_review`, `early_reviews`.
- Regenerate with [`fsrs/generate_vectors.py`](./fsrs/generate_vectors.py) (`pip install fsrs==6.3.2`). The test project links this JSON (`tests/Quizly.Tests`, `FsrsTests`) and the C# scheduler (`Quizly.Domain/Scheduling/Fsrs.cs`) reproduces every step.

### 3.5 Mastery buckets (stats, deck list)

| Bucket | Rule |
| --- | --- |
| **Zvládnuto** | `state = Review` and `stability ≥ 21` |
| **Učím se** | `state ∈ {Learning, Relearning}`, or `Review` with `stability < 21` |
| **Nové** | no `card_states` row |

"% mastered" = Zvládnuto ÷ all cards in the deck(s), rounded down to a whole percent.

---

## 4. Study session

### 4.1 Session queue (`GET /api/session`)

Computed on the server at request time `now`. The server does not store sessions.

1. **Due cards:** the user's `card_states` with `due ≤ now`, in the chosen deck (or all decks), ordered by `due` ascending (most overdue first), then `card_id`.
2. **New cards:** cards without a `card_states` row for this user, up to the **remaining allowance**:
   - `allowance = max(0, new_cards_per_day − introducedToday)`
   - `introducedToday` = the user's `card_states` whose `first_review` falls on today's Prague day, **across all decks**.
   - Order: deck `sort_order`, deck id, card `sort_order`, card id.
3. Queue = due cards, then new cards. No upper limit on due cards in v1.

A new card counts toward the allowance only once it's **graded**. Skipping a new card doesn't use the allowance.

**Extra new cards** ("Ještě 5 nových karet"): `extraNew` (0–50) is added to the remaining allowance for that one request. The cards it brings in count as introduced today like any other.

### 4.2 Answering

| Action | Client | Server |
| --- | --- | --- |
| **Vím** (swipe right) | sends `know` | FSRS Good, points 10 × m |
| **Nevím** (swipe left) | sends `dontKnow`; puts the card **once** more at the end of the queue | FSRS Again, points 2 × m |
| **Přeskočit** | moves the card to the end of the queue; sends nothing | nothing |

- A card re-shown after Nevím is a normal review (FSRS + points + daily count). It is re-queued only once per session, even if answered Nevím again.
- A review's `reviewed_at` = server receive time of the batch, plus the item's index in microseconds (keeps the batch order strictly increasing).
- "Karta X z Y": Y = initial queue length + re-queued Nevím cards so far. Skips don't change Y.

### 4.3 End screen ("Hotovo")

The app computes it from the review responses it got during the session:
- cards done = graded answers in the session; % correct = Vím ÷ graded (rounded to a whole percent);
- points with breakdown: Vím × points, Nevím × points, milestone bonus;
- new balance, streak and goal from the last review response;
- wishlist progress from `GET /api/shop` (nearest wishlist item not yet affordable).

---

## 5. Daily goal and streak

### 5.1 Day

The Prague day of a review is `PragueDate(reviewed_at)`. Days are 23, 24 or 25 hours long (DST). Example boundaries:

| UTC instant | Prague local | Prague day |
| --- | --- | --- |
| `2026-10-24T21:59:59Z` | 23:59:59 CEST | 2026-10-24 |
| `2026-10-24T22:00:00Z` | 00:00:00 CEST | 2026-10-25 |
| `2026-10-25T00:59:59Z` | 02:59:59 CEST | 2026-10-25 |
| `2026-10-25T01:00:00Z` | 02:00:00 CET (clocks back) | 2026-10-25 |
| `2026-10-25T22:59:59Z` | 23:59:59 CET | 2026-10-25 (a 25-hour day) |
| `2027-03-27T23:00:00Z` | 00:00:00 CET | 2027-03-28 |
| `2027-03-28T01:00:00Z` | 03:00:00 CEST (clocks forward) | 2027-03-28 |
| `2027-03-28T21:59:59Z` | 23:59:59 CEST | 2027-03-28 (a 23-hour day) |

### 5.2 Daily activity update (per graded review, in the review transaction)

1. Get or create today's `daily_activities` row. On create: `goal = user_settings.daily_goal`.
2. `graded_count += 1`; `correct_count += 1` if Vím; `points += card points`.
3. If `goal_met` is false and `graded_count ≥ goal`: set `goal_met = true`, `goal_met_at = now`, then run the **streak update** (§5.4).

### 5.3 Changing the daily goal

- If today's row exists and `goal_met` is **false**: set `goal = new goal`. If `graded_count ≥ new goal`, the day becomes met **right away** (streak update + milestone, no review needed). The settings response then carries the same events as a review response.
- If today's row is already met: nothing changes for today (**a met day stays met**). The new goal applies from tomorrow.
- If there's no row for today: nothing to do; the row is created with the new goal at the first review.
- Past days keep their own `goal` (used by the heatmap).

### 5.4 Streak update (when a day becomes met)

```
if user.last_goal_met_date == today − 1:  current_streak += 1
else:                                     current_streak = 1
last_goal_met_date = today
best_streak = max(best_streak, current_streak)
if current_streak ∈ {7, 30, 100, 365}: award milestone (§6.3)
```

### 5.5 Reading the streak (no background job)

```
displayedStreak = last_goal_met_date ∈ {today, today − 1} ? current_streak : 0
```

- Today isn't lost until the day ends: if today isn't met yet, the streak still includes yesterday.
- The cached `current_streak` may be stale after a missed day; it's fixed on the next met day (`= 1`) and every read uses `displayedStreak`.
- **Streak broken:** `current_streak > 0` and `last_goal_met_date < today − 1`. Then `/api/me` reports `streakBroken: { previousStreak, brokenOn }` with `brokenOn = last_goal_met_date + 2` (the first morning after the missed day). The phone uses it for the `comeback` notification.

### 5.6 Worked examples (goal 20)

**A. Normal day.** Met through yesterday, streak 6. Today: reviews 1–19 → streak still 6 (includes yesterday). Review 20 → day met, streak 7, milestone +50.

**B. Missed day.** Last met Monday, streak 12. Tuesday: 5 reviews (not met). Wednesday morning: `last_goal_met_date = Monday = today − 2` → displayed streak **0**, `streakBroken { previousStreak: 12, brokenOn: Wednesday }`. Wednesday goal met → `current_streak = 1`.

**C. Just before midnight.** Streak 3 through yesterday. Today 19 reviews by 23:58 Prague. Review 20 arrives at 23:59:59.900 → today met, streak 4. If it arrives at 00:00:00.100, it counts for the new day: the old day ends unmet, streak displayed as 0 (yesterday unmet, today not met), the new day has 1 review.

**D. DST day.** 2026-10-25 has 25 hours; the goal and the streak work the same, one day is one day.

**E. Goal lowered.** Goal 20, 15 reviews today, not met. The user sets the goal to 15 → today met immediately, streak +1, events returned by `PUT /api/me/settings`.

**F. Goal raised after met.** Goal 20, met with 22 reviews. The user sets 30 → today stays met (goal stays 20 for today). Tomorrow's row starts with goal 30.

**G. New streak re-earns milestones.** Streak 9 (7-day bonus already earned), breaks, later reaches 7 again → +50 again (a different `reference_id`: `7:<new date>`).

---

## 6. Points

### 6.1 Formula

```
m      = min(2.0, 1.0 + 0.1 × floor(streak / 7))
points = round(base × m)        base: Vím 10, Nevím 2, Přeskočit 0
```

- Computed with `decimal` (no floating-point surprises). Rounding: `MidpointRounding.AwayFromZero`.
- `streak` = **displayed streak at the moment just before this review** is counted. The review that meets today's goal still uses the old streak; the next review uses the new one.
- Because `m` moves in steps of 0.1, `2 × m` never ends in .5, so the rounding mode only matters on paper. It's kept as specified.

### 6.2 Multiplier table

| Streak | m | Vím | Nevím |
| --- | --- | --- | --- |
| 0–6 | 1,0× | 10 | 2 |
| 7–13 | 1,1× | 11 | 2 (2,2) |
| 14–20 | 1,2× | 12 | 2 (2,4) |
| 21–27 | 1,3× | 13 | 3 (2,6) |
| 28–34 | 1,4× | 14 | 3 (2,8) |
| 35–41 | 1,5× | 15 | 3 |
| 42–48 | 1,6× | 16 | 3 (3,2) |
| 49–55 | 1,7× | 17 | 3 (3,4) |
| 56–62 | 1,8× | 18 | 4 (3,6) |
| 63–69 | 1,9× | 19 | 4 (3,8) |
| ≥ 70 | 2,0× | 20 | 4 |

"Za X dní násobič stoupne na Y" (Home): `daysToNext = 7 − (streak mod 7)` counted in met days, shown only while `m < 2.0`. If today is not met yet, today is one of those days.

### 6.3 Milestone bonuses

| Streak reaches | Bonus |
| --- | --- |
| 7 | +50 |
| 30 | +200 |
| 100 | +1 000 |
| 365 | +5 000 |

- Awarded in the same transaction as the streak update, as a `milestone` ledger entry (`reference_id = "{days}:{date}"`), and added to that day's `daily_activities.points`.
- Not multiplied. Re-earnable after a new streak reaches the milestone again.
- Returned as an event (`milestone`) so the phone can celebrate and notify.

### 6.4 Wishlist "reached" event

At the end of every `POST /api/reviews` and `PUT /api/me/settings` (the calls whose events reach the phone): for each of the user's wishlist entries with `notified_at IS NULL`, active item, and `balance ≥ price`, set `notified_at = now` and return a `wishlistReached` event.
- Adding a heart when the balance is already ≥ price sets `notified_at` right away (no event, the user can already see it).
- Removing and re-adding a heart resets it.
- A refund raises the balance in an admin action, which the phone never sees; the event then comes with the user's next review.

### 6.5 Worked example

Streak 13 through yesterday (m = 1,1×), goal 20. Today the first 19 answers are 13 Vím + 6 Nevím → 13 × 11 + 6 × 2 = 155. The 20th answer (Vím) still uses 1,1× → +11, goal met, streak 14. The 21st answer (Vím) uses 1,2× → +12. No milestone at 14. Day total: 155 + 11 + 12 = 178.

---

## 7. Shop and claims

### 7.1 Claim (`POST /api/shop/{itemId}/claim`, one transaction)

1. If a claim with this `request_id` already exists for this user, return it (idempotent retry).
2. `SELECT … FOR UPDATE` the **user row**, then the **item row** (always in this order, avoids deadlocks).
3. Check: item active (else `itemInactive`), `stock ≥ 1` (else `soldOut`), `balance ≥ price` (else `insufficientBalance`).
4. Insert `claims(pending, price)`, insert `points_entries(−price, claim, claimId)`, `stock −= 1`.
5. Commit. Concurrent claims of the last piece: the second waits on the item lock, then sees `stock = 0` → `soldOut`.

### 7.2 Decide (admin)

- **Confirm:** `pending → confirmed`, `decided_at = now`. Final.
- **Reject:** `pending → rejected`, `decided_at = now`, `points_entries(+price, refund, claimId)`, `stock += 1` (also when the item is inactive).
- Deciding a non-pending claim → `claimNotPending` (409).

### 7.3 Visibility

- Inactive items are hidden in the app; existing claims of them stay visible in "Moje nákupy".
- `stock = 0` items show "Vyprodáno" and can't be bought.

---

## 8. Validation limits

| Field | Rule |
| --- | --- |
| Username | `^[a-z0-9]{3,32}$`, unique (case: input lowercased first) |
| Display name | 1–50 chars |
| Password (admin-set or changed by the user) | 8–128 chars; a changed one must differ from the current one |
| Generated password | 12 chars from `abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789`, crypto RNG |
| Deck name / description / color | 1–100 / ≤ 500 / `#RRGGBB` |
| Card question / answer | 1–500 / 1–2 000 chars |
| Shop item name / description / price / stock | 1–100 / ≤ 500 / 1–1 000 000 / 0–10 000 |
| Notification text | 1–300 chars; only known placeholders (`{due} {left} {done} {goal} {streak} {multiplier} {item} {points}`); braces must match |
| Settings | goal 1–500; new cards 0–100; times `HH:mm` (minutes 0–59); `quiet_from ≠ quiet_to` |
| Review batch | 1–50 items; `id` a UUID; `rating` `know` or `dontKnow` |
| YAML upload | ≤ 1 MB, ≤ 2 000 cards (see `yaml-format.md`) |

---

## 9. Authentication

### 9.1 App users (JWT)

- **Access token:** JWT HS256, 60 min, signed with `Jwt__SigningKey` (≥ 32 bytes). Claims: `sub` = user id, `name` = username, `iss` = `Jwt__Issuer`, `aud` = `quizly-app`, `iat`, `exp`. Clock skew 1 min.
- **Refresh token:** 32 random bytes, base64url. Stored as SHA-256. Valid 90 days from issue.
- **Rotation:** every refresh revokes the presented token (`revoked_at`, `replaced_by_id`) and issues a new pair.
- **Retry grace:** if a token that was revoked by rotation **less than 60 s ago** is presented again (e.g. the phone lost the first response), and its replacement hasn't been used yet, rotate again from it (revoke the unused replacement, issue a new pair). This keeps flaky networks from logging the user out.
- **Reuse detection:** any other use of a revoked token revokes **all** the user's refresh tokens → 401 `refreshTokenInvalid`.
- **Every authenticated request** checks `users.is_active` (a lookup by id, fine for a few users). Inactive → 401 `accountDisabled`. Deactivating a user also revokes all refresh tokens.
- **Logout** revokes the presented refresh token.
- **Password change** (`POST /api/me/password`): the current password is verified (failures count toward the per-username login throttle), then all the user's refresh tokens are **deleted** and a new pair is issued. Deleted rather than revoked: another device presenting its old token gets `refreshTokenInvalid` without triggering reuse detection, which would otherwise also revoke the new token.
- **Rate limits:** `/api/auth/login` 10 requests / 5 min per IP and 5 failed attempts / 5 min per username; `/api/auth/refresh` 30 / 5 min per IP. Exceeded → 429 with `Retry-After`.
- Wrong username and wrong password give the same error (`invalidCredentials`); inactive accounts give `accountDisabled` only after a correct password.

### 9.2 Admin (cookie)

- Credentials from `ADMIN_USERNAME` / `ADMIN_PASSWORD`; the password is hashed in memory at startup and compared with `PasswordHasher`.
- Cookie `__Host-quizly-admin`: `HttpOnly`, `Secure`, `SameSite=Strict`, 12 h sliding expiration.
- Login page `/admin/login` (static server-rendered form with antiforgery): 5 failed attempts / 5 min per IP. `returnUrl` must be an `/admin` path (no open redirect).
- Logout: `POST /admin/logout` from the sidebar form, antiforgery-checked.
- Default authentication: `/api/*` uses the JWT, everything else (the dashboard and its Blazor circuit) the admin cookie; app and admin endpoints name their scheme explicitly, so the cookie never reaches app endpoints and app tokens never open the dashboard.
- Admin REST endpoints (`/api/admin/*`) accept the same cookie. Writes with a body must be `application/json` (else 415); with `SameSite=Strict` this blocks CSRF.
- `POST /api/admin/auth/login` sets the cookie for REST and Swagger use (same rate limit); the Blazor login page arrives in Etapa 4.
- In Development and Testing the cookie is `quizly-admin` without the `Secure` requirement (plain http); in Production it is `__Host-quizly-admin`.
- Blazor pages call the application services directly.
- Swagger UI `/api/docs`: open in Development, behind the admin cookie in Production.

---

## 10. Stats (`GET /api/stats`)

All days are Prague days; "today" included. `deckId` filters everything except the streak tile.

| Item | Definition |
| --- | --- |
| Streak tile | displayed streak + best streak (never filtered) |
| Success rate | Vím ÷ graded over the last 30 days, whole percent; `null` if no reviews |
| Sparkline | 30 values, one per day: daily success % or `null` on days without reviews |
| Total reviews | all-time graded count |
| Total points earned | all-time sum of `review` + `milestone` entries (claims and refunds excluded). With a deck filter: sum of `review_logs.points_awarded` for that deck |
| Heatmap | 17 columns × 7 rows, Monday first; the last column is the current week (days after today are `null`). Level from `r = graded ÷ that day's goal`: 0 if graded = 0 · 1 if `r < 1` · 2 if `1 ≤ r < 1.25` · 3 if `1.25 ≤ r < 1.5` · 4 if `r ≥ 1.5`. Days without a row use the current goal (they're level 0 anyway). |
| Cards per day | last 14 days of graded counts + the current goal for the dashed line |
| Weekday success | last 90 days, Monday…Sunday: Vím ÷ graded; `null` if fewer than 10 graded |
| Best time window | last 90 days, fixed 2-hour windows (00–02, 02–04, … 22–24, Prague local hour of `reviewed_at`) with ≥ 20 graded reviews; highest success wins, tie → more reviews. `null` if no window qualifies |
| Deck progress | counts of Zvládnuto / Učím se / Nové (§3.5), per deck and total |

Unfiltered numbers come from `daily_activities`; filtered numbers are computed from `review_logs` (indexed by `user_id, day`).

---

## 11. Admin overview definitions

| Tile | Definition |
| --- | --- |
| Pending claims | count of `claims.status = pending` |
| Users active today | users with ≥ 1 graded review today |
| Reviews today + success | graded today across users; Vím ÷ graded |
| Points in the last 7 days | sum of `review` + `milestone` entries, last 7 Prague days incl. today |

"Uživatelé dnes" table: every active user with displayed streak + multiplier, today's `graded_count / goal`, today's points, balance, `last_active_at`.
