# Notifications: scheduling rules

All notifications are **local**, scheduled on the phone with `flutter_local_notifications`. The server provides texts (`GET /api/notification-texts`) and the numbers (`GET /api/me`, review responses). Texts: [`notification-texts.md`](./notification-texts.md).

## 1. Android permissions and platform rules

| Topic | Rule |
| --- | --- |
| `POST_NOTIFICATIONS` (Android 13+, API 33) | Runtime permission. Asked once after the first login, from an in-app explainer on Domů ("Mám ti připomínat učení? 🔔" → **Povolit** opens the system dialog / **Teď ne**). Android stops showing the dialog after two denials, so after that Nastavení shows "Upozornění jsou vypnutá v systému" with a button that opens the app's system notification settings. |
| Android 8–12 (API 26–32) | No runtime permission. Channels are required from API 26. |
| Exact alarms (`SCHEDULE_EXACT_ALARM`, Android 12+; denied by default for new installs on Android 14+) | **Not used.** All scheduling is inexact: `AndroidScheduleMode.inexactAllowWhileIdle`. No `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM` in the manifest. Android delivers an inexact alarm within a window of up to an hour after its time (seen as `window=+1h` in `dumpsys alarm`); that is fine for this app. |
| Reboot | The plugin re-registers scheduled notifications after boot (`RECEIVE_BOOT_COMPLETED` + its boot receiver in the manifest). |
| Channels | `reminders` "Připomínky" (morning, evening, last_call, comeback) and `achievements` "Úspěchy" (milestone, wishlist). Default importance. |
| Tap | Opens the app: wishlist → Obchod, everything else → Domů. |

If `notificationsEnabled` is off (Nastavení) or the system permission is missing, the planner cancels everything and schedules nothing.

## 2. Inputs (all from the server, cached on the device)

- `summary` (streak, today graded/goal/met, multiplier, `streakBroken`), `dueNow`, `forecast.dueByNextMorning`, `smartEveningTime` from `/api/me` and review responses.
- Settings (`/api/me/settings`).
- Texts (`/api/notification-texts`, cached with ETag).
- Local text history (last used ids per category).

The cached numbers belong to the Prague day they were fetched on. When the planner runs on a later day (the app wasn't opened and the background refresh failed), it rolls them forward day by day: a met day keeps the streak going into the next day, an unmet day with a streak makes the next day a `comeback` day and the streak 0. `{due}` is known only for the day it was fetched (`dueNow`) or for the morning of `forecast.nextMorning` (`dueByNextMorning`); after answers it's unknown until `/me` is loaded again.

## 3. Planner

A **pure Dart** function so it can be unit-tested without Android:

```dart
List<PlannedNotification> planNotifications({
  required DateTime now,              // device clock, converted to Europe/Prague
  required NotificationInputs inputs,
  required TextPool texts,
  required TextHistory history,
  required Random random,
});
```

It returns notifications for **the rest of today and all of tomorrow** (Prague days). The caller cancels all scheduled `reminders` notifications and schedules the returned list.

**Re-plan when:** the app starts or resumes · after every review response · after a settings change · after the background refresh · after login. On logout: cancel everything.

### 3.1 Slots

Each Prague day `d` has three slots. Notification id = `yyyymmdd × 10 + slot`.

| Slot | Time | Scheduled when |
| --- | --- | --- |
| 1 · `comeback` or `morning` | `morningTime` | **comeback** if the streak breaks at the start of `d` (see below), else **morning** |
| 2 · `evening` | evening time (§3.3) | the goal for `d` is not met (for tomorrow: always) and the evening time is before `lastCallTime` |
| 3 · `last_call` | `lastCallTime` | the goal for `d` is not met **and** the streak on `d` is > 0 |

Rules for "streak on `d` > 0" and "streak breaks at the start of `d`":
- **Today:** streak > 0 ⇔ `summary.streak > 0`. Breaks ⇔ `summary.streakBroken?.brokenOn == today`.
- **Tomorrow:** if today is met → streak > 0, no break. If today is not met → streak = 0 tomorrow, and it **breaks** tomorrow if `summary.streak > 0` now.

So reaching today's goal (a review response with `goalMet`) re-plans: today's `evening` and `last_call` disappear, tomorrow's `last_call` appears, and tomorrow's slot 1 changes from `comeback` to `morning`.

Slots whose time has already passed today are not scheduled. A day whose goal is already met gets no reminder at all, the morning one included.

### 3.2 Quiet hours

- Window `[quietFrom, quietTo)`; if `quietFrom > quietTo` it wraps over midnight (default 22:00–07:00).
- A slot whose time falls inside the window is **skipped**, not moved.
- Immediate notifications (§3.5) inside the window are skipped too (the in-app celebration still shows).

Example: morning 06:30 with quiet hours until 07:00 → no morning notification.

### 3.3 Evening time and Chytré časy

- `smartTimes` on and `smartEveningTime != null` → evening at `smartEveningTime`. The server already rounds it to 15 min and clamps it to 17:00–20:30 (api.md §3).
- Otherwise → `eveningTime`.
- If the evening time is ≥ `lastCallTime`, the evening slot is dropped (last call covers it).

### 3.4 Texts and placeholders

1. Take the active texts of the category.
2. Drop texts with a placeholder whose value is unknown (notification-texts.md table). Values per slot:
   - morning / comeback today: `{due}` = `dueNow`; morning / comeback tomorrow: `{due}` = `forecast.dueByNextMorning`.
   - evening / last_call: `{done}`, `{goal}`, `{left}` from today's summary (tomorrow: done 0, left = goal, goal = current setting).
   - `{streak}` and `{multiplier}` as they will be on that day (tomorrow after an unmet today: streak unknown, multiplier 1,0×).
3. Drop texts used recently: the last `k = min(5, ⌊n / 2⌋)` ids of the category (n = eligible texts). If nothing is left, use the least recently used eligible text.
4. Pick uniformly at random (injected `Random`). Record the id in the history when it's **scheduled**. A re-plan that schedules the same slot again reuses the text chosen before for that slot id, so re-planning doesn't burn through texts.
5. Render placeholders with Czech formatting (`1 457`, `1,2×`). Title: "Quizly". Body: the text.
6. If no text at all is available (empty cache), use the built-in fallback for the category from the strings file.

### 3.5 Immediate notifications

Shown right away (`show`, not scheduled) from review/settings response events, unless inside quiet hours:

| Event | Category | Values |
| --- | --- | --- |
| `milestone` | `milestone` | `{streak}` = days, `{points}` = bonus, `{multiplier}` = new multiplier |
| `wishlistReached` | `wishlist` | `{item}` = name, `{points}` = balance |

The server marks wishlist events once (spec §6.4), so they never repeat.

## 4. Background refresh

- `workmanager` periodic task every **24 h**, constraint: network connected. Android may run it later than asked.
- The task: refresh tokens if needed → `GET /api/me` → `GET /api/notification-texts` (with `If-None-Match`) → re-plan.
- On failure it re-plans from the cache (the plan is still valid, maybe with older numbers).

## 5. Test scenarios (pure Dart)

1. 07:30, goal not met, streak 5 → today: morning 08:00, evening 18:30, last call 21:00; tomorrow: comeback 08:00, evening 18:30 (no last call).
2. Same, then a response with `goalMet` at 12:00 → today: nothing left; tomorrow: morning, evening, last call.
3. 19:00, goal not met, streak 0 → today: nothing (evening passed, last call needs streak > 0); tomorrow: morning, evening.
4. `brokenOn == today`, 06:00 → slot 1 today is `comeback`.
5. Quiet hours 22:00–07:00, morning 06:30 → no morning slots.
6. Quiet hours 13:00–15:00 (no wrap) → nothing between 13:00 and 15:00.
7. Smart times on, `smartEveningTime` 19:15 → evening at 19:15; off → 18:30.
8. Evening time 21:30 ≥ last call 21:00 → no evening slot.
9. Text with `{due}` but no forecast → a text without `{due}` is used.
10. History: 12 morning texts, the last 5 used are never picked; with 3 eligible texts only the last 1 is excluded.
11. Re-plan twice in a row → same texts for the same slot ids.
12. DST: planning on 2026-10-24 for 2026-10-25 → morning at 08:00 local (07:00 UTC), not 06:00 UTC.
13. Notifications disabled → empty plan.
