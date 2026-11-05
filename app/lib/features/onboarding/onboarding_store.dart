import '../notifications/notification_store.dart';

/// Remembers whether the one-time intro after the first login was shown (#41).
///
/// Stored in [KeyValueStore] (SharedPreferences on Android), so an app update
/// keeps the flag and never runs the intro a second time.
class OnboardingStore {
  OnboardingStore(this._store);

  static const _key = 'quizly.onboarding';

  final KeyValueStore _store;
  bool _initialized = false;
  bool _done = false;
  bool _pending = false;

  bool get isDone => _done;
  bool get isPending => _pending;

  /// Restores the state at app start.
  ///
  /// If the user is [alreadySignedIn] when the app starts and no state was saved yet,
  /// this installation comes from an update of an earlier version: mark the intro as done
  /// so the update doesn't show it.
  Future<void> init({required bool alreadySignedIn}) async {
    _initialized = true;
    final raw = await _store.read(_key);
    if (raw == 'done' || _done) {
      _done = true;
      _pending = false;
      return;
    }
    if (raw == 'pending') {
      _done = false;
      _pending = alreadySignedIn;
      return;
    }
    if (alreadySignedIn) {
      _done = true;
      _pending = false;
      await _store.write(_key, 'done');
    }
  }

  /// Fallback when a test builds the app without calling [init] first.
  void ensureInitialized({required bool alreadySignedIn}) {
    if (_initialized) return;
    _initialized = true;
    if (alreadySignedIn) _done = true;
  }

  /// Called right after `POST /api/auth/login` succeeds.
  /// Returns true when the intro should now be shown.
  Future<bool> onLogin() async {
    final raw = await _store.read(_key);
    if (_done || raw == 'done') {
      _done = true;
      _pending = false;
      return false;
    }
    _pending = true;
    await _store.write(_key, 'pending');
    return true;
  }

  /// Marks the intro as finished for good.
  Future<void> complete() async {
    _done = true;
    _pending = false;
    await _store.write(_key, 'done');
  }
}
