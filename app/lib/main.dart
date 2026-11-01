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
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final client = ApiClient(baseUrl: apiBaseUrl, store: SecureTokenStore());
  await client.restore();
  runApp(
    ProviderScope(
      // Screens show their own error with "Zkusit znovu"; no silent automatic retries.
      retry: (retryCount, error) => null,
      overrides: [apiClientProvider.overrideWithValue(client)],
      child: const QuizlyApp(),
    ),
  );
}

class QuizlyApp extends ConsumerWidget {
  const QuizlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the review outbox alive for the logged-in user, so leftovers are sent at start (api.md §11.5).
    ref.watch(reviewSyncProvider);
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
