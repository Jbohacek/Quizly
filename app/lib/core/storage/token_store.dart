import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/models.dart';

/// Keeps the login (tokens + user) between app starts. The user stays logged in until logout.
abstract interface class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

/// Android Keystore-backed storage (flutter_secure_storage).
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'quizly.auth';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthTokens?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null ? null : AuthTokens.fromJson(jsonDecode(raw) as Json);
    } on Object {
      // Unreadable (e.g. keystore reset after a restore): treat as logged out.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthTokens tokens) => _storage.write(key: _key, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// In-memory store for tests.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.tokens]);

  AuthTokens? tokens;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens tokens) async => this.tokens = tokens;

  @override
  Future<void> clear() async => tokens = null;
}
