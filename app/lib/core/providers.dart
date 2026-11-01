import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/session/review_sync.dart';
import 'api/api_client.dart';
import 'api/models.dart';

/// The API client, created in `main` after the stored login is restored.
final apiClientProvider = Provider<ApiClient>((ref) => throw UnimplementedError('Overridden in main'));

/// Where the review outbox is stored (overridden in tests).
final outboxStoreProvider = Provider<OutboxStore>((ref) => PrefsOutboxStore());

/// Reports whether the OS has any network (overridden in tests).
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);
  yield online(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(online);
});

class AuthState {
  const AuthState({this.user, this.reason});

  final AppUser? user;

  /// Why the last login ended (shown on the login screen).
  final SignOutReason? reason;

  bool get signedIn => user != null;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final client = ref.watch(apiClientProvider);
    final sub = client.signedOut.listen((reason) => state = AuthState(reason: reason));
    ref.onDispose(sub.cancel);
    return AuthState(user: client.user);
  }

  Future<void> login(String username, String password) async {
    final user = await ref.read(apiClientProvider).login(username.trim().toLowerCase(), password);
    state = AuthState(user: user);
  }

  Future<void> logout() => ref.read(apiClientProvider).logout();
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// The review outbox of the logged-in user; a new one per login (api.md §11).
final reviewSyncProvider = Provider<ReviewSync?>((ref) {
  final userId = ref.watch(authProvider.select((s) => s.user?.id));
  if (userId == null) return null;
  final sync = ReviewSync(
    userId: userId,
    store: ref.watch(outboxStoreProvider),
    send: ref.watch(apiClientProvider).postReviews,
  );
  unawaited(sync.start().then((_) async {
    // Answers left over from the last run go out now; refresh home once they're in.
    if (sync.status.pending == 0) return;
    await sync.whenIdle();
    if (ref.mounted) ref.invalidate(homeProvider);
  }));
  ref.listen(connectivityProvider, (_, next) {
    final connected = next.value;
    if (connected != null) sync.setConnectivity(connected: connected);
  }, fireImmediately: true);
  ref.onDispose(sync.dispose);
  return sync;
});

/// Home data: profile summary and decks, loaded together.
class HomeData {
  const HomeData({required this.me, required this.decks});

  final Me me;
  final DeckList decks;

  /// New cards left today across all decks (the "Učit se vše" queue minus due reviews).
  int get newToday => (me.dueNow - dueReviews).clamp(0, me.dueNow);

  int get dueReviews => decks.items.fold(0, (sum, d) => sum + d.dueNow);
}

final homeProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  final client = ref.watch(apiClientProvider);
  final results = await Future.wait<Object>([client.me(), client.decks()]);
  return HomeData(me: results[0] as Me, decks: results[1] as DeckList);
});
