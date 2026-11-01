import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/api/api_client.dart';
import 'package:quizly/core/api/models.dart';
import 'package:quizly/core/providers.dart';
import 'package:quizly/core/storage/token_store.dart';
import 'package:quizly/features/session/review_sync.dart';
import 'package:quizly/main.dart';

/// A small in-memory Quizly API: two cards in one deck.
class FakeApi implements HttpClientAdapter {
  int balance = 1240;
  int graded = 0;
  final reviewed = <Map<String, Object?>>[];

  Map<String, Object?> get summary => {
        'balance': balance,
        'streak': 12,
        'bestStreak': 21,
        'multiplier': 1.1,
        'nextMultiplier': {'value': 1.2, 'inDays': 2},
        'today': {'date': '2026-11-02', 'graded': graded, 'correct': graded, 'goal': 20, 'goalMet': false, 'points': 0},
        'streakBroken': null,
      };

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final route = '${options.method} ${options.uri.path}';
    final body = requestStream == null ? null : jsonDecode(await utf8.decodeStream(requestStream));
    return switch (route) {
      'POST /api/auth/login' => _json({
          'accessToken': 'A',
          'accessTokenExpiresAt': '2099-01-01T00:00:00Z',
          'refreshToken': 'R',
          'refreshTokenExpiresAt': '2099-01-01T00:00:00Z',
          'user': {'id': 2, 'username': 'kuba', 'displayName': 'Kuba'},
        }),
      'GET /api/me' => _json({
          'user': {'id': 2, 'username': 'kuba', 'displayName': 'Kuba'},
          'summary': summary,
          'dueNow': 2,
          'forecast': {'nextMorning': '2026-11-03T07:00:00Z', 'dueByNextMorning': 5},
          'smartEveningTime': null,
          'serverTime': '2026-11-02T16:40:12Z',
        }),
      'GET /api/decks' => _json({
          'items': [
            {
              'id': 1, 'name': 'C# základy', 'description': '', 'color': '#BAD69B',
              'totalCards': 84, 'dueNow': 2, 'newAvailable': 0, 'masteredPercent': 62,
            },
          ],
          'newAllowanceLeft': 0,
        }),
      'GET /api/session' => _json({
          'deckId': null,
          'multiplier': 1.1,
          'points': {'know': 11, 'dontKnow': 2},
          'dueCount': 2,
          'newCount': 0,
          'cards': [
            {'cardId': 101, 'deckId': 1, 'question': 'Co je struct?', 'answer': 'Hodnotový typ.', 'kind': 'review'},
            {'cardId': 102, 'deckId': 1, 'question': 'Co je class?', 'answer': 'Referenční typ.', 'kind': 'new'},
          ],
        }),
      'POST /api/reviews' => _reviews(body as Map<String, Object?>),
      _ => _json({'code': 'notFound', 'title': 'Nenalezeno.'}, 404),
    };
  }

  ResponseBody _reviews(Map<String, Object?> body) {
    final results = <Object>[];
    for (final r in (body['reviews']! as List).cast<Map<String, Object?>>()) {
      reviewed.add(r);
      final points = r['rating'] == 'know' ? 11 : 2;
      balance += points;
      graded++;
      results.add({'id': r['id'], 'status': 'applied', 'pointsAwarded': points, 'multiplier': 1.1});
    }
    return _json({'results': results, 'summary': summary, 'points': {'know': 11, 'dontKnow': 2}, 'events': []});
  }

  ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('log in, study two cards (one Nevím re-queued), see Hotovo, back home', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final api = FakeApi();
    final client = ApiClient(
      baseUrl: 'https://quizly.test',
      store: MemoryTokenStore(),
      dio: Dio()..httpClientAdapter = api,
    );

    await tester.pumpWidget(ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        apiClientProvider.overrideWithValue(client),
        outboxStoreProvider.overrideWithValue(MemoryOutboxStore()),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const QuizlyApp(),
    ));
    await settle(tester);

    // Přihlášení
    expect(find.text('Přihlásit se'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Kuba');
    await tester.enterText(find.byType(TextField).at(1), 'tajneheslo');
    await tester.tap(find.text('Přihlásit se'));
    await settle(tester);

    // Domů
    expect(find.text('Ahoj, Kuba!'), findsOneWidget);
    expect(find.text('1 240'), findsOneWidget);
    expect(find.text('dní v řadě'), findsOneWidget);
    expect(find.text('Za 2 dny násobič stoupne na 1,2×'), findsOneWidget);
    expect(find.text('C# základy'), findsOneWidget);
    await tester.tap(find.text('Učit se vše · 2 karty'));
    await settle(tester);

    // Učení: card 1 of 2, flip, Nevím
    expect(find.text('Karta 1 z 2'), findsOneWidget);
    expect(find.text('Co je struct?'), findsOneWidget);
    await tester.tap(find.text('Co je struct?'));
    await settle(tester);
    expect(find.text('Hodnotový typ.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Nevím').first);
    await settle(tester);

    // Re-queued: the total grows to 3, card 2 is next.
    expect(find.text('Karta 2 z 3'), findsOneWidget);
    expect(find.text('Co je class?'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Vím').first);
    await settle(tester);

    expect(find.text('Karta 3 z 3'), findsOneWidget);
    expect(find.text('Co je struct?'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Vím').first);
    await settle(tester);

    // Hotovo
    expect(find.text('Hotovo!'), findsOneWidget);
    expect(find.text('+24'), findsOneWidget);
    expect(find.text('67 %'), findsOneWidget);
    expect(find.text('1 264 bodů'), findsOneWidget);
    expect(api.reviewed.map((r) => (r['cardId'], r['rating'])), [(101, 'dontKnow'), (102, 'know'), (101, 'know')]);
    expect(api.reviewed.map((r) => r['id']).toSet(), hasLength(3));

    await tester.tap(find.text('Hotovo').last);
    await settle(tester);
    expect(find.text('Ahoj, Kuba!'), findsOneWidget);
  });
  testWidgets('answers left in the outbox from the last run are sent when the app starts', (tester) async {
    final api = FakeApi();
    final outbox = MemoryOutboxStore()
      ..data[2] = [const ReviewItem(id: '6f1c2a7e-3b0c-4f6e-9d51-0a2b7c9e1f42', cardId: 101, rating: Rating.know)];
    final store = MemoryTokenStore(AuthTokens(
      accessToken: 'A',
      accessTokenExpiresAt: DateTime.utc(2099),
      refreshToken: 'R',
      refreshTokenExpiresAt: DateTime.utc(2099),
      user: const AppUser(id: 2, username: 'kuba', displayName: 'Kuba'),
    ));
    final client = ApiClient(baseUrl: 'https://quizly.test', store: store, dio: Dio()..httpClientAdapter = api);
    await client.restore();

    await tester.pumpWidget(ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        apiClientProvider.overrideWithValue(client),
        outboxStoreProvider.overrideWithValue(outbox),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: const QuizlyApp(),
    ));
    await settle(tester);

    expect(find.text('Ahoj, Kuba!'), findsOneWidget);
    expect(api.reviewed.single['cardId'], 101);
    expect(outbox.data[2], isEmpty);
    // Home was refreshed after the leftover answer went in.
    expect(find.text('1 251'), findsOneWidget);
  });
}
