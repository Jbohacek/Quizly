import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/api/models.dart';
import 'package:quizly/features/notifications/notification_store.dart';
import 'package:quizly/features/notifications/notifications.dart';
import 'package:quizly/features/notifications/planner.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'fakes.dart';
import 'fixtures.dart';

const nbsp = ' ';

UserSettings settings({
  bool enabled = true,
  String morning = '08:00',
  String evening = '18:30',
  String lastCall = '21:00',
  String quietFrom = '22:00',
  String quietTo = '07:00',
  bool smart = true,
}) =>
    UserSettings(
      dailyGoal: 20,
      newCardsPerDay: 5,
      notificationsEnabled: enabled,
      morningTime: morning,
      eveningTime: evening,
      lastCallTime: lastCall,
      quietFrom: quietFrom,
      quietTo: quietTo,
      smartTimes: smart,
    );

/// An instant given as Prague wall-clock time.
DateTime prg(int month, int day, int hour, [int minute = 0]) => tz.TZDateTime(prague, 2026, month, day, hour, minute);

ProgressSnapshot snap({
  int day = 2,
  int done = 3,
  bool met = false,
  int streak = 5,
  int? brokenOn,
  int? dueNow,
  int? forecastDay,
  int? dueByNextMorning,
  String? smart,
}) =>
    ProgressSnapshot(
      day: DateTime.utc(2026, 11, day),
      done: done,
      goal: 20,
      goalMet: met,
      streak: streak,
      multiplier: multiplierFor(streak),
      balance: 640,
      brokenOn: brokenOn == null ? null : DateTime.utc(2026, 11, brokenOn),
      dueNow: dueNow,
      forecastDay: forecastDay == null ? null : DateTime.utc(2026, 11, forecastDay),
      dueByNextMorning: dueByNextMorning,
      smartEveningTime: smart,
    );

NotificationTexts texts(Map<String, List<String>> byCategory) {
  var id = 0;
  return NotificationTexts(
    version: 'v1',
    categories: {
      for (final MapEntry(:key, :value) in byCategory.entries)
        key: [for (final t in value) NotificationText(id: ++id, text: t)],
    },
  );
}

final simpleTexts = texts({
  for (final c in NotificationCategory.values) c.id: ['${c.id} A', '${c.id} B'],
});

Plan plan({
  required DateTime now,
  UserSettings? with_,
  ProgressSnapshot? snapshot,
  NotificationTexts? pool,
  TextHistory history = const TextHistory(),
  bool permitted = true,
  int seed = 1,
}) =>
    planNotifications(
      now: now,
      settings: with_ ?? settings(),
      permitted: permitted,
      snapshot: snapshot ?? snap(),
      texts: pool ?? simpleTexts,
      history: history,
      random: Random(seed),
    );

/// `2. morning 08:00` per planned notification.
List<String> slots(Plan p) => [
      for (final n in p.notifications)
        '${n.at.day}. ${n.category.id} ${n.at.hour.toString().padLeft(2, '0')}:${n.at.minute.toString().padLeft(2, '0')}',
    ];

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('planner (docs/notifications.md §5)', () {
    test('1: 07:30, goal open, streak 5 → three reminders today, comeback and evening tomorrow', () {
      final p = plan(now: prg(11, 2, 7, 30));
      expect(slots(p), ['2. morning 08:00', '2. evening 18:30', '2. last_call 21:00', '3. comeback 08:00', '3. evening 18:30']);
      expect(p.notifications.first.id, 202611021);
      expect(p.notifications.last.id, 202611032);
    });

    test('2: the goal met at 12:00 → nothing today; tomorrow morning, evening and last call', () {
      final p = plan(now: prg(11, 2, 12), snapshot: snap(done: 20, met: true, streak: 6));
      expect(slots(p), ['3. morning 08:00', '3. evening 18:30', '3. last_call 21:00']);
    });

    test('3: 19:00, goal open, streak 0 → nothing today; tomorrow morning and evening', () {
      final p = plan(now: prg(11, 2, 19), snapshot: snap(streak: 0));
      expect(slots(p), ['3. morning 08:00', '3. evening 18:30']);
    });

    test('4: the streak broke today → slot 1 today is comeback', () {
      final p = plan(now: prg(11, 2, 6), snapshot: snap(streak: 0, done: 0, brokenOn: 2));
      expect(slots(p).first, '2. comeback 08:00');
      expect(slots(p), isNot(contains('2. last_call 21:00')));
    });

    test('5: quiet hours 22:00–07:00 and morning at 06:30 → no morning reminders', () {
      final p = plan(now: prg(11, 2, 5), with_: settings(morning: '06:30'));
      expect(slots(p).where((s) => s.contains('morning') || s.contains('comeback')), isEmpty);
      expect(slots(p), contains('2. evening 18:30'));
    });

    test('6: quiet hours 13:00–15:00 (no wrap) → nothing between 13:00 and 15:00', () {
      final p = plan(
        now: prg(11, 2, 7),
        with_: settings(evening: '14:00', quietFrom: '13:00', quietTo: '15:00', smart: false),
      );
      expect(slots(p).where((s) => s.contains('evening')), isEmpty);
      expect(slots(p), contains('2. last_call 21:00'));
      expect(isQuiet(const ClockTime(15, 0), const ClockTime(13, 0), const ClockTime(15, 0)), isFalse);
      expect(isQuiet(const ClockTime(6, 59), const ClockTime(22, 0), const ClockTime(7, 0)), isTrue);
    });

    test('7: Chytré časy move the evening reminder; off keeps the set time', () {
      expect(slots(plan(now: prg(11, 2, 7), snapshot: snap(smart: '19:15'))), contains('2. evening 19:15'));
      expect(
        slots(plan(now: prg(11, 2, 7), snapshot: snap(smart: '19:15'), with_: settings(smart: false))),
        contains('2. evening 18:30'),
      );
      // Too few sessions for a smart time yet: the set time.
      expect(slots(plan(now: prg(11, 2, 7))), contains('2. evening 18:30'));
    });

    test('8: evening at 21:30, after the last call at 21:00 → no evening reminder', () {
      final p = plan(now: prg(11, 2, 7), with_: settings(evening: '21:30', smart: false));
      expect(slots(p).where((s) => s.contains('evening')), isEmpty);
    });

    test('9: a text with {due} but no card count → a text without {due}', () {
      final pool = texts({'morning': ['Karty na dnešek: {due}', 'Dobré ráno! ☀️']});
      for (var seed = 0; seed < 20; seed++) {
        final p = plan(now: prg(11, 2, 7), pool: pool, seed: seed);
        expect(p.notifications.first.body, 'Dobré ráno! ☀️');
      }
      final known = plan(now: prg(11, 2, 7), pool: texts({'morning': ['Karty na dnešek: {due}']}), snapshot: snap(dueNow: 1234));
      expect(known.notifications.first.body, 'Karty na dnešek: 1${nbsp}234');
    });

    test('10: the last 5 used texts are never picked; with 3 eligible texts only the last one is excluded', () {
      final pool = texts({'morning': [for (var i = 1; i <= 12; i++) 'Ráno $i']});
      final recent = TextHistory(recent: {'morning': [1, 2, 3, 4, 5, 6, 7]});
      for (var seed = 0; seed < 50; seed++) {
        final p = plan(now: prg(11, 2, 7), pool: pool, history: recent, seed: seed, with_: settings(evening: '22:30'));
        final morning = p.notifications.where((n) => n.category == NotificationCategory.morning).first;
        expect(morning.textId, isNot(isIn([3, 4, 5, 6, 7])));
      }
      final few = texts({'morning': ['Ráno 1', 'Ráno 2', 'Ráno 3']});
      final picked = <int>{};
      for (var seed = 0; seed < 50; seed++) {
        final p = plan(now: prg(11, 2, 7), pool: few, history: const TextHistory(recent: {'morning': [1, 2]}), seed: seed);
        picked.add(p.notifications.first.textId!);
      }
      expect(picked, {1, 3});
    });

    test('11: planning twice in a row keeps the same texts for the same slots', () {
      final pool = texts({for (final c in NotificationCategory.values) c.id: [for (var i = 0; i < 8; i++) '${c.id} $i']});
      final first = plan(now: prg(11, 2, 7), pool: pool, seed: 1);
      final second = plan(now: prg(11, 2, 7, 5), pool: pool, history: first.history, seed: 99);
      expect([for (final n in second.notifications) n.textId], [for (final n in first.notifications) n.textId]);
      // Re-planning doesn't burn through texts.
      expect(second.history.recent, first.history.recent);
    });

    test('12: DST end — tomorrow 25. 10. at 08:00 is 07:00 UTC', () {
      final p = plan(
        now: prg(10, 24, 10),
        snapshot: ProgressSnapshot(day: DateTime.utc(2026, 10, 24), done: 0, goal: 20, goalMet: false, streak: 3, multiplier: 1, balance: 0),
      );
      final morning = p.notifications.firstWhere((n) => n.at.day == 25 && n.id % 10 == 1);
      expect(morning.at.toUtc(), DateTime.utc(2026, 10, 25, 7));
      final today = p.notifications.firstWhere((n) => n.at.day == 24);
      expect(today.at.toUtc(), DateTime.utc(2026, 10, 24, 16, 30));
    });

    test('13: notifications off or not allowed by the system → empty plan', () {
      expect(plan(now: prg(11, 2, 7), with_: settings(enabled: false)).notifications, isEmpty);
      expect(plan(now: prg(11, 2, 7), permitted: false).notifications, isEmpty);
    });
  });

  group('planner details', () {
    test('numbers from an earlier day carry over: yesterday unmet with a streak → comeback today', () {
      final p = plan(now: prg(11, 3, 7), snapshot: snap(day: 2, streak: 4));
      expect(slots(p), ['3. comeback 08:00', '3. evening 18:30', '4. morning 08:00', '4. evening 18:30']);
    });

    test('yesterday met → today goes on with the streak and its last call', () {
      final p = plan(now: prg(11, 3, 7), snapshot: snap(day: 2, done: 20, met: true, streak: 6));
      expect(slots(p).take(3), ['3. morning 08:00', '3. evening 18:30', '3. last_call 21:00']);
    });

    test('placeholders: today numbers, tomorrow done 0 and the new multiplier', () {
      final pool = texts({
        'evening': ['{done} z {goal}, zbývá: {left}'],
        'last_call': ['Série: {streak}, násobič {multiplier}'],
        'morning': ['Násobič {multiplier}, karty: {due}'],
      });
      final p = plan(
        now: prg(11, 2, 12),
        pool: pool,
        snapshot: snap(done: 13, streak: 13, forecastDay: 3, dueByNextMorning: 31),
      );
      final bodies = {for (final n in p.notifications) '${n.at.day}. ${n.category.id}': n.body};
      expect(bodies['2. evening'], '13 z 20, zbývá: 7');
      expect(bodies['2. last_call'], 'Série: 13, násobič 1,1×');
      // Today unmet: tomorrow starts without a streak, so the morning is a comeback (no text in the pool).
      expect(bodies['3. evening'], '0 z 20, zbývá: 20');
      expect(bodies.containsKey('3. comeback'), isFalse);

      final met = plan(now: prg(11, 2, 12), pool: pool, snapshot: snap(done: 20, met: true, streak: 14, forecastDay: 3, dueByNextMorning: 31));
      final tomorrow = {for (final n in met.notifications) n.category.id: n.body};
      expect(tomorrow['morning'], 'Násobič 1,2×, karty: 31');
      expect(tomorrow['last_call'], 'Série: 14, násobič 1,2×');
    });

    test('{streak} is unknown at 0 and {left} once the goal is met', () {
      final pool = texts({'evening': ['Série: {streak}', 'Bez čísel']});
      final p = plan(now: prg(11, 2, 7), pool: pool, snapshot: snap(streak: 0));
      expect(p.notifications.where((n) => n.category == NotificationCategory.evening).map((n) => n.body).toSet(), {'Bez čísel'});
    });

    test('no texts cached → the built-in text', () {
      final p = planNotifications(
        now: prg(11, 2, 7),
        settings: settings(),
        permitted: true,
        snapshot: snap(streak: 0),
        texts: null,
        history: const TextHistory(),
        random: Random(1),
        fallbacks: {NotificationCategory.morning: 'Dobré ráno'},
      );
      expect(slots(p), ['2. morning 08:00', '3. morning 08:00']);
      expect(p.notifications.first.body, 'Dobré ráno');
      expect(p.notifications.first.textId, isNull);
    });

    test('slot choices of past days are dropped', () {
      final p = plan(now: prg(11, 2, 7), history: const TextHistory(slots: {202611011: 1, 202611021: 2}));
      expect(p.history.slots.keys, everyElement(greaterThanOrEqualTo(202611020)));
    });

    test('snapshot round-trips through JSON', () {
      final s = snap(brokenOn: 2, dueNow: 4, forecastDay: 3, dueByNextMorning: 9, smart: '19:15');
      expect(ProgressSnapshot.fromJson(s.toJson()).toJson(), s.toJson());
      expect(ProgressSnapshot.fromJson(s.toJson()).day, DateTime.utc(2026, 11, 2));
      final h = const TextHistory().use(NotificationCategory.lastCall, 4, slot: 202611023);
      expect(TextHistory.fromJson(h.toJson()).toJson(), h.toJson());
    });

    test('study day rolls over at 03:00 in Prague (#40)', () {
      expect(pragueDay(prg(11, 3, 2, 59)), DateTime.utc(2026, 11, 2));
      expect(pragueDay(prg(11, 3, 3, 0)), DateTime.utc(2026, 11, 3));

      // At 01:00 on Nov 3 the study day is still Nov 2; its morning/evening/last_call are in the past,
      // so only Nov 3's slots are planned.
      final p = plan(now: prg(11, 3, 1, 0), snapshot: snap(day: 2, done: 5, met: false, streak: 4));
      expect(slots(p), ['3. comeback 08:00', '3. evening 18:30']);
    });
  });

  group('immediate notifications (§3.5)', () {
    final pool = texts({
      'milestone': ['{streak} dní v řadě! Bonus +{points} bodů, násobič {multiplier}'],
      'wishlist': ['Na „{item}“ už máš body: {points}'],
    });

    ({PlannedNotification notification, TextHistory history})? show(AppEvent event, DateTime now) =>
        immediateNotification(
          event: event,
          now: now,
          settings: settings(),
          permitted: true,
          balance: 1520,
          texts: pool,
          history: const TextHistory(),
          random: Random(1),
        );

    test('milestone: days, bonus and the new multiplier', () {
      final n = show(const AppEvent(type: 'milestone', days: 7, bonus: 50), prg(11, 2, 19))!.notification;
      expect(n.body, '7 dní v řadě! Bonus +50 bodů, násobič 1,1×');
      expect(n.category.isAchievement, isTrue);
      expect(n.target, NotificationTarget.home);
    });

    test('wishlist: the reward and the balance; a tap opens Obchod', () {
      final n = show(const AppEvent(type: 'wishlistReached', itemId: 3, name: 'Jít na pizzu', price: 1500), prg(11, 2, 19))!
          .notification;
      expect(n.body, 'Na „Jít na pizzu“ už máš body: 1${nbsp}520');
      expect(n.target, NotificationTarget.shop);
      expect(n.id, 1000000003);
    });

    test('inside quiet hours, or for other events, nothing is shown', () {
      expect(show(const AppEvent(type: 'milestone', days: 7, bonus: 50), prg(11, 2, 23)), isNull);
      expect(show(const AppEvent(type: 'goalMet'), prg(11, 2, 19)), isNull);
    });
  });

  group('Notifications service', () {
    late FakeNotificationPlatform platform;
    late Notifications notifications;

    setUp(() {
      platform = FakeNotificationPlatform();
      notifications = Notifications(platform: platform, store: MemoryKeyValueStore(), now: () => prg(11, 2, 7), random: Random(1));
    });

    test('settings and numbers make a plan; reaching the goal re-plans and a milestone shows at once', () async {
      await notifications.onSettings(settings());
      await notifications.onSummary(summary(streak: 6, graded: 3), const []);
      expect(platform.scheduled.map((n) => n.category.id), ['morning', 'evening', 'last_call', 'comeback', 'evening']);

      await notifications.onSummary(
        summary(streak: 7, graded: 20, goalMet: true),
        const [AppEvent(type: 'goalMet'), AppEvent(type: 'milestone', days: 7, bonus: 50)],
      );
      expect(platform.shown.single.category, NotificationCategory.milestone);
      expect(platform.scheduled.map((n) => '${n.at.day}. ${n.category.id}'), ['3. morning', '3. evening', '3. last_call']);
    });

    test('turning notifications off cancels everything; logout too', () async {
      await notifications.onSettings(settings());
      await notifications.onSummary(summary(), const []);
      expect(platform.scheduled, isNotEmpty);
      await notifications.onSettings(settings(enabled: false));
      expect(platform.scheduled, isEmpty);

      await notifications.onSettings(settings());
      await notifications.signedOut();
      expect(platform.cancelledAll, isTrue);
      expect(platform.background, isFalse);
    });

    test('the Domů question is asked once, only while the system blocks notifications', () async {
      platform.allowed = false;
      expect(await notifications.shouldAsk(), isTrue);
      platform.grantOnRequest = true;
      expect(await notifications.answerAsk(allow: true), isTrue);
      expect(platform.requests, 1);
      platform.allowed = false;
      expect(await notifications.shouldAsk(), isFalse);
    });
  });
}
