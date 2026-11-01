import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/models.dart';
import 'planner.dart';

/// String key-value storage for the notification cache.
abstract interface class KeyValueStore {
  Future<String?> read(String key);

  /// Writes [value], or removes the key when it's null.
  Future<void> write(String key, String? value);
}

/// SharedPreferences without the in-memory cache, because the background refresh
/// writes from another isolate.
class PrefsKeyValueStore implements KeyValueStore {
  final _prefs = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String? value) => value == null ? _prefs.remove(key) : _prefs.setString(key, value);
}

class MemoryKeyValueStore implements KeyValueStore {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String? value) async => value == null ? data.remove(key) : data[key] = value;
}

/// What the planner needs, cached on the device (docs/notifications.md §2).
class NotificationCache {
  NotificationCache(this._store);

  final KeyValueStore _store;

  static const _settings = 'quizly.notify.settings';
  static const _snapshot = 'quizly.notify.snapshot';
  static const _texts = 'quizly.notify.texts';
  static const _history = 'quizly.notify.history';
  static const _asked = 'quizly.notify.asked';

  Future<T?> _get<T>(String key, T Function(Json json) parse) async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    try {
      return parse(jsonDecode(raw) as Json);
    } on Object {
      // A cache from an older app version; it's refilled from the server.
      return null;
    }
  }

  Future<void> _put(String key, Json? json) => _store.write(key, json == null ? null : jsonEncode(json));

  Future<UserSettings?> settings() => _get(_settings, UserSettings.fromJson);
  Future<void> saveSettings(UserSettings? value) => _put(_settings, value?.toJson());

  Future<ProgressSnapshot?> snapshot() => _get(_snapshot, ProgressSnapshot.fromJson);
  Future<void> saveSnapshot(ProgressSnapshot? value) => _put(_snapshot, value?.toJson());

  Future<NotificationTexts?> texts() => _get(_texts, NotificationTexts.fromJson);
  Future<void> saveTexts(NotificationTexts value) => _put(_texts, value.toJson());

  Future<TextHistory> history() async => await _get(_history, TextHistory.fromJson) ?? const TextHistory();
  Future<void> saveHistory(TextHistory value) => _put(_history, value.toJson());

  /// Whether the Domů explainer was answered (asked once per device).
  Future<bool> asked() async => await _store.read(_asked) != null;
  Future<void> setAsked() => _store.write(_asked, '1');

  /// Forgets the user's numbers and settings; texts and history stay for the next login.
  Future<void> clearUser() async {
    await saveSettings(null);
    await saveSnapshot(null);
  }
}
