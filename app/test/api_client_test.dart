import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/api/api_client.dart';
import 'package:quizly/core/api/api_exception.dart';
import 'package:quizly/core/api/models.dart';
import 'package:quizly/core/storage/token_store.dart';

final now = DateTime.utc(2026, 11, 2, 8);

AuthTokens tokens(String access, String refresh, {Duration validFor = const Duration(minutes: 60)}) => AuthTokens(
      accessToken: access,
      accessTokenExpiresAt: now.add(validFor),
      refreshToken: refresh,
      refreshTokenExpiresAt: now.add(const Duration(days: 90)),
      user: const AppUser(id: 2, username: 'jakub', displayName: 'Jakub'),
    );

Map<String, Object?> tokenJson(String access, String refresh) => tokens(access, refresh).toJson();

const settingsJson = {
  'dailyGoal': 20, 'newCardsPerDay': 5, 'notificationsEnabled': true,
  'morningTime': '08:00', 'eveningTime': '18:30', 'lastCallTime': '21:00',
  'quietFrom': '22:00', 'quietTo': '07:00', 'smartTimes': true,
};

/// A fake server: `/auth/refresh` rotates tokens, everything else needs the current access token.
class FakeServer implements HttpClientAdapter {
  String validAccess = 'A1';
  String validRefresh = 'R1';
  int refreshCalls = 0;
  bool rejectRefresh = false;
  final requests = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = options.uri.path;
    requests.add('${options.method} $path ${options.headers['Authorization'] ?? ''}'.trim());
    if (path == '/api/auth/refresh') {
      refreshCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final body = jsonDecode(await utf8.decodeStream(requestStream!)) as Map<String, Object?>;
      if (rejectRefresh || body['refreshToken'] != validRefresh) {
        return _json(401, {'code': 'refreshTokenInvalid', 'title': 'Přihlas se znovu.'});
      }
      validAccess = 'A${refreshCalls + 1}';
      validRefresh = 'R${refreshCalls + 1}';
      return _json(200, tokenJson(validAccess, validRefresh));
    }
    if (options.headers['Authorization'] != 'Bearer $validAccess') {
      return _json(401, {'code': 'unauthorized', 'title': 'Nepřihlášeno.'});
    }
    return _json(200, settingsJson);
  }

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  late FakeServer server;
  late MemoryTokenStore store;

  ApiClient client() {
    final dio = Dio()..httpClientAdapter = server;
    return ApiClient(baseUrl: 'https://quizly.test', store: store, dio: dio, now: () => now);
  }

  setUp(() {
    server = FakeServer();
    store = MemoryTokenStore(tokens('A1', 'R1'));
  });

  test('sends the stored access token', () async {
    final c = client();
    expect((await c.restore())!.username, 'jakub');
    final settings = await c.settings();
    expect(settings.dailyGoal, 20);
    expect(server.requests.single, 'GET /api/me/settings Bearer A1');
  });

  test('after a 401 it refreshes once for concurrent requests and repeats them', () async {
    final c = client();
    await c.restore();
    // The server already rotated A1 away; both requests get 401 and wait for one refresh.
    server.validAccess = 'X';
    final results = await Future.wait([c.settings(), c.settings()]);
    expect(results, hasLength(2));
    expect(server.refreshCalls, 1);
    expect(store.tokens!.refreshToken, 'R2');
    expect(server.requests.where((r) => r.endsWith('Bearer A2')), hasLength(2));
  });

  test('refreshes ahead of time when the access token is about to expire', () async {
    store = MemoryTokenStore(tokens('A1', 'R1', validFor: const Duration(seconds: 10)));
    final c = client();
    await c.restore();
    await c.settings();
    expect(server.refreshCalls, 1);
    expect(server.requests.first, 'POST /api/auth/refresh');
    expect(server.requests.last, 'GET /api/me/settings Bearer A2');
  });

  test('a rejected refresh token signs out and clears the stored login', () async {
    server
      ..validAccess = 'X'
      ..rejectRefresh = true;
    final c = client();
    await c.restore();
    final reasons = <SignOutReason>[];
    c.signedOut.listen(reasons.add);
    await expectLater(c.settings(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
    await pumpEventQueue();
    expect(reasons, [SignOutReason.sessionExpired]);
    expect(store.tokens, isNull);
    expect(c.user, isNull);
  });

  test('network failures become ApiException(network)', () async {
    final dio = Dio()
      ..httpClientAdapter = _Offline();
    final c = ApiClient(baseUrl: 'https://quizly.test', store: store, dio: dio, now: () => now);
    await c.restore();
    await expectLater(
      c.settings(),
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue).having((e) => e.isTransient, 'transient', isTrue)),
    );
    expect(store.tokens, isNotNull);
  });
  test('a network failure while refreshing is reported as network, not 401, and keeps the login', () async {
    store = MemoryTokenStore(tokens('A1', 'R1', validFor: const Duration(seconds: 10)));
    final dio = Dio()..httpClientAdapter = _Offline();
    final c = ApiClient(baseUrl: 'https://quizly.test', store: store, dio: dio, now: () => now);
    await c.restore();
    await expectLater(c.settings(), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue)));
    expect(store.tokens!.refreshToken, 'R1');
    expect(c.user, isNotNull);
  });
}

class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      Future.error(DioException.connectionError(requestOptions: options, reason: 'offline'));

  @override
  void close({bool force = false}) {}
}
