import 'package:quizly/features/notifications/notification_platform.dart';
import 'package:quizly/features/notifications/planner.dart';

/// Records what would be scheduled and shown on Android.
class FakeNotificationPlatform implements NotificationPlatform {
  bool allowed = true;
  bool grantOnRequest = false;
  int requests = 0;
  int settingsOpened = 0;
  bool cancelledAll = false;
  bool background = false;
  List<PlannedNotification> scheduled = [];
  final shown = <PlannedNotification>[];

  @override
  Future<void> init({void Function(NotificationTarget target)? onTap}) async {}

  @override
  Future<NotificationTarget?> launchTarget() async => null;

  @override
  Future<bool> permitted() async => allowed;

  @override
  Future<bool> requestPermission() async {
    requests++;
    if (grantOnRequest) allowed = true;
    return allowed;
  }

  @override
  Future<void> openSystemSettings() async => settingsOpened++;

  @override
  Future<void> schedule(List<PlannedNotification> notifications) async => scheduled = [...notifications];

  @override
  Future<void> show(PlannedNotification notification) async => shown.add(notification);

  @override
  Future<void> cancelAll() async {
    cancelledAll = true;
    scheduled = [];
  }

  @override
  Future<void> startBackgroundRefresh() async => background = true;

  @override
  Future<void> stopBackgroundRefresh() async => background = false;
}
