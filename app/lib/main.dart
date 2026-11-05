import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/api_client.dart';
import 'core/config.dart';
import 'core/providers.dart';
import 'core/storage/token_store.dart';
import 'core/strings.dart';
import 'core/theme/theme.dart';
import 'features/notifications/notification_platform.dart';
import 'features/notifications/notification_store.dart';
import 'features/notifications/notifications.dart';
import 'features/notifications/planner.dart';
import 'features/onboarding/onboarding_store.dart';
import 'features/updates/app_update.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final client = ApiClient(baseUrl: apiBaseUrl, store: SecureTokenStore());
  await client.restore();
  final store = PrefsKeyValueStore();
  final onboarding = OnboardingStore(store);
  await onboarding.init(alreadySignedIn: client.user != null);
  final notifications = Notifications(platform: AndroidNotificationPlatform(), store: store);
  await notifications.init();
  runApp(
    ProviderScope(
      // Screens show their own error with "Zkusit znovu"; no silent automatic retries.
      retry: (retryCount, error) => null,
      overrides: [
        apiClientProvider.overrideWithValue(client),
        onboardingStoreProvider.overrideWithValue(onboarding),
        notificationsProvider.overrideWithValue(notifications),
      ],
      child: const QuizlyApp(),
    ),
  );
}

class QuizlyApp extends ConsumerStatefulWidget {
  const QuizlyApp({super.key});

  @override
  ConsumerState<QuizlyApp> createState() => _QuizlyAppState();
}

class _QuizlyAppState extends ConsumerState<QuizlyApp> {
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<NotificationTarget>? _taps;

  @override
  void initState() {
    super.initState();
    final notifications = ref.read(notificationsProvider);
    _taps = notifications.taps.listen(_open);
    unawaited(notifications.platform.launchTarget().then((target) {
      if (target != null && mounted) _open(target);
    }));
    _lifecycle = AppLifecycleListener(onResume: _resumed);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_taps?.cancel());
    super.dispose();
  }

  /// A tapped notification: wishlist → Obchod, the rest → Domů (docs/notifications.md §1).
  void _open(NotificationTarget target) {
    if (!ref.read(authProvider).signedIn || ref.read(onboardingProvider)) return;
    // The screen may still show what it loaded before the notification came.
    final shop = target == NotificationTarget.shop;
    ref
      ..invalidate(shop ? shopProvider : homeProvider)
      ..read(routerProvider).go(shop ? '/shop' : '/home');
  }

  /// Back from the background: the permission may have changed in Android settings, and the numbers may be old.
  void _resumed() {
    ref.invalidate(notificationPermissionProvider);
    if (!ref.read(authProvider).signedIn) return;
    // A release may have come out while the app was in the background.
    ref.invalidate(availableUpdateProvider);
    unawaited(ref.read(notificationsProvider).refresh(ref.read(apiClientProvider), force: false));
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the review outbox alive for the logged-in user, so leftovers are sent at start (api.md §11.5).
    ref
      ..watch(reviewSyncProvider)
      ..watch(notificationSyncProvider);
    return MaterialApp.router(
      title: S.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('cs'),
      supportedLocales: const [Locale('cs')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
