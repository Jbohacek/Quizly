/// Notification planner: which reminders to schedule and with which text (docs/notifications.md §3).
///
/// Pure Dart (no Flutter, no plugins) so every rule can be unit-tested.
library;

import 'dart:math';

import 'package:timezone/timezone.dart' as tz;

import '../../core/api/models.dart';
import '../../core/format.dart';

enum NotificationCategory {
  morning('morning'),
  evening('evening'),
  lastCall('last_call'),
  milestone('milestone'),
  wishlist('wishlist'),
  comeback('comeback');

  const NotificationCategory(this.id);

  /// Category id in the API and the text history.
  final String id;

  /// Milestone and wishlist go to the "Úspěchy" channel, the rest to "Připomínky".
  bool get isAchievement => this == milestone || this == wishlist;
}

/// Where a tap on the notification leads.
enum NotificationTarget { home, shop }

class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.category,
    required this.at,
    required this.textId,
    required this.body,
  });

  /// `yyyymmdd × 10 + slot` for reminders; see [immediateId] for the rest.
  final int id;
  final NotificationCategory category;
  final tz.TZDateTime at;

  /// The text it was rendered from; null for the built-in fallback.
  final int? textId;
  final String body;

  NotificationTarget get target =>
      category == NotificationCategory.wishlist ? NotificationTarget.shop : NotificationTarget.home;

  @override
  String toString() => '${category.id} ${at.toIso8601String()} #$id';
}

/// A time of day, `HH:mm`.
class ClockTime implements Comparable<ClockTime> {
  const ClockTime(this.hour, this.minute);

  factory ClockTime.parse(String value) {
    final [h, m] = value.split(':');
    return ClockTime(int.parse(h), int.parse(m));
  }

  final int hour;
  final int minute;

  int get minutes => hour * 60 + minute;

  @override
  int compareTo(ClockTime other) => minutes.compareTo(other.minutes);

  bool operator <(ClockTime other) => minutes < other.minutes;
  bool operator >=(ClockTime other) => minutes >= other.minutes;

  @override
  bool operator ==(Object other) => other is ClockTime && other.minutes == minutes;

  @override
  int get hashCode => minutes;

  @override
  String toString() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// What the server last told us, cached on the device (notifications.md §2).
class ProgressSnapshot {
  const ProgressSnapshot({
    required this.day,
    required this.done,
    required this.goal,
    required this.goalMet,
    required this.streak,
    required this.multiplier,
    required this.balance,
    this.brokenOn,
    this.dueNow,
    this.forecastDay,
    this.dueByNextMorning,
    this.smartEveningTime,
  });

  factory ProgressSnapshot.fromMe(Me me) => ProgressSnapshot.fromSummary(me.summary).copyWith(
        dueNow: me.dueNow,
        forecastDay: me.forecast == null ? null : pragueDay(me.forecast!.nextMorning),
        dueByNextMorning: me.forecast?.dueByNextMorning,
        smartEveningTime: me.smartEveningTime,
      );

  factory ProgressSnapshot.fromSummary(Summary s) => ProgressSnapshot(
        day: dateOnly(s.today.date),
        done: s.today.graded,
        goal: s.today.goal,
        goalMet: s.today.goalMet,
        streak: s.streak,
        multiplier: s.multiplier,
        balance: s.balance,
        brokenOn: s.streakBroken == null ? null : dateOnly(s.streakBroken!.brokenOn),
      );

  factory ProgressSnapshot.fromJson(Json j) => ProgressSnapshot(
        day: dateOnly(DateTime.parse(j['day'] as String)),
        done: j['done'] as int,
        goal: j['goal'] as int,
        goalMet: j['goalMet'] as bool,
        streak: j['streak'] as int,
        multiplier: (j['multiplier'] as num).toDouble(),
        balance: j['balance'] as int,
        brokenOn: j['brokenOn'] == null ? null : dateOnly(DateTime.parse(j['brokenOn'] as String)),
        dueNow: j['dueNow'] as int?,
        forecastDay: j['forecastDay'] == null ? null : dateOnly(DateTime.parse(j['forecastDay'] as String)),
        dueByNextMorning: j['dueByNextMorning'] as int?,
        smartEveningTime: j['smartEveningTime'] as String?,
      );

  /// The Prague day the numbers are for (UTC midnight of that date).
  final DateTime day;
  final int done;
  final int goal;
  final bool goalMet;
  final int streak;
  final double multiplier;
  final int balance;
  final DateTime? brokenOn;

  /// Cards waiting when this was fetched; unknown after answers that came later.
  final int? dueNow;

  /// The Prague day of the next morning reminder that [dueByNextMorning] is for.
  final DateTime? forecastDay;
  final int? dueByNextMorning;
  final String? smartEveningTime;

  /// The numbers of a review or settings response; the card counts from `/me` are kept,
  /// except [dueNow], which the answers just changed.
  ProgressSnapshot withSummary(Summary s) => ProgressSnapshot.fromSummary(s).copyWith(
        forecastDay: forecastDay,
        dueByNextMorning: dueByNextMorning,
        smartEveningTime: smartEveningTime,
      );

  ProgressSnapshot copyWith({int? dueNow, DateTime? forecastDay, int? dueByNextMorning, String? smartEveningTime}) =>
      ProgressSnapshot(
        day: day,
        done: done,
        goal: goal,
        goalMet: goalMet,
        streak: streak,
        multiplier: multiplier,
        balance: balance,
        brokenOn: brokenOn,
        dueNow: dueNow ?? this.dueNow,
        forecastDay: forecastDay ?? this.forecastDay,
        dueByNextMorning: dueByNextMorning ?? this.dueByNextMorning,
        smartEveningTime: smartEveningTime ?? this.smartEveningTime,
      );

  Json toJson() => {
        'day': _isoDay(day),
        'done': done,
        'goal': goal,
        'goalMet': goalMet,
        'streak': streak,
        'multiplier': multiplier,
        'balance': balance,
        'brokenOn': brokenOn == null ? null : _isoDay(brokenOn!),
        'dueNow': dueNow,
        'forecastDay': forecastDay == null ? null : _isoDay(forecastDay!),
        'dueByNextMorning': dueByNextMorning,
        'smartEveningTime': smartEveningTime,
      };
}

/// Recently used text ids per category, and the text chosen for each scheduled slot.
class TextHistory {
  const TextHistory({this.recent = const {}, this.slots = const {}});

  factory TextHistory.fromJson(Json j) => TextHistory(
        recent: {
          for (final MapEntry(:key, :value) in (j['recent'] as Json).entries) key: [for (final v in value as List) v as int],
        },
        slots: {for (final MapEntry(:key, :value) in (j['slots'] as Json).entries) int.parse(key): value as int},
      );

  /// Category id → text ids, oldest first.
  final Map<String, List<int>> recent;

  /// Notification id → text id, so re-planning keeps the text of a slot.
  final Map<int, int> slots;

  static const _keep = 10;

  TextHistory use(NotificationCategory category, int textId, {int? slot}) {
    final ids = [...?recent[category.id]]
      ..remove(textId)
      ..add(textId);
    return TextHistory(
      recent: {...recent, category.id: ids.length > _keep ? ids.sublist(ids.length - _keep) : ids},
      slots: slot == null ? slots : {...slots, slot: textId},
    );
  }

  /// Drops slot choices of days before [from] (`yyyymmdd × 10` ids).
  TextHistory pruneSlots(int from) =>
      TextHistory(recent: recent, slots: {for (final e in slots.entries) if (e.key >= from) e.key: e.value});

  Json toJson() => {
        'recent': recent,
        'slots': {for (final e in slots.entries) '${e.key}': e.value},
      };
}

class Plan {
  const Plan(this.notifications, this.history);

  final List<PlannedNotification> notifications;
  final TextHistory history;
}

final _placeholder = RegExp(r'\{(\w+)\}');

/// Prague, where every Quizly day starts and ends at 03:00 (CLAUDE.md §5.5, #40).
tz.Location get prague => tz.getLocation('Europe/Prague');

/// Hour of day in Prague when the study day rolls over (#40).
const rolloverHour = 3;

DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// The Prague study day of an instant (03:00 to 03:00 local time, #40).
DateTime pragueDay(DateTime instant) {
  final local = tz.TZDateTime.from(instant, prague);
  final date = DateTime.utc(local.year, local.month, local.day);
  return local.hour < rolloverHour ? date.subtract(const Duration(days: 1)) : date;
}

String _isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int _dayId(DateTime day) => (day.year * 10000 + day.month * 100 + day.day) * 10;

/// Multiplier for the answers of a day that starts with [streak] (CLAUDE.md §5.4).
double multiplierFor(int streak) => min(2.0, 1.0 + 0.1 * (streak ~/ 7));

/// Inside the quiet hours `[from, to)`; wraps over midnight when from > to.
bool isQuiet(ClockTime time, ClockTime from, ClockTime to) =>
    from < to ? time >= from && time < to : time >= from || time < to;

/// One Prague day as the planner sees it.
class _Day {
  const _Day({
    required this.date,
    required this.done,
    required this.goal,
    required this.met,
    required this.streak,
    required this.broken,
    required this.multiplier,
  });

  final DateTime date;
  final int done;
  final int goal;
  final bool met;

  /// Streak on this day: includes the day once it's met, else the days before it.
  final int streak;

  /// The streak broke at the start of this day.
  final bool broken;
  final double multiplier;

  /// The day after: a met day keeps the streak going, an unmet one ends it.
  _Day next(int goal) {
    final carried = met ? streak : 0;
    return _Day(
      date: date.add(const Duration(days: 1)),
      done: 0,
      goal: goal,
      met: false,
      streak: carried,
      broken: !met && streak > 0,
      multiplier: multiplierFor(carried),
    );
  }
}

/// Reminders for the rest of today and all of tomorrow (notifications.md §3).
///
/// Returns the notifications and the text history with the new choices recorded.
/// An empty plan when notifications are off or not allowed by the system.
Plan planNotifications({
  required DateTime now,
  required UserSettings settings,
  required bool permitted,
  required ProgressSnapshot? snapshot,
  required NotificationTexts? texts,
  required TextHistory history,
  required Random random,
  Map<NotificationCategory, String> fallbacks = const {},
}) {
  final local = tz.TZDateTime.from(now, prague);
  final todayDate = pragueDay(now);
  history = history.pruneSlots(_dayId(todayDate));
  if (!settings.notificationsEnabled || !permitted || snapshot == null) return Plan(const [], history);

  final morning = ClockTime.parse(settings.morningTime);
  final lastCall = ClockTime.parse(settings.lastCallTime);
  final quietFrom = ClockTime.parse(settings.quietFrom);
  final quietTo = ClockTime.parse(settings.quietTo);
  final smart = settings.smartTimes ? snapshot.smartEveningTime : null;
  final evening = ClockTime.parse(smart ?? settings.eveningTime);

  // Bring the snapshot up to today, in case it's from an earlier day.
  var day = _Day(
    date: snapshot.day,
    done: snapshot.done,
    goal: snapshot.goal,
    met: snapshot.goalMet,
    streak: snapshot.streak,
    broken: snapshot.brokenOn == snapshot.day,
    multiplier: snapshot.multiplier,
  );
  for (var i = 0; i < 400 && day.date.isBefore(todayDate); i++) {
    day = day.next(settings.dailyGoal);
  }
  final days = [day, day.next(settings.dailyGoal)];

  final planned = <PlannedNotification>[];
  for (final d in days) {
    int? due;
    if (snapshot.forecastDay == d.date) {
      due = snapshot.dueByNextMorning;
    } else if (snapshot.day == d.date) {
      due = snapshot.dueNow;
    }
    final values = <String, String>{
      if (due != null) 'due': formatInt(due),
      'done': formatInt(d.done),
      'goal': formatInt(d.goal),
      if (!d.met && d.goal > d.done) 'left': formatInt(d.goal - d.done),
      if (d.streak > 0) 'streak': formatInt(d.streak),
      'multiplier': formatMultiplier(d.multiplier),
    };

    void slot(int number, NotificationCategory category, ClockTime time) {
      // A slot before 03:00 falls on the next calendar date of the same study day (#40).
      final calendarDate = time.hour < rolloverHour ? d.date.add(const Duration(days: 1)) : d.date;
      final at = tz.TZDateTime(prague, calendarDate.year, calendarDate.month, calendarDate.day, time.hour, time.minute);
      if (!at.isAfter(local) || isQuiet(time, quietFrom, quietTo)) return;
      final id = _dayId(d.date) + number;
      final pick = _pickText(category, values, texts, history, random, fallbacks, keep: history.slots[id]);
      if (pick == null) return;
      if (pick.id != null && pick.id != history.slots[id]) history = history.use(category, pick.id!, slot: id);
      planned.add(PlannedNotification(id: id, category: category, at: at, textId: pick.id, body: pick.body));
    }

    // A day that's already met needs no reminder at all.
    if (!d.met) {
      slot(1, d.broken ? NotificationCategory.comeback : NotificationCategory.morning, morning);
      // Compare within the 03:00–03:00 study day.
      final eveningInDay = (evening.minutes - rolloverHour * 60 + 1440) % 1440;
      final lastCallInDay = (lastCall.minutes - rolloverHour * 60 + 1440) % 1440;
      if (eveningInDay < lastCallInDay) slot(2, NotificationCategory.evening, evening);
      if (d.streak > 0) slot(3, NotificationCategory.lastCall, lastCall);
    }
  }
  return Plan(planned, history);
}

/// Notification ids for things shown right away, apart from the reminder ids.
int immediateId(AppEvent event) => switch (event.type) {
      'milestone' => 1100000000 + (event.days ?? 0),
      _ => 1000000000 + (event.itemId ?? 0),
    };

/// The notification for a milestone or wishlist event, shown now (notifications.md §3.5).
/// Null for other events, when notifications are off or inside the quiet hours.
({PlannedNotification notification, TextHistory history})? immediateNotification({
  required AppEvent event,
  required DateTime now,
  required UserSettings settings,
  required bool permitted,
  required int balance,
  required NotificationTexts? texts,
  required TextHistory history,
  required Random random,
  Map<NotificationCategory, String> fallbacks = const {},
}) {
  final category = switch (event.type) {
    'milestone' => NotificationCategory.milestone,
    'wishlistReached' => NotificationCategory.wishlist,
    _ => null,
  };
  if (category == null || !settings.notificationsEnabled || !permitted) return null;
  final local = tz.TZDateTime.from(now, prague);
  if (isQuiet(ClockTime(local.hour, local.minute), ClockTime.parse(settings.quietFrom), ClockTime.parse(settings.quietTo))) {
    return null;
  }
  final values = category == NotificationCategory.milestone
      ? {
          if (event.days != null) 'streak': formatInt(event.days!),
          if (event.bonus != null) 'points': formatInt(event.bonus!),
          if (event.days != null) 'multiplier': formatMultiplier(multiplierFor(event.days!)),
        }
      : {
          if (event.name != null) 'item': event.name!,
          'points': formatInt(balance),
        };
  final pick = _pickText(category, values, texts, history, random, fallbacks);
  if (pick == null) return null;
  return (
    notification: PlannedNotification(id: immediateId(event), category: category, at: local, textId: pick.id, body: pick.body),
    history: pick.id == null ? history : history.use(category, pick.id!),
  );
}

/// Picks a text of [category] whose placeholders are all known (notifications.md §3.4).
({int? id, String body})? _pickText(
  NotificationCategory category,
  Map<String, String> values,
  NotificationTexts? texts,
  TextHistory history,
  Random random,
  Map<NotificationCategory, String> fallbacks, {
  int? keep,
}) {
  final eligible = [
    for (final t in texts?.categories[category.id] ?? const <NotificationText>[])
      if (_placeholder.allMatches(t.text).every((m) => values.containsKey(m.group(1)))) t,
  ];
  if (eligible.isEmpty) {
    final fallback = fallbacks[category];
    return fallback == null ? null : (id: null, body: fallback);
  }

  NotificationText? chosen;
  if (keep != null) {
    // A re-plan keeps the text chosen before for this slot, if it still fits.
    chosen = eligible.where((t) => t.id == keep).firstOrNull;
  }
  if (chosen == null) {
    final used = history.recent[category.id] ?? const <int>[];
    final k = min(5, eligible.length ~/ 2);
    final blocked = used.length <= k ? used.toSet() : used.sublist(used.length - k).toSet();
    var candidates = [for (final t in eligible) if (!blocked.contains(t.id)) t];
    if (candidates.isEmpty) {
      // Every eligible text was used lately: the least recently used one.
      final sorted = [...eligible]..sort((a, b) => used.indexOf(a.id).compareTo(used.indexOf(b.id)));
      candidates = [sorted.first];
    }
    chosen = candidates[random.nextInt(candidates.length)];
  }
  return (id: chosen.id, body: chosen.text.replaceAllMapped(_placeholder, (m) => values[m.group(1)]!));
}
