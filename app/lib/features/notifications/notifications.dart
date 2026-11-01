import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/strings.dart';
import 'notification_platform.dart';
import 'notification_store.dart';
import 'planner.dart';

const _fallbacks = {
  NotificationCategory.morning: S.fallbackMorning,
  NotificationCategory.evening: S.fallbackEvening,
  NotificationCategory.lastCall: S.fallbackLastCall,
  NotificationCategory.milestone: S.fallbackMilestone,
  NotificationCategory.wishlist: S.fallbackWishlist,
  NotificationCategory.comeback: S.fallbackComeback,
};

/// Keeps the scheduled reminders in line with the latest numbers, settings and texts.
///
/// Every input is cached first and then the whole plan is made again (docs/notifications.md §3).
/// Re-plans run one at a time.
class Notifications {
  Notifications({
    required this.platform,
    required KeyValueStore store,
    DateTime Function()? now,
    Random? random,
  })  : _cache = NotificationCache(store),
        _now = now ?? DateTime.now,
        _random = random ?? Random();

  final NotificationPlatform platform;
  final NotificationCache _cache;
  final DateTime Function() _now;
  final Random _random;
  final _taps = StreamController<NotificationTarget>.broadcast();

  Future<void> _queue = Future.value();
  DateTime? _lastRefresh;

  /// Refreshes on resume happen at most this often.
  static const refreshInterval = Duration(minutes: 5);

  /// Taps on notifications while the app runs.
  Stream<NotificationTarget> get taps => _taps.stream;

  Future<void> init() => platform.init(onTap: _taps.add);

  /// Runs [job] after the jobs before it; a failure is logged and doesn't stop the next one.
  Future<void> _serial(Future<void> Function() job) {
    final next = _queue.then((_) => job()).catchError((Object e) => debugPrint('Notifications: $e'));
    return _queue = next;
  }

  Future<void> _replan() async {
    final settings = await _cache.settings();
    final permitted = await platform.permitted();
    if (settings == null) return;
    final plan = planNotifications(
      now: _now(),
      settings: settings,
      permitted: permitted,
      snapshot: await _cache.snapshot(),
      texts: await _cache.texts(),
      history: await _cache.history(),
      random: _random,
      fallbacks: _fallbacks,
    );
    await platform.schedule(plan.notifications);
    await _cache.saveHistory(plan.history);
  }

  /// Makes the plan again from the cache (app start, permission changes).
  Future<void> replan() => _serial(_replan);

  /// Numbers from `GET /api/me`.
  Future<void> onMe(Me me) => _serial(() async {
        await _cache.saveSnapshot(ProgressSnapshot.fromMe(me));
        await _replan();
      });

  /// A review or settings response: new numbers, and milestone / wishlist events shown now.
  Future<void> onSummary(Summary summary, List<AppEvent> events) => _serial(() async {
        final old = await _cache.snapshot();
        await _cache.saveSnapshot(old?.withSummary(summary) ?? ProgressSnapshot.fromSummary(summary));
        final settings = await _cache.settings();
        if (settings != null && events.isNotEmpty) await _showEvents(events, settings, summary.balance);
        await _replan();
      });

  Future<void> _showEvents(List<AppEvent> events, UserSettings settings, int balance) async {
    final permitted = await platform.permitted();
    final texts = await _cache.texts();
    var history = await _cache.history();
    for (final event in events) {
      final result = immediateNotification(
        event: event,
        now: _now(),
        settings: settings,
        permitted: permitted,
        balance: balance,
        texts: texts,
        history: history,
        random: _random,
        fallbacks: _fallbacks,
      );
      if (result == null) continue;
      await platform.show(result.notification);
      history = result.history;
    }
    await _cache.saveHistory(history);
  }

  Future<void> onSettings(UserSettings settings) => _serial(() async {
        await _cache.saveSettings(settings);
        await _replan();
      });

  /// Loads the numbers, settings and texts and re-plans (start, resume, background refresh).
  /// Each request may fail on its own; the plan is then made from what's cached.
  /// With [force] false, does nothing if the last refresh was less than [refreshInterval] ago.
  Future<void> refresh(ApiClient client, {bool force = true}) {
    final now = _now();
    if (!force && _lastRefresh != null && now.difference(_lastRefresh!) < refreshInterval) return replan();
    _lastRefresh = now;
    return _serial(() async {
      final etag = (await _cache.texts())?.version;
      final (me, settings, texts) = await (
        _attempt(client.me),
        _attempt(client.settings),
        _attempt(() => client.notificationTexts(etag: etag)),
      ).wait;
      if (me != null) await _cache.saveSnapshot(ProgressSnapshot.fromMe(me));
      if (settings != null) await _cache.saveSettings(settings);
      if (texts != null) await _cache.saveTexts(texts);
      await _replan();
    });
  }

  static Future<T?> _attempt<T>(Future<T?> Function() request) async {
    try {
      return await request();
    } on ApiException catch (e) {
      debugPrint('Notifications refresh: ${e.code}');
      return null;
    }
  }

  Future<bool> permitted() => platform.permitted();

  /// The Domů explainer: shown once, while the system doesn't allow notifications yet.
  Future<bool> shouldAsk() async {
    if (await _cache.asked()) return false;
    final settings = await _cache.settings();
    if (settings != null && !settings.notificationsEnabled) return false;
    return !await platform.permitted();
  }

  /// The explainer was answered; [allow] opens the system dialog.
  Future<bool> answerAsk({required bool allow}) async {
    await _cache.setAsked();
    if (!allow) return false;
    final granted = await platform.requestPermission();
    await replan();
    return granted;
  }

  Future<bool> requestPermission() async {
    final granted = await platform.requestPermission();
    await replan();
    return granted;
  }

  /// Logged in: daily background refresh on.
  Future<void> signedIn() => _serial(platform.startBackgroundRefresh);

  /// Logout: nothing more is shown for this user.
  Future<void> signedOut() => _serial(() async {
        _lastRefresh = null;
        await _cache.clearUser();
        await platform.cancelAll();
        await platform.stopBackgroundRefresh();
      });
}
