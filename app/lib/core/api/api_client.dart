import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/token_store.dart';
import 'api_exception.dart';
import 'models.dart';

/// Why the app went back to the login screen.
enum SignOutReason { userLoggedOut, sessionExpired, accountDisabled }

/// REST client for `/api` with JWT auth and automatic token refresh (api.md §11.8).
///
/// - The access token is refreshed ahead of time when it's about to expire, and once more
///   after a `401 unauthorized`. Concurrent requests wait for a single refresh.
/// - When the refresh token is rejected the stored login is cleared and [signedOut] fires.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this._store,
    Dio? dio,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api'
      ..connectTimeout = timeout
      ..sendTimeout = timeout
      ..receiveTimeout = timeout
      ..contentType = Headers.jsonContentType
      ..responseType = ResponseType.json;
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

  /// Request timeout (api.md §11.6).
  static const timeout = Duration(seconds: 10);

  /// Refresh this long before the access token expires.
  static const _refreshAhead = Duration(seconds: 30);

  final TokenStore _store;
  final DateTime Function() _now;
  final Dio _dio;
  final _signedOut = StreamController<SignOutReason>.broadcast();

  AuthTokens? _tokens;
  Future<bool>? _refreshing;

  /// The logged-in user, or null.
  AppUser? get user => _tokens?.user;

  /// Fires when the login ends (logout, rejected refresh token, deactivated account).
  Stream<SignOutReason> get signedOut => _signedOut.stream;

  /// Loads the stored login. Returns the user if there is one.
  Future<AppUser?> restore() async {
    final tokens = await _store.read();
    if (tokens != null && tokens.refreshTokenExpiresAt.isBefore(_now())) {
      await _store.clear();
      return null;
    }
    _tokens = tokens;
    return tokens?.user;
  }

  Future<AppUser> login(String username, String password, {String? deviceName}) async {
    final json = await _send<Json>('POST', '/auth/login', auth: false, data: {
      'username': username,
      'password': password,
      'deviceName': ?deviceName,
    });
    final tokens = AuthTokens.fromJson(json);
    await _setTokens(tokens);
    return tokens.user;
  }

  /// Revokes the refresh token (best effort) and forgets the login.
  Future<void> logout() async {
    final refreshToken = _tokens?.refreshToken;
    await _setTokens(null);
    _signedOut.add(SignOutReason.userLoggedOut);
    if (refreshToken == null) return;
    try {
      await _send<void>('POST', '/auth/logout', auth: false, data: {'refreshToken': refreshToken});
    } on ApiException {
      // Already logged out locally; the token expires on its own.
    }
  }

  Future<Me> me() async => Me.fromJson(await _send<Json>('GET', '/me'));

  Future<UserSettings> settings() async => UserSettings.fromJson(await _send<Json>('GET', '/me/settings'));

  Future<SettingsUpdate> saveSettings(UserSettings settings) async =>
      SettingsUpdate.fromJson(await _send<Json>('PUT', '/me/settings', data: settings.toJson()));

  Future<DeckList> decks() async => DeckList.fromJson(await _send<Json>('GET', '/decks'));

  Future<DeckCards> deckCards(int deckId) async =>
      DeckCards.fromJson(await _send<Json>('GET', '/decks/$deckId/cards'));

  /// Changes my password. The server signs out every other device and returns new tokens for this one.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final json = await _send<Json>('POST', '/me/password', data: {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
    await _setTokens(AuthTokens.fromJson(json));
  }

  Future<SessionData> session({int? deckId}) async =>
      SessionData.fromJson(await _send<Json>('GET', '/session', query: {'deckId': ?deckId}));

  Future<ReviewBatchResult> postReviews(List<ReviewItem> reviews) async => ReviewBatchResult.fromJson(
        await _send<Json>('POST', '/reviews', data: {'reviews': [for (final r in reviews) r.toJson()]}),
      );

  Future<Stats> stats({int? deckId}) async =>
      Stats.fromJson(await _send<Json>('GET', '/stats', query: {'deckId': ?deckId}));

  Future<Shop> shop() async => Shop.fromJson(await _send<Json>('GET', '/shop'));

  /// Buys a reward and returns the new balance. Retrying with the same [requestId]
  /// returns the same purchase (api.md §8).
  Future<int> claim(int itemId, String requestId) async {
    final json = await _send<Json>('POST', '/shop/$itemId/claim', data: {'requestId': requestId});
    return (json['balance'] as num).toInt();
  }

  Future<List<Claim>> claims() async {
    final json = await _send<Json>('GET', '/claims');
    return [for (final c in json['items'] as List) Claim.fromJson(c as Json)];
  }

  /// Hearts ([on]) or un-hearts an item. Both are idempotent.
  Future<void> setWishlist(int itemId, {required bool on}) =>
      _send<Object?>(on ? 'PUT' : 'DELETE', '/wishlist/$itemId');

  Future<T> _send<T>(String method, String path, {Object? data, Map<String, Object?>? query, bool auth = true}) async {
    try {
      final response = await _dio.request<T>(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method, extra: {'auth': auth}),
      );
      return response.data as T;
    } on DioException catch (e) {
      throw e.error is ApiException ? e.error! as ApiException : ApiException.fromDio(e);
    }
  }

  Future<void> _setTokens(AuthTokens? tokens) async {
    _tokens = tokens;
    if (tokens == null) {
      await _store.clear();
    } else {
      await _store.write(tokens);
    }
  }

  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['auth'] == false) return handler.next(options);
    if (_tokens != null && _tokens!.accessTokenExpiresAt.difference(_now()) < _refreshAhead) {
      try {
        await _refresh();
      } on ApiException catch (e) {
        return handler.reject(DioException(requestOptions: options, error: e));
      }
    }
    final tokens = _tokens;
    if (tokens == null) {
      return handler.reject(
        DioException(requestOptions: options, error: const ApiException(status: 401, code: 'unauthorized')),
      );
    }
    options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    handler.next(options);
  }

  Future<void> _onError(DioException error, ErrorInterceptorHandler handler) async {
    final options = error.requestOptions;
    final problem = ApiException.fromDio(error);
    if (problem.code == 'accountDisabled' && options.extra['auth'] != false && _tokens != null) {
      await _setTokens(null);
      _signedOut.add(SignOutReason.accountDisabled);
      return handler.next(error);
    }
    final canRetry = options.extra['auth'] != false && options.extra['retried'] != true;
    if (problem.code != 'unauthorized' || !canRetry) return handler.next(error);

    final sentWith = options.headers['Authorization'];
    // Another request may have refreshed already; only refresh if our token is still current.
    final current = _tokens == null ? null : 'Bearer ${_tokens!.accessToken}';
    final bool ok;
    try {
      ok = sentWith != current || await _refresh(force: true);
    } on ApiException catch (e) {
      // The refresh itself failed (network, 5xx): report that, not the 401, so callers retry.
      return handler.next(DioException(requestOptions: options, error: e));
    }
    if (!ok || _tokens == null) return handler.next(error);
    try {
      options.extra['retried'] = true;
      handler.resolve(await _dio.fetch<Object?>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Rotates the tokens once, however many requests ask at the same time.
  /// Returns false when the login ended; throws [ApiException] when the refresh couldn't be done now.
  Future<bool> _refresh({bool force = false}) {
    return _refreshing ??= _doRefresh(force).whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh(bool force) async {
    final tokens = _tokens;
    if (tokens == null) return false;
    if (!force && tokens.accessTokenExpiresAt.difference(_now()) >= _refreshAhead) return true;
    try {
      final json = await _send<Json>('POST', '/auth/refresh', auth: false, data: {'refreshToken': tokens.refreshToken});
      await _setTokens(AuthTokens.fromJson(json));
      return true;
    } on ApiException catch (e) {
      if (e.code == 'refreshTokenInvalid' || e.code == 'accountDisabled') {
        await _setTokens(null);
        _signedOut.add(e.code == 'accountDisabled' ? SignOutReason.accountDisabled : SignOutReason.sessionExpired);
        return false;
      }
      debugPrint('Token refresh failed: ${e.code}');
      rethrow;
    }
  }
}
