import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'features/auth/login_screen.dart';
import 'features/home/deck_screen.dart';
import 'features/home/home_screen.dart';
import 'features/session/done_screen.dart';
import 'features/session/session_controller.dart';
import 'features/session/session_screen.dart';
import 'features/settings/change_password_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/shop/shop_screen.dart';
import 'features/stats/stats_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier(ref.read(authProvider));
  ref
    ..listen(authProvider, (_, next) => auth.value = next)
    ..onDispose(auth.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: auth,
    redirect: (context, state) {
      final signedIn = auth.value.signedIn;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      if (atLogin) return '/home';
      if (state.matchedLocation == '/done' && state.extra is! SessionResult) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
              routes: [
                GoRoute(
                  path: 'deck/:id',
                  builder: (context, state) => DeckScreen(deckId: int.parse(state.pathParameters['id']!)),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/stats',
              builder: (context, state) => const StatsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/shop',
              builder: (context, state) => const ShopScreen(),
            ),
          ]),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
                routes: [GoRoute(path: 'password', builder: (context, state) => const ChangePasswordScreen())],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/session',
        builder: (context, state) => SessionScreen(
          deckId: int.tryParse(state.uri.queryParameters['deck'] ?? ''),
          extraNew: int.tryParse(state.uri.queryParameters['extra'] ?? '') ?? 0,
        ),
      ),
      GoRoute(path: '/done', builder: (context, state) => DoneScreen(result: state.extra! as SessionResult)),
    ],
  );
});
