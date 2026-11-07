import '../notifications/notification_store.dart';

/// Remembers whether the one-time intro after the first login was shown (#41).
///
/// Stored in [KeyValueStore] (SharedPreferences on Android). Existing users see it
/// once after the update that brings it; later updates keep the flag and never run
/// the intro a second time. Storage errors never
/// block the app: the state is then kept in memory for this run.
class OnboardingStore {
  OnboardingStore(this._store);

  static const _key = 'quizly.onboarding';
  static const _pendingValue = 'pending';
  static const _doneValue = 'done';

  final KeyValueStore _store;
  bool _done = false;
  bool _pending = false;

  bool get isDone => _done;
  bool get isPending => _pending;

  /// Restores the state at app start (before the first frame).
  ///
  /// - `done`: the intro was finished; no later update shows it again.
  /// - `pending`: the app was closed during the intro; it comes back if the user is still signed in.
  /// - nothing saved and [alreadySignedIn]: the update that brings the intro; existing users see it once now.
  /// - nothing saved and signed out: the intro starts after the next login.
  Future<void> init({required bool alreadySignedIn}) async {
    final raw = await _read();
    if (raw == _doneValue) {
      _done = true;
      _pending = false;
    } else if (raw == _pendingValue) {
      _done = false;
      _pending = alreadySignedIn;
    } else if (alreadySignedIn) {
      _done = false;
      _pending = true;
      await _write(_pendingValue);
    }
  }

  /// Called right after `POST /api/auth/login` succeeds. Returns true when the intro should now be shown.
  Future<bool> onLogin() async {
    if (!_done && await _read() == _doneValue) _done = true;
    if (_done) {
      _pending = false;
      return false;
    }
    _pending = true;
    await _write(_pendingValue);
    return true;
  }

  /// Marks the intro as finished for good.
  Future<void> complete() async {
    _done = true;
    _pending = false;
    await _write(_doneValue);
  }

  Future<String?> _read() async {
    try {
      return await _store.read(_key);
    } on Object {
      return null;
    }
  }

  Future<void> _write(String value) async {
    try {
      await _store.write(_key, value);
    } on Object {
      // Kept in memory for this run; the worst case is the intro once more after a restart.
    }
  }
}
