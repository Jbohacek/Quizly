import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:workmanager/workmanager.dart';

import '../../core/strings.dart';
import '../../core/theme/tokens.dart';
import 'background.dart';
import 'planner.dart';

/// The Android side of notifications, behind an interface so the app can be tested without it.
abstract interface class NotificationPlatform {
  /// [onTap] is called when the user taps a notification while the app runs.
  Future<void> init({void Function(NotificationTarget target)? onTap});

  /// Where to go when the app was started by tapping a notification.
  Future<NotificationTarget?> launchTarget();

  /// The system allows notifications (Android 13+ permission, or not blocked in settings).
  Future<bool> permitted();

  /// Shows the system dialog on Android 13+. Returns whether notifications are allowed now.
  Future<bool> requestPermission();

  /// Opens the app's notification settings in Android.
  Future<void> openSystemSettings();

  /// Replaces every scheduled reminder with [notifications].
  Future<void> schedule(List<PlannedNotification> notifications);

  Future<void> show(PlannedNotification notification);

  Future<void> cancelAll();

  /// The daily background refresh (docs/notifications.md §4).
  Future<void> startBackgroundRefresh();
  Future<void> stopBackgroundRefresh();
}

/// `flutter_local_notifications` + `workmanager`.
class AndroidNotificationPlatform implements NotificationPlatform {
  final _plugin = FlutterLocalNotificationsPlugin();
  static const _system = MethodChannel('cz.jbohacek.quizly/system');

  /// Ids of reminders; immediate notifications use ids from 1 000 000 000 up.
  static const _firstImmediateId = 1000000000;

  static const _reminders = AndroidNotificationChannel(
    'reminders',
    S.channelReminders,
    description: S.channelRemindersHint,
  );
  static const _achievements = AndroidNotificationChannel(
    'achievements',
    S.channelAchievements,
    description: S.channelAchievementsHint,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static NotificationTarget _target(String? payload) =>
      NotificationTarget.values.where((t) => t.name == payload).firstOrNull ?? NotificationTarget.home;

  @override
  Future<void> init({void Function(NotificationTarget target)? onTap}) async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
      onDidReceiveNotificationResponse: onTap == null ? null : (r) => onTap(_target(r.payload)),
    );
    await _android?.createNotificationChannel(_reminders);
    await _android?.createNotificationChannel(_achievements);
  }

  @override
  Future<NotificationTarget?> launchTarget() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return _target(details.notificationResponse?.payload);
  }

  @override
  Future<bool> permitted() async => await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<bool> requestPermission() async {
    await _android?.requestNotificationsPermission();
    return permitted();
  }

  @override
  Future<void> openSystemSettings() => _system.invokeMethod<void>('openNotificationSettings');

  NotificationDetails _details(PlannedNotification n) {
    final channel = n.category.isAchievement ? _achievements : _reminders;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        color: Q.primary,
        styleInformation: BigTextStyleInformation(n.body),
      ),
    );
  }

  @override
  Future<void> schedule(List<PlannedNotification> notifications) async {
    final keep = {for (final n in notifications) n.id};
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (pending.id < _firstImmediateId && !keep.contains(pending.id)) await _plugin.cancel(id: pending.id);
    }
    for (final n in notifications) {
      await _plugin.zonedSchedule(
        id: n.id,
        scheduledDate: n.at,
        notificationDetails: _details(n),
        // Inexact on purpose: no exact-alarm permission (docs/notifications.md §1).
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: S.appName,
        body: n.body,
        payload: n.target.name,
      );
    }
  }

  @override
  Future<void> show(PlannedNotification n) =>
      _plugin.show(id: n.id, title: S.appName, body: n.body, notificationDetails: _details(n), payload: n.target.name);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> startBackgroundRefresh() async {
    await Workmanager().initialize(backgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      backgroundRefreshTask,
      backgroundRefreshTask,
      frequency: const Duration(hours: 24),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  @override
  Future<void> stopBackgroundRefresh() async {
    await Workmanager().initialize(backgroundDispatcher);
    await Workmanager().cancelByUniqueName(backgroundRefreshTask);
  }
}
