import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/home/week.dart';
import '../features/notifications/notifications.dart';
import '../features/session/review_sync.dart';
import 'api/api_client.dart';
import 'api/api_exception.dart';
import 'api/models.dart';

/// The API client, created in `main` after the stored login is restored.
final apiClientProvider = Provider<ApiClient>((ref) => throw UnimplementedError('Overridden in main'));

/// Scheduled reminders, created in `main` (tests use a fake platform).
final notificationsProvider = Provider<Notifications>((ref) => throw UnimplementedError('Overridden in main'));

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
  final client = ref.watch(apiClientProvider);
  final notifications = ref.watch(notificationsProvider);
  final sync = ReviewSync(
    userId: userId,
    store: ref.watch(outboxStoreProvider),
    send: (batch) async {
      final result = await client.postReviews(batch);
      // Every answer can change the plan: goal met, milestone, a reward within reach.
      unawaited(notifications.onSummary(result.summary, result.events));
      return result;
    },
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

/// Keeps the reminders of the logged-in user going; logout stops them.
final notificationSyncProvider = Provider<void>((ref) {
  final userId = ref.watch(authProvider.select((s) => s.user?.id));
  final notifications = ref.watch(notificationsProvider);
  if (userId == null) {
    unawaited(notifications.signedOut());
    return;
  }
  unawaited(notifications.signedIn());
  unawaited(notifications.refresh(ref.read(apiClientProvider)));
});

/// The system allows notifications; refreshed when the app comes back to the front.
final notificationPermissionProvider =
    FutureProvider.autoDispose<bool>((ref) => ref.watch(notificationsProvider).permitted());

/// Show the "Mám ti připomínat učení?" card on Domů.
final notificationAskProvider = FutureProvider.autoDispose<bool>((ref) => ref.watch(notificationsProvider).shouldAsk());

/// Home data: profile summary and decks, loaded together, plus this week's strip.
class HomeData {
  const HomeData({required this.me, required this.decks, this.week});

  final Me me;
  final DeckList decks;

  /// Mon–Sun of the current week; null if the stats couldn't be loaded (the strip is hidden).
  final List<DayMark>? week;

  /// New cards left today across all decks (the "Učit se vše" queue minus due reviews).
  int get newToday => (me.dueNow - dueReviews).clamp(0, me.dueNow);

  int get dueReviews => decks.items.fold(0, (sum, d) => sum + d.dueNow);
}

final homeProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  final client = ref.watch(apiClientProvider);
  // The week strip is extra: Domů still shows when the stats fail.
  final week = client.stats().then<List<DayMark>?>((s) => weekMarks(s.heatmap), onError: (Object _) => null);
  final results = await Future.wait<Object>([client.me(), client.decks()]);
  final me = results[0] as Me;
  unawaited(ref.read(notificationsProvider).onMe(me));
  return HomeData(me: me, decks: results[1] as DeckList, week: await week);
});

/// Statistiky for all decks (null) or one deck.
final statsProvider = FutureProvider.autoDispose.family<Stats, int?>(
  (ref, deckId) => ref.watch(apiClientProvider).stats(deckId: deckId),
);

/// Moje nákupy, newest first.
final claimsProvider = FutureProvider.autoDispose<List<Claim>>((ref) => ref.watch(apiClientProvider).claims());

/// Obchod: items, hearts and balance.
class ShopController extends AsyncNotifier<Shop> {
  @override
  Future<Shop> build() => ref.watch(apiClientProvider).shop();

  /// Hearts or un-hearts [item] right away; reverts if the server refuses.
  Future<void> toggleWishlist(ShopItem item) async {
    final shop = state.value;
    if (shop == null) return;
    final next = item.copyWith(wishlisted: !item.wishlisted);
    state = AsyncData(shop.withItem(next));
    try {
      await ref.read(apiClientProvider).setWishlist(item.id, on: next.wishlisted);
    } on ApiException {
      final now = state.value;
      if (ref.mounted && now != null) state = AsyncData(now.withItem(item));
      rethrow;
    }
  }

  /// Buys [item]. The same [requestId] makes a retry safe. Reloads the shop, claims and Domů.
  Future<void> buy(ShopItem item, String requestId) async {
    await ref.read(apiClientProvider).claim(item.id, requestId);
    if (!ref.mounted) return;
    ref
      ..invalidate(claimsProvider)
      ..invalidate(homeProvider)
      ..invalidateSelf();
  }
}

final shopProvider = AsyncNotifierProvider.autoDispose<ShopController, Shop>(ShopController.new);

/// Everything that changes after a study session or a purchase.
void invalidateProgress(WidgetRef ref) {
  ref
    ..invalidate(homeProvider)
    ..invalidate(statsProvider)
    ..invalidate(shopProvider);
}
