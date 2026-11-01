import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/storage/token_store.dart';
import 'notification_platform.dart';
import 'notification_store.dart';
import 'notifications.dart';

/// Unique name of the daily refresh in WorkManager.
const backgroundRefreshTask = 'quizly.notifications.refresh';

/// Runs in a background isolate, about once a day, even when the app isn't open
/// (docs/notifications.md §4): fresh numbers and texts, then a new plan.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final notifications = Notifications(platform: AndroidNotificationPlatform(), store: PrefsKeyValueStore());
    await notifications.init();
    final client = ApiClient(baseUrl: apiBaseUrl, store: SecureTokenStore());
    if (await client.restore() == null) {
      // The login ended (expired or rejected): stop the reminders.
      await notifications.platform.cancelAll();
      return true;
    }
    // Failed requests fall back to the cache, so the task itself always succeeds.
    await notifications.refresh(client);
    return true;
  });
}
