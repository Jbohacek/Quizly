import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/api/api_client.dart';
import 'package:quizly/core/api/models.dart';
import 'package:quizly/core/format.dart';
import 'package:quizly/core/providers.dart';
import 'package:quizly/core/storage/token_store.dart';
import 'package:quizly/core/strings.dart';
import 'package:quizly/core/theme/tokens.dart';
import 'package:quizly/core/widgets/widgets.dart';
import 'package:quizly/features/cards/card_editor.dart';
import 'package:quizly/features/home/deck_screen.dart';
import 'package:quizly/features/notifications/notification_store.dart';
import 'package:quizly/features/notifications/notifications.dart';
import 'package:quizly/features/notifications/planner.dart';
import 'package:quizly/features/onboarding/onboarding_screen.dart';
import 'package:quizly/features/onboarding/onboarding_store.dart';
import 'package:quizly/features/session/review_sync.dart';
import 'package:quizly/features/session/swipe_card.dart';
import 'package:quizly/features/updates/app_update.dart';
import 'package:quizly/main.dart';
import 'package:quizly/router.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'fakes.dart';

/// A small in-memory Quizly API: two cards in one deck.
class FakeApi implements HttpClientAdapter {
  int balance = 1240;
  int graded = 0;
  final reviewed = <Map<String, Object?>>[];
  String password = 'tajneheslo';
  bool hasDeckCards = true;
  int passwordChanges = 0;
  int dueNow = 2;

  /// The admin keeps this user out of the shop when false.
  bool shopEnabled = true;

  /// `GET /api/app/latest` (docs/api.md §15): null = nothing to offer.
  Map<String, Object?>? appLatest;
  bool apkFails = false;
  int apkDownloads = 0;
  final sessionQueries = <Map<String, String>>[];

  /// Card edits from the app (#23): "METHOD path" with the body.
  final cardRequests = <(String, Object?)>[];
  final editedCards = <int, ({String question, String answer, List<Object?>? tags})>{};
  final deletedCards = <int>{};
  final addedCards = <Map<String, Object?>>[];
  final savedSettings = <Map<String, Object?>>[];

  /// `GET` / `PUT /api/me/settings` answer 503 while true (#41: onboarding without the settings).
  bool settingsLoadFails = false;
  bool settingsSaveFails = false;
  Map<String, Object?> settings = {
    'dailyGoal': 20, 'newCardsPerDay': 5, 'notificationsEnabled': true,
    'morningTime': '08:00', 'eveningTime': '18:30', 'lastCallTime': '21:00',
    'quietFrom': '22:00', 'quietTo': '07:00', 'smartTimes': true,
  };

  /// Events returned with every review batch.
  List<Map<String, Object?>> reviewEvents = [];
  final statsQueries = <String?>[];
  final wishlistCalls = <String>[];
  final claimRequests = <String>[];

  /// Rewards: id → (name, price, stock, hearted).
  final items = <int, ({String name, int price, int stock, bool hearted})>{
    1: (name: 'Jít na pizzu', price: 500, stock: 1, hearted: false),
    2: (name: 'Večer v kině', price: 1500, stock: 2, hearted: true),
    3: (name: 'Sladká odměna', price: 80, stock: 0, hearted: false),
  };
  final claims = <Map<String, Object?>>[
    {
      'id': 7, 'itemId': 3, 'itemName': 'Sladká odměna', 'price': 80, 'status': 'confirmed',
      'createdAt': '2026-10-24T10:00:00Z', 'decidedAt': '2026-10-24T12:00:00Z',
    },
  ];

  Map<String, Object?> get shop => {
        'balance': balance,
        'items': [
          for (final MapEntry(key: id, value: i) in items.entries)
            {
              'id': id, 'name': i.name, 'description': id == 1 ? 'Večeře podle tvého výběru.' : '',
              'price': i.price, 'stock': i.stock, 'initialStock': 3, 'soldOut': i.stock == 0,
              'wishlisted': i.hearted, 'missing': i.price > balance ? i.price - balance : 0,
            },
        ],
      };

  /// Today is Wednesday 2026-11-04: Monday met, Tuesday below the goal, today open.
  Map<String, Object?> stats(String? deckId) => {
        'deckId': deckId == null ? null : int.parse(deckId),
        'tiles': {
          'streak': 12, 'bestStreak': 21, 'successRate30d': 81,
          'sparkline': [for (var i = 0; i < 30; i++) i % 6 == 0 ? null : 70 + i % 9],
          'totalReviews': 1284, 'totalPointsEarned': 14920,
        },
        'heatmap': {
          'from': '2026-07-13', 'to': '2026-11-08', 'today': '2026-11-04',
          'weeks': [
            for (var w = 0; w < 16; w++) [2, 3, 0, 4, 1, 2, 2],
            [3, 1, 0, null, null, null, null],
          ],
        },
        'daily': {
          'goal': 20,
          'days': [
            for (var i = 0; i < 14; i++)
              {'date': DateTime.utc(2026, 10, 22 + i).toIso8601String().substring(0, 10), 'graded': 10 + i * 2},
          ],
        },
        'weekdays': [
          for (final (i, rate) in [78, 80, 79, 88, 74, 70, null].indexed)
            {'weekday': i + 1, 'successRate': rate, 'graded': rate == null ? 4 : 60},
        ],
        'bestTime': {'from': '19:00', 'to': '21:00', 'successRate': 91, 'graded': 140},
        'deckProgress': [
          {'deckId': 1, 'name': 'C# základy', 'mastered': 52, 'learning': 24, 'new': 8},
        ],
        'totalProgress': {'mastered': 52, 'learning': 24, 'new': 8},
      };

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
          'user': {'id': 2, 'username': 'kuba', 'displayName': 'Kuba', 'shopEnabled': shopEnabled},
          'summary': summary,
          'dueNow': dueNow,
          'forecast': {'nextMorning': '2026-11-03T07:00:00Z', 'dueByNextMorning': 5},
          'smartEveningTime': null,
          'serverTime': '2026-11-02T16:40:12Z',
        }),
      'GET /api/decks' => _json({
          'items': [
            {
              'id': 1, 'name': 'C# základy', 'description': '', 'color': '#BAD69B',
              'totalCards': 84, 'dueNow': dueNow, 'newAvailable': 0, 'masteredPercent': 62,
              'learningPercent': 20, 'unseenCards': 9,
            },
          ],
          'newAllowanceLeft': 0,
        }),
      'GET /api/session' when (sessionQueries..add(options.uri.queryParameters)).isNotEmpty => _json({
          'deckId': null,
          'multiplier': 1.1,
          'points': {'know': 11, 'dontKnow': 2, 'hard': 11, 'easy': 11},
          'dueCount': 2,
          'newCount': 0,
          'fourRatings': settings['fourRatings'] ?? false,
          'cards': [
            {
              'cardId': 101, 'deckId': 1, 'question': 'Co je struct?', 'answer': 'Hodnotový typ.', 'kind': 'review',
              'tags': ['ai_gen', 'prednaska_01'],
              'intervals': {'dontKnow': 600, 'hard': 172800, 'know': 345600, 'easy': 691200},
              'relearnIntervals': {'dontKnow': 600, 'hard': 900, 'know': 86400, 'easy': 259200},
            },
            {
              'cardId': 102, 'deckId': 1, 'question': 'Co je class?', 'answer': 'Referenční typ.', 'kind': 'new',
              'intervals': {'dontKnow': 60, 'hard': 330, 'know': 600, 'easy': 691200},
              'relearnIntervals': {'dontKnow': 60, 'hard': 330, 'know': 600, 'easy': 691200},
            },
          ],
        }),
      'POST /api/reviews' => _reviews(body as Map<String, Object?>),
      'GET /api/decks/1/cards' when !hasDeckCards => _json({'code': 'notFound', 'title': 'Tohle jsme nenašli.'}, 404),
      'GET /api/decks/1/cards' => _json({
          'deck': {
            'id': 1, 'name': 'C# základy', 'description': 'Základní pojmy jazyka C#', 'color': '#BAD69B',
            'totalCards': 3, 'dueNow': 1, 'newAvailable': 1, 'masteredPercent': 33,
            'learningPercent': 33, 'unseenCards': 1,
          },
          'cards': [
            for (final c in <Map<String, Object?>>[
              {
                'id': 101, 'question': 'Co je struct?', 'answer': 'Hodnotový typ.', 'status': 'mastered',
                'masteryPercent': 100, 'knowCount': 6, 'dontKnowCount': 0, 'nextReview': '2099-01-01T08:00:00Z',
                'tags': ['ai_gen', 'prednaska_01'],
              },
              {
                'id': 102, 'question': 'Co je class?', 'answer': '**Referenční** typ.', 'status': 'learning',
                'masteryPercent': 45, 'knowCount': 3, 'dontKnowCount': 1, 'nextReview': '2026-11-01T08:00:00Z',
              },
              {'id': 103, 'question': 'Co je record?', 'answer': 'Typ s hodnotovou rovností.', 'status': 'new'},
              ...addedCards,
            ])
              if (!deletedCards.contains(c['id']))
                {
                  ...c,
                  if (editedCards[c['id']] case final e?) ...{
                    'question': e.question,
                    'answer': e.answer,
                    if (e.tags != null) 'tags': e.tags,
                  },
                },
          ],
        }),
      'POST /api/decks/1/cards' => _addCard(body as Map<String, Object?>),
      final r when r.startsWith('PUT /api/decks/1/cards/') => _editCard(r, body as Map<String, Object?>),
      final r when r.startsWith('DELETE /api/decks/1/cards/') => _deleteCard(r),
      'POST /api/me/password' => _changePassword(body as Map<String, Object?>),
      'GET /api/app/latest' => _json({'latest': appLatest}),
      'GET /api/app/apk' when (++apkDownloads > 0) && apkFails => _json({'code': 'notFound', 'title': 'Novou verzi aplikace teď nemáme.'}, 404),
      'GET /api/app/apk' => ResponseBody.fromBytes(List.filled(1234, 7), 200, headers: {
          Headers.contentTypeHeader: ['application/vnd.android.package-archive'],
          Headers.contentLengthHeader: ['1234'],
        }),
      'GET /api/stats' => _json(stats((statsQueries..add(options.uri.queryParameters['deckId'])).last)),
      'GET /api/leaderboard' => _json({
          'period': options.uri.queryParameters['period'] ?? 'week',
          'metric': options.uri.queryParameters['metric'] ?? 'points',
          'entries': [
            {'rank': 1, 'userId': 1, 'displayName': 'Admin', 'points': 500, 'currentStreak': 15, 'cardsStudied': 80},
            {'rank': 2, 'userId': 2, 'displayName': 'Kuba', 'points': 350, 'currentStreak': 12, 'cardsStudied': 50},
            {'rank': 3, 'userId': 3, 'displayName': 'Petra', 'points': 200, 'currentStreak': 8, 'cardsStudied': 30},
          ],
          'currentUserRank': 2,
        }),
      'GET /api/shop' => _json(shop),
      'GET /api/claims' => _json({'items': claims.reversed.toList()}),
      final r when r.startsWith('PUT /api/wishlist/') || r.startsWith('DELETE /api/wishlist/') => _wishlist(r),
      final r when r.startsWith('POST /api/shop/') => _claim(r, body as Map<String, Object?>),
      'GET /api/me/settings' when settingsLoadFails => _unavailable(),
      'GET /api/me/settings' => _json(settings),
      'PUT /api/me/settings' when settingsSaveFails => _unavailable(),
      'PUT /api/me/settings' => _json({
          'settings': settings = (savedSettings..add(body as Map<String, Object?>)).last,
          'summary': summary,
          'events': [],
        }),
      'GET /api/notification-texts' => _json({
          'version': 'v1',
          'categories': {
            'morning': [{'id': 1, 'text': 'Dobré ráno! Karty na dnešek: {due}'}],
            'evening': [{'id': 2, 'text': 'Už máš {done} z {goal}. Dáme ještě kousek?'}],
            'last_call': [{'id': 3, 'text': 'Série: {streak}. Pár karet a jede dál 🔥'}],
            'milestone': [{'id': 4, 'text': '{streak} dní v řadě! 🎉'}],
            'wishlist': [{'id': 5, 'text': 'Na „{item}“ už máš body 🎁'}],
            'comeback': [{'id': 6, 'text': 'Vítej zpátky 💚'}],
          },
        }),
      _ => _json({'code': 'notFound', 'title': 'Nenalezeno.'}, 404),
    };
  }

  ResponseBody _wishlist(String route) {
    wishlistCalls.add(route);
    final id = int.parse(route.split('/').last);
    final i = items[id]!;
    items[id] = (name: i.name, price: i.price, stock: i.stock, hearted: route.startsWith('PUT'));
    return ResponseBody.fromString('', 204);
  }

  ResponseBody _claim(String route, Map<String, Object?> body) {
    claimRequests.add(body['requestId']! as String);
    final id = int.parse(route.split('/')[3]);
    final i = items[id]!;
    if (i.price > balance) return _json({'code': 'insufficientBalance', 'title': 'Na tuhle odměnu ti zatím chybí body.'}, 409);
    balance -= i.price;
    items[id] = (name: i.name, price: i.price, stock: i.stock - 1, hearted: i.hearted);
    final claim = {
      'id': 8, 'itemId': id, 'itemName': i.name, 'price': i.price, 'status': 'pending',
      'createdAt': DateTime.now().toUtc().toIso8601String(), 'decidedAt': null,
    };
    claims.add(claim);
    return _json({'claim': claim, 'balance': balance}, 201);
  }

  ResponseBody _addCard(Map<String, Object?> body) {
    cardRequests.add(('POST', body));
    final card = {
      'id': 200 + addedCards.length, 'question': body['question'], 'answer': body['answer'], 'status': 'new',
      'tags': body['tags'] ?? [],
    };
    addedCards.add(card);
    return _json({...card, 'deckId': 1, 'sortOrder': 9}, 201);
  }

  ResponseBody _editCard(String route, Map<String, Object?> body) {
    cardRequests.add((route, body));
    final id = int.parse(route.split('/').last);
    // The server's tag rules, roughly: a "!" breaks them (#29).
    final tags = body['tags'] as List<Object?>?;
    if (tags != null && tags.any((t) => '$t'.contains('!'))) {
      return _json({
        'code': 'validation',
        'title': 'Některé údaje nejsou v pořádku.',
        'errors': {
          'tags': ['Tag smí mít jen malá písmena, číslice, _ a -.'],
        },
      }, 400);
    }
    editedCards[id] = (question: body['question']! as String, answer: body['answer']! as String, tags: tags);
    return _json({'id': id, 'deckId': 1, ...body});
  }

  ResponseBody _deleteCard(String route) {
    cardRequests.add((route, null));
    deletedCards.add(int.parse(route.split('/').last));
    return ResponseBody.fromString('', 204);
  }

  ResponseBody _changePassword(Map<String, Object?> body) {
    if (body['currentPassword'] != password) {
      return _json({
        'code': 'validation',
        'title': 'Některé údaje nejsou v pořádku.',
        'errors': {
          'currentPassword': ['Současné heslo nesedí.'],
        },
      }, 400);
    }
    password = body['newPassword']! as String;
    passwordChanges++;
    return _json({
      'accessToken': 'A2',
      'accessTokenExpiresAt': '2099-01-01T00:00:00Z',
      'refreshToken': 'R2',
      'refreshTokenExpiresAt': '2099-01-01T00:00:00Z',
      'user': {'id': 2, 'username': 'kuba', 'displayName': 'Kuba'},
    });
  }

  ResponseBody _reviews(Map<String, Object?> body) {
    final results = <Object>[];
    for (final r in (body['reviews']! as List).cast<Map<String, Object?>>()) {
      reviewed.add(r);
      final points = r['rating'] == 'dontKnow' ? 2 : 11;
      balance += points;
      graded++;
      results.add({'id': r['id'], 'status': 'applied', 'pointsAwarded': points, 'multiplier': 1.1});
    }
    return _json({'results': results, 'summary': summary, 'points': {'know': 11, 'dontKnow': 2}, 'events': reviewEvents});
  }

  ResponseBody _unavailable() => _json({'code': 'unavailable', 'title': 'Server teď neodpovídá.'}, 503);

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
  setUpAll(tzdata.initializeTimeZones);

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
        onboardingStoreProvider.overrideWithValue(await _onboarding()),
        outboxStoreProvider.overrideWithValue(MemoryOutboxStore()),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
        notificationsProvider.overrideWithValue(_notifications(FakeNotificationPlatform())),
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

    // Onboarding (#41): 5 steps + "Přeji hezkou zábavu!"
    expect(find.byType(OnboardingScreen), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text(S.next));
      await settle(tester);
    }
    expect(find.text(S.onboardingWelcomeTitle), findsOneWidget);
    await tester.tap(find.text(S.onboardingStart));
    await settle(tester);

    // Domů
    expect(find.text('Ahoj, Kuba!'), findsOneWidget);
    expect(find.text('1 240'), findsOneWidget);
    expect(find.text('dní v řadě'), findsOneWidget);
    expect(find.text('Za 2 dny násobič stoupne na 1,2×'), findsOneWidget);
    await _scrollTo(tester, find.text('C# základy'));
    expect(find.text('C# základy'), findsOneWidget);
    await _scrollTo(tester, find.textContaining('Učit se vše'));
    await tester.tap(find.text('Učit se vše · 2 karty'));
    await settle(tester);

    // Učení: card 1 of 2, flip, Nevím
    expect(find.text('Karta 1 z 2'), findsOneWidget);
    expect(find.text('Co je struct?'), findsOneWidget);
    await tester.tap(find.text('Co je struct?'));
    await settle(tester);
    expect(find.text('Hodnotový typ.'), findsOneWidget);
    await _answer(tester, 'Nevím');

    // Re-queued: the total grows to 3, card 2 is next.
    expect(find.text('Karta 2 z 3'), findsOneWidget);
    expect(find.text('Co je class?'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    await _answer(tester, 'Vím');

    expect(find.text('Karta 3 z 3'), findsOneWidget);
    expect(find.text('Co je struct?'), findsOneWidget);
    await _answer(tester, 'Vím');

    // Hotovo
    expect(find.text('Hotovo!'), findsOneWidget);
    expect(find.text('+24'), findsOneWidget);
    expect(find.text('67 %'), findsOneWidget);
    expect(find.text('1 264 bodů'), findsOneWidget);
    // The nearest wishlist reward: 1 500 − 1 264 = 236 points, 22 × Vím at 11 each.
    expect(find.text(S.fromWishlist), findsOneWidget);
    expect(find.text(S.wishlistLeft(236, 22)), findsOneWidget);
    expect(api.reviewed.map((r) => (r['cardId'], r['rating'])), [(101, 'dontKnow'), (102, 'know'), (101, 'know')]);
    expect(api.reviewed.map((r) => r['id']).toSet(), hasLength(3));

    await tester.ensureVisible(find.text('Hotovo').last);
    await tester.pump();
    await tester.tap(find.text('Hotovo').last);
    await settle(tester);
    await _scrollTo(tester, find.text('Ahoj, Kuba!'), up: true);
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
        onboardingStoreProvider.overrideWithValue(await _onboarding(done: true)),
        outboxStoreProvider.overrideWithValue(outbox),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
        notificationsProvider.overrideWithValue(_notifications(FakeNotificationPlatform())),
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
  testWidgets('a deck shows its cards with status; tapping a card shows the answer', (tester) async {
    final (api, _) = await _signedIn(tester);

    await _scrollTo(tester, find.text('C# základy'));
    await tester.tap(find.text('C# základy'));
    await settle(tester);

    expect(find.text('Základní pojmy jazyka C#'), findsOneWidget);
    expect(find.text('Učit se · 2 karty'), findsOneWidget);
    expect(find.text('33 %'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Nová'), 200, scrollable: _deckList);
    await settle(tester);
    expect(find.text('Zvládnuto'), findsOneWidget);
    expect(find.text('Učím se'), findsOneWidget);
    expect(find.text('Nová'), findsOneWidget);
    expect(find.text('Hodnotový typ.'), findsNothing);
    await tester.tap(find.text('Co je struct?'));
    await settle(tester);
    expect(find.text('Hodnotový typ.'), findsOneWidget);

    await tester.scrollUntilVisible(find.byTooltip('Zpět'), -200, scrollable: _deckList);
    await tester.tap(find.byTooltip('Zpět'));
    await settle(tester);
    await _scrollTo(tester, find.text('Ahoj, Kuba!'), up: true);
    expect(find.text('Ahoj, Kuba!'), findsOneWidget);
    expect(api.reviewed, isEmpty);
  });

  testWidgets('change password: local checks, server field error, then success keeps the login', (tester) async {
    final (api, store) = await _signedIn(tester);

    await tester.tap(find.text('Nastavení'));
    await settle(tester);
    await tester.tap(find.text('Změnit heslo'));
    await settle(tester);

    final fields = find.byType(TextField);
    // The keyboard's "Next" moves to the next field, not to the show-password button.
    await tester.showKeyboard(fields.at(0));
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    final second = tester.widget<EditableText>(find.descendant(of: fields.at(1), matching: find.byType(EditableText)));
    expect(second.focusNode.hasFocus, isTrue);
    await tester.enterText(fields.at(0), 'spatne-heslo');
    await tester.enterText(fields.at(1), 'nove-heslo-1');
    await tester.enterText(fields.at(2), 'nove-heslo-2');
    await tester.tap(find.widgetWithText(FilledButton, 'Změnit heslo'));
    await settle(tester);
    expect(find.text('Hesla se neshodují.'), findsOneWidget);
    expect(api.passwordChanges, 0);

    await tester.enterText(fields.at(2), 'nove-heslo-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Změnit heslo'));
    await settle(tester);
    expect(find.text('Současné heslo nesedí.'), findsOneWidget);

    await tester.enterText(fields.at(0), 'tajneheslo');
    await tester.tap(find.widgetWithText(FilledButton, 'Změnit heslo'));
    await settle(tester);
    expect(api.passwordChanges, 1);
    expect(api.password, 'nove-heslo-1');
    expect(store.tokens!.refreshToken, 'R2');
    expect(find.text('Heslo je změněné.'), findsOneWidget);
    expect(find.text('Tvůj účet'), findsOneWidget);
  });
  testWidgets('a server without the card list still lets the deck be studied', (tester) async {
    final (api, _) = await _signedIn(tester, configure: (api) => api.hasDeckCards = false);

    await _scrollTo(tester, find.text('C# základy'));
    await tester.tap(find.text('C# základy'));
    await settle(tester);

    expect(find.text('Tohle jsme nenašli.'), findsOneWidget);
    expect(find.text('Zkusit znovu'), findsOneWidget);
    await tester.tap(find.text('Učit se · 2 karty'));
    await settle(tester);
    expect(find.text('Karta 1 z 2'), findsOneWidget);
    expect(api.reviewed, isEmpty);
  });

  testWidgets('Domů shows this week: met days ticked, today still open', (tester) async {
    await _signedIn(tester);

    expect(find.bySemanticsLabel('pondělí: splněno'), findsOneWidget);
    expect(find.bySemanticsLabel('úterý: nesplněno'), findsOneWidget);
    expect(find.bySemanticsLabel('středa: dnes'), findsOneWidget);
    expect(find.bySemanticsLabel('neděle: ještě nebylo'), findsOneWidget);
  });

  testWidgets('Obchod: heart a reward, buy one, see it waiting in Moje nákupy', (tester) async {
    final (api, _) = await _signedIn(tester);
    await tester.tap(find.text('Obchod'));
    await settle(tester);

    // Šetříš na: the hearted Večer v kině; 1 500 − 1 240 = 260 missing.
    expect(find.text('Šetříš na'), findsOneWidget);
    expect(find.text(S.savingMissing(260)), findsOneWidget);
    expect(find.text('Poslední kus'), findsOneWidget);
    expect(find.text(S.missingShort(260)), findsOneWidget);
    expect(find.text('Vyprodáno'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Přidat na seznam přání').first);
    await settle(tester);
    expect(api.wishlistCalls, ['PUT /api/wishlist/1']);
    expect(find.byTooltip('Odebrat ze seznamu přání'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilledButton, 'Koupit'));
    await settle(tester);
    expect(find.text('Koupit „Jít na pizzu“?'), findsOneWidget);
    expect(find.text('Večeře podle tvého výběru.'), findsOneWidget);
    expect(find.text(points(740)), findsOneWidget);
    await tester.tap(find.text('Koupit za 500'));
    await settle(tester);

    expect(api.claimRequests, hasLength(1));
    expect(api.balance, 740);
    expect(find.text(S.bought('Jít na pizzu')), findsOneWidget);
    expect(find.text('Moje nákupy · 2'), findsOneWidget);
    expect(find.text('Čeká na schválení'), findsOneWidget);
    expect(find.text('Schváleno'), findsOneWidget);
    expect(find.text('740'), findsOneWidget);
  });

  testWidgets('Statistiky: tiles, activity, best time, deck progress and the deck filter', (tester) async {
    final (api, _) = await _signedIn(tester);
    await tester.tap(find.text('Statistiky'));
    await settle(tester);

    expect(find.text(days(12)), findsOneWidget);
    expect(find.text(S.record(21)), findsOneWidget);
    expect(find.text(formatPercent(81)), findsOneWidget);
    expect(find.text(formatInt(1284)), findsOneWidget);
    expect(find.text(formatInt(14920)), findsOneWidget);
    // 16 weeks with 5 met days each, plus this Monday.
    expect(find.bySemanticsLabel(S.activityLabel(16 * 5 + 1)), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Postup v balíčcích'), 300, scrollable: find.byType(Scrollable).last);
    await settle(tester);
    expect(find.text('${S.bestDay(4)} ${S.bestTime(19, 21, 91)}'), findsOneWidget);
    expect(find.text(S.deckMeta(84, 62)), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Všechny balíčky'), -300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Všechny balíčky'));
    await settle(tester);
    await tester.tap(find.text('C# základy').last);
    await settle(tester);
    expect(api.statsQueries.last, '1');
    expect(find.text('C# základy'), findsWidgets);
  });

  testWidgets('a session that meets the goal celebrates and shows the reward it made affordable', (tester) async {
    await _signedIn(tester, configure: (api) => api.reviewEvents = [
          {'type': 'goalMet'},
          {'type': 'wishlistReached', 'itemId': 2, 'name': 'Večer v kině', 'price': 1500},
        ]);
    await tester.tap(find.text(S.studyAll(2)));
    await settle(tester);
    await _answer(tester, 'Vím');
    await _answer(tester, 'Vím');

    expect(find.text('Denní cíl splněn!'), findsOneWidget);
    expect(find.text('${S.streakGrows(12)} ${S.multiplierIn(2, 1.2)}'), findsOneWidget);
    expect(find.text(S.wishlistReady), findsOneWidget);
    expect(find.text(S.wishlistReadyText('Večer v kině')), findsOneWidget);
  });

  testWidgets('reduce motion: the points show at once and nothing floats', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _signedIn(tester);
    await tester.tap(find.text(S.studyAll(2)));
    await settle(tester);

    await tester.tap(find.byType(SwipeCard));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Vím').first);
    await tester.pump();
    await tester.pump();
    expect(find.text('+11'), findsOneWidget);
    expect(find.text('Karta 2 z 2'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('signed in: tomorrow\'s reminders are planned with the server texts', (tester) async {
    final platform = FakeNotificationPlatform();
    await _signedIn(tester, notifications: platform);

    // 12:00, goal open, streak 12: evening and last call today, comeback (no goal yet) tomorrow.
    expect(platform.background, isTrue);
    expect(
      platform.scheduled.map((n) => '${n.at.day}. ${n.category.id} ${n.at.hour}:${n.at.minute}'),
      ['2. evening 18:30', '2. last_call 21:0', '3. comeback 8:0', '3. evening 18:30'],
    );
    expect(platform.scheduled.first.body, 'Už máš 0 z 20. Dáme ještě kousek?');
    expect(platform.scheduled[1].body, 'Série: 12. Pár karet a jede dál 🔥');
  });

  testWidgets('Domů asks once about reminders; Povolit opens the system dialog', (tester) async {
    final platform = FakeNotificationPlatform()
      ..allowed = false
      ..grantOnRequest = true;
    await _signedIn(tester, notifications: platform);
    expect(platform.scheduled, isEmpty);
    expect(find.text(S.askTitle), findsOneWidget);

    await tester.tap(find.text(S.allow));
    await settle(tester);
    expect(platform.requests, 1);
    expect(find.text(S.askTitle), findsNothing);
    expect(platform.scheduled, isNotEmpty);
  });

  testWidgets('Teď ne hides the question for good', (tester) async {
    final platform = FakeNotificationPlatform()..allowed = false;
    await _signedIn(tester, notifications: platform);
    await tester.tap(find.text(S.notNow));
    await settle(tester);
    expect(platform.requests, 0);
    expect(find.text(S.askTitle), findsNothing);

    // Nastavení still offers to switch them on.
    await tester.tap(find.text('Nastavení'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text(S.allowNotifications), 200, scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(find.text(S.allowNotifications));
    await settle(tester);
    await tester.tap(find.text(S.allowNotifications));
    await settle(tester);
    // The system dialog first; Android refused, so its settings open.
    expect(platform.requests, 1);
    expect(platform.settingsOpened, 1);
  });

  testWidgets('Nastavení: notification options are saved and the plan follows them', (tester) async {
    final platform = FakeNotificationPlatform();
    final (api, _) = await _signedIn(tester, notifications: platform);
    await tester.tap(find.text('Nastavení'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text(S.smartTimes), 200, scrollable: find.byType(Scrollable).last);
    await settle(tester);
    expect(find.bySemanticsLabel(S.timeLabel(S.morningReminder, '08:00')), findsOneWidget);
    expect(find.bySemanticsLabel(S.timeLabel(S.quietHours, '22:00–07:00')), findsOneWidget);

    // A time row opens the 24-hour picker.
    await tester.tap(find.text(S.lastCall));
    await settle(tester);
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text(S.cancel).last);
    await settle(tester);

    await tester.tap(find.text(S.smartTimes));
    await settle(tester);
    expect(api.savedSettings.last['smartTimes'], false);

    await tester.tap(find.text(S.sendNotifications));
    await settle(tester);
    expect(api.savedSettings.last['notificationsEnabled'], false);
    expect(platform.scheduled, isEmpty);
  });

  testWidgets('#34: Zobrazit mě v žebříčku is saved with the settings', (tester) async {
    final (api, _) = await _signedIn(tester);
    await tester.tap(find.text('Nastavení'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text(S.showInLeaderboard), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(S.showInLeaderboard));
    await settle(tester);
    expect(api.savedSettings.last['showInLeaderboard'], false);
  });

  testWidgets('#19: with Těžké a Snadné on, the session offers four answers', (tester) async {
    final semantics = tester.ensureSemantics();
    final (api, _) = await _signedIn(tester);
    await tester.tap(find.text('Nastavení'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text(S.fourRatings), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(S.fourRatings));
    await settle(tester);
    expect(api.savedSettings.last['fourRatings'], true);

    await tester.tap(find.text('Domů'));
    await settle(tester);
    await _scrollTo(tester, find.text(S.studyAll(2)), up: true);
    await tester.tap(find.text(S.studyAll(2)));
    await settle(tester);
    await tester.tap(find.byType(SwipeCard));
    await settle(tester);
    for (final label in [S.dontKnow, S.hard, S.know, S.easy]) {
      expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
    }
    // #31: the time to the next review is under each answer
    expect(find.text('10\u00A0min'), findsOneWidget);
    expect(find.text('2\u00A0d'), findsOneWidget);
    expect(find.text('4\u00A0d'), findsOneWidget);
    expect(find.text('8\u00A0d'), findsOneWidget);
    // No Přeskočit button: a swipe up skips, and nothing on screen says so.
    expect(find.bySemanticsLabel(S.skip), findsNothing);
    expect(find.textContaining('nahoru'), findsNothing);
    await tester.drag(find.byType(SwipeCard), const Offset(0, -400));
    await settle(tester);
    expect(find.text('Co je class?'), findsOneWidget);
    expect(api.reviewed, isEmpty);
    // Back to the first card, turned over for the buttons.
    await tester.drag(find.byType(SwipeCard), const Offset(0, -400));
    await settle(tester);
    expect(find.text('Co je struct?'), findsOneWidget);
    await tester.tap(find.byType(SwipeCard));
    await settle(tester);
    // The buttons still fit a phone with 44 px targets and readable labels (CLAUDE.md §9.3).
    await expectLater(tester, meetsGuideline(const MinimumTapTargetGuideline(size: Size(44, 44), link: 'CLAUDE.md §9.3')));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    await _answer(tester, S.hard);
    await _answer(tester, S.easy);
    expect(api.reviewed.map((r) => r['rating']), ['hard', 'easy']);
    // Hotovo: both remembered, a row for each.
    expect(find.text(formatPercent(100)), findsOneWidget);
    expect(find.text(S.hardRow(1)), findsOneWidget);
    expect(find.text(S.easyRow(1)), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a user the admin keeps out of the shop sees no Obchod anywhere', (tester) async {
    await _signedIn(tester, configure: (api) => api.shopEnabled = false);

    expect(find.bySemanticsLabel(S.navShop), findsNothing);
    expect(find.bySemanticsLabel(S.navStats), findsOneWidget);
    // The points stay, but they don't lead to a shop.
    final pill = tester.widget<PointsPill>(find.byType(PointsPill));
    expect(pill.semanticsLabel, S.pointsBalance(1240));
    expect(pill.onTap, isNull);

    // A stray link (e.g. an old wishlist notification) lands on Domů.
    final container = ProviderScope.containerOf(tester.element(find.byType(QuizlyApp)));
    container.read(routerProvider).go('/shop');
    await settle(tester);
    expect(find.text('Ahoj, Kuba!'), findsOneWidget);
  });

  testWidgets('a milestone in a review response shows a notification right away', (tester) async {
    final platform = FakeNotificationPlatform();
    await _signedIn(
      tester,
      notifications: platform,
      configure: (api) => api.reviewEvents = [
        {'type': 'milestone', 'days': 7, 'bonus': 50},
      ],
    );
    await tester.tap(find.text(S.studyAll(2)));
    await settle(tester);
    await _answer(tester, 'Vím');

    expect(platform.shown.map((n) => n.body), contains('7 dní v řadě! 🎉'));
  });

  testWidgets('#11: Vím / Nevím show after the card is turned; a swipe works before that', (tester) async {
    final (api, _) = await _signedIn(tester);
    await tester.tap(find.text(S.studyAll(2)));
    await settle(tester);

    // No buttons before the card is turned.
    expect(find.bySemanticsLabel('Vím'), findsNothing);
    expect(find.bySemanticsLabel('Přeskočit'), findsNothing);
    await tester.drag(find.text('Co je struct?'), const Offset(500, 0));
    await settle(tester);
    expect(api.reviewed.single['rating'], 'know');

    expect(find.text('Karta 2 z 2'), findsOneWidget);
    final hintBefore = tester.getTopLeft(find.text(S.hintDrag)).dy;
    await tester.tap(find.byType(SwipeCard));
    await settle(tester);
    expect(find.text('Referenční typ.'), findsOneWidget);
    // The hint row slid up from the bottom to make room for the buttons.
    expect(tester.getTopLeft(find.text(S.hintDrag)).dy, lessThan(hintBefore - 80));
    expect(find.bySemanticsLabel('Vím'), findsWidgets);
    expect(find.bySemanticsLabel('Nevím'), findsWidgets);
    // #31: the time to the next review is under each answer
    expect(find.text('1\u00A0min'), findsOneWidget);
    expect(find.text('10\u00A0min'), findsOneWidget);
  });

  testWidgets('#31: re-queued card switches review button intervals to relearnIntervals', (tester) async {
    await _signedIn(tester);
    await tester.tap(find.text(S.studyAll(2)));
    await settle(tester);

    // Turn the first card ('Co je struct?', a review card).
    await tester.tap(find.byType(SwipeCard));
    await settle(tester);

    // Its first showing: Nevím 10 min, Vím 4 d.
    expect(find.text('10\u00A0min'), findsOneWidget);
    expect(find.text('4\u00A0d'), findsOneWidget);

    // Nevím puts it once more at the end of the session.
    await _answer(tester, 'Nevím');
    expect(find.text('Karta 2 z 3'), findsOneWidget);

    // The second card ('Co je class?', a new one).
    await tester.tap(find.byType(SwipeCard));
    await settle(tester);
    expect(find.text('1\u00A0min'), findsOneWidget);
    expect(find.text('10\u00A0min'), findsOneWidget);
    await _answer(tester, 'Vím');

    // The first card is back.
    expect(find.text('Karta 3 z 3'), findsOneWidget);
    await tester.tap(find.byType(SwipeCard));
    await settle(tester);

    // Now the times after a Nevím: Vím 1 d, not the 4 d of its first showing.
    expect(find.text('10\u00A0min'), findsOneWidget);
    expect(find.text('1\u00A0d'), findsOneWidget);
    expect(find.text('4\u00A0d'), findsNothing);

    await _answer(tester, 'Vím');
    expect(find.text('Hotovo!'), findsOneWidget);
  });

  testWidgets('#12–#15: deck filter, search, progress per card, no hint on every card', (tester) async {
    await _signedIn(tester);
    await _scrollTo(tester, find.text('C# základy'));
    await tester.tap(find.text('C# základy'));
    await settle(tester);

    expect(find.text(S.deckMetaLearning(3, 33, 33)), findsOneWidget);
    expect(find.bySemanticsLabel(S.deckProgressLabel(33, 33)), findsOneWidget);
    expect(find.textContaining('Klepni'), findsNothing);

    await tester.scrollUntilVisible(find.text('${S.statusLearning} · 1'), 200, scrollable: _deckList);
    await tester.tap(find.text('${S.statusLearning} · 1'));
    await settle(tester);
    expect(find.text('Co je class?'), findsOneWidget);
    expect(find.text('Co je struct?'), findsNothing);
    expect(find.text(S.cardsShown(1, 3)), findsOneWidget);

    // Progress of the card: way to Zvládnuto, answers, next review (already due); the answer is formatted.
    await tester.tap(find.text('Co je class?'));
    await settle(tester);
    expect(find.text(S.cardProgress), findsOneWidget);
    expect(find.text(formatPercent(45)), findsOneWidget);
    expect(find.text(S.cardAnswers(3, 1)), findsOneWidget);
    expect(find.text(S.nextReviewNow), findsOneWidget);
    expect(find.text('Referenční typ.', findRichText: true), findsOneWidget);
    expect(find.text('**Referenční** typ.', findRichText: true), findsNothing);

    // Search without diacritics, across questions and answers.
    await tester.tap(find.text('${S.filterAll} · 3'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'rovnosti');
    await settle(tester);
    expect(find.text('Co je record?'), findsOneWidget);
    expect(find.text('Co je class?'), findsNothing);
    await tester.tap(find.text('Co je record?'));
    await settle(tester);
    expect(find.text(S.notStudiedYet), findsOneWidget);

    // #29: tags show under the question, and the search finds them.
    await tester.enterText(find.byType(TextField), 'prednaska_01');
    await settle(tester);
    expect(find.text('Co je struct?'), findsOneWidget);
    expect(find.text('Co je record?'), findsNothing);
    expect(find.text('ai_gen · prednaska_01'), findsOneWidget);
  });

  testWidgets('#9: with nothing left for today, Domů offers 5 more new cards', (tester) async {
    final (api, _) = await _signedIn(tester, configure: (api) => api.dueNow = 0);
    expect(find.text(S.moreNewCards(5)), findsOneWidget);
    await tester.tap(find.text(S.moreNewCards(5)));
    await settle(tester);
    expect(api.sessionQueries.last, {'extraNew': '5'});
  });

  testWidgets('#16: "Jak Quizly dávkuje karty" from the deck and from Nastavení', (tester) async {
    await _signedIn(tester);
    await _scrollTo(tester, find.text('C# základy'));
    await tester.tap(find.text('C# základy'));
    await settle(tester);
    await tester.tap(find.byTooltip(S.howItWorks));
    await settle(tester);
    expect(find.text(S.howItWorks), findsOneWidget);
    expect(find.textContaining('FSRS', findRichText: true), findsOneWidget);
  });

  testWidgets('#23: edit a card from the deck, add one with +', (tester) async {
    final (api, _) = await _signedIn(tester);
    await _scrollTo(tester, find.text('C# základy'));
    await tester.tap(find.text('C# základy'));
    await settle(tester);

    await tester.scrollUntilVisible(find.text('Co je class?'), 200, scrollable: _deckList);
    await tester.tap(find.text('Co je class?'));
    await settle(tester);
    await tester.scrollUntilVisible(find.byTooltip(S.editCardTitle), 200, scrollable: _deckList);
    // Clear of the bottom navigation bar.
    await tester.drag(_deckList, const Offset(0, -200));
    await settle(tester);
    await tester.tap(find.byTooltip(S.editCardTitle));
    await settle(tester);

    expect(find.text(S.editCardTitle), findsOneWidget);
    // The fields hold the text as typed; the preview shows it formatted.
    expect(find.widgetWithText(TextField, '**Referenční** typ.'), findsOneWidget);
    expect(find.text('Referenční typ.', findRichText: true), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Co je class?'), 'Co je class v C#?');
    // #29: tags typed as one text; the server's error shows under the field.
    expect(find.text(S.tagsLabel), findsOneWidget);
    expect(find.text(S.tagsHint), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(2), 'AI_gen ; spatny!');
    await tester.scrollUntilVisible(find.text(S.saveCard), 200, scrollable: _editorList);
    await tester.tap(find.text(S.saveCard));
    await settle(tester);
    expect(api.cardRequests.single.$2, {
      'question': 'Co je class v C#?',
      'answer': '**Referenční** typ.',
      'tags': ['ai_gen', 'spatny!'],
    });
    expect(find.text('Tag smí mít jen malá písmena, číslice, _ a -.'), findsOneWidget);
    expect(find.byType(CardEditorScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(2), 'AI_gen ; prednaska_02, ai_gen');
    await tester.ensureVisible(find.text(S.saveCard));
    await tester.pump();
    await tester.tap(find.text(S.saveCard));
    await settle(tester);

    expect(api.cardRequests.last.$1, 'PUT /api/decks/1/cards/102');
    expect(api.cardRequests.last.$2, {
      'question': 'Co je class v C#?',
      'answer': '**Referenční** typ.',
      'tags': ['ai_gen', 'prednaska_02'],
    });
    expect(find.text('Co je class v C#?'), findsOneWidget);
    expect(find.text('ai_gen · prednaska_02'), findsOneWidget);
    api.cardRequests.clear();

    // "+ Přidat kartu" is the first tile; it hides while searching.
    await tester.enterText(find.byType(TextField), 'class');
    await settle(tester);
    expect(find.bySemanticsLabel(S.addCard), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await settle(tester);
    await tester.scrollUntilVisible(find.bySemanticsLabel(S.addCard), -200, scrollable: _deckList);
    // Empty fields are caught before anything is sent.
    await tester.tap(find.bySemanticsLabel(S.addCard));
    await settle(tester);
    expect(find.text(S.newCard), findsOneWidget);
    await tester.scrollUntilVisible(find.text(S.addCard), 200, scrollable: _editorList);
    await tester.tap(find.text(S.addCard));
    await settle(tester);
    expect(find.text(S.fillQuestion), findsOneWidget);
    expect(api.cardRequests, isEmpty);
    await tester.enterText(find.byType(TextField).at(0), 'Co je interface?');
    await tester.enterText(find.byType(TextField).at(1), 'Smlouva, kterou třída splní.');
    await tester.tap(find.text(S.addCard));
    await settle(tester);
    expect(api.cardRequests.last.$1, 'POST');
    expect(api.cardRequests.last.$2, {'question': 'Co je interface?', 'answer': 'Smlouva, kterou třída splní.', 'tags': []});
    await tester.scrollUntilVisible(find.text('Co je interface?'), 200, scrollable: _deckList);
    expect(find.text('Co je interface?'), findsOneWidget);
  });

  testWidgets('#23: "Upravit" in a session fixes the card; deleting it moves on', (tester) async {
    final (api, _) = await _signedIn(tester);
    await tester.tap(find.text(S.studyAll(2)));
    await settle(tester);
    expect(find.text(S.multiplierChip(1.1)), findsNothing);

    // #29: where the card belongs: the deck name in the deck's color (no chip), its tags below in smaller grey text.
    expect(find.widgetWithText(Tag, 'C# základy'), findsNothing);
    final deckName = tester.widget<Text>(find.text('C# základy'));
    expect(deckName.style?.color, parseHex('#BAD69B'));
    final tagLine = tester.widget<Text>(find.text('ai_gen · prednaska_01'));
    expect(tagLine.style?.color, Q.textMuted);
    expect(tagLine.style!.fontSize!, lessThan(deckName.style!.fontSize!));

    await tester.tap(find.bySemanticsLabel(S.editCardTitle));
    await settle(tester);
    expect(find.widgetWithText(TextField, 'ai_gen ; prednaska_01'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Hodnotový typ.'), 'Hodnotový typ na zásobníku.');
    await tester.enterText(find.widgetWithText(TextField, 'ai_gen ; prednaska_01'), 'prednaska_03');
    await tester.scrollUntilVisible(find.text(S.saveCard), 200, scrollable: _editorList);
    await tester.tap(find.text(S.saveCard));
    await settle(tester);
    expect(api.cardRequests.single.$1, 'PUT /api/decks/1/cards/101');
    expect((api.cardRequests.single.$2! as Map)['tags'], ['prednaska_03']);
    expect(find.text('prednaska_03'), findsOneWidget);
    expect(find.text('ai_gen · prednaska_01'), findsNothing);
    await tester.tap(find.byType(SwipeCard));
    await settle(tester);
    expect(find.text('Hodnotový typ na zásobníku.', findRichText: true), findsOneWidget);
    expect(api.reviewed, isEmpty);

    await tester.tap(find.bySemanticsLabel(S.editCardTitle));
    await settle(tester);
    await tester.tap(find.byTooltip(S.deleteCard));
    await settle(tester);
    expect(find.text(S.deleteCardText), findsOneWidget);
    await tester.tap(find.text(S.delete));
    await settle(tester);
    expect(api.cardRequests.last, ('DELETE /api/decks/1/cards/101', null));
    // The next card, and the deleted one no longer counts.
    expect(find.text('Co je class?'), findsOneWidget);
    expect(find.text(S.cardOf(1, 1)), findsOneWidget);
    expect(find.text('prednaska_03'), findsNothing);
    expect(api.reviewed, isEmpty);
  });

  group('app updates (docs/app-updates.md)', () {
    const latest = {'versionName': '1.0.1', 'versionCode': 58, 'size': 1234};

    testWidgets('Domů offers a newer version; Aktualizovat downloads it and opens the installer', (tester) async {
      final installer = FakeAppInstaller(installed: 41);
      final (api, _) = await _signedIn(tester, configure: (api) => api.appLatest = latest, installer: installer);

      expect(find.text(S.updateTitle), findsOneWidget);
      expect(find.text(S.updateText('1.0.1', formatMegabytes(1234))), findsOneWidget);
      await tester.tap(find.text(S.updateNow));
      await _untilReal(tester, () => installer.installs.isNotEmpty);

      expect(api.apkDownloads, 1);
      expect(installer.installs, [installer.path]);
      expect(await tester.runAsync(() => File(installer.path).length()), 1234);
      expect(find.text(S.updateFailed), findsNothing);
    });

    testWidgets('the same or an older version shows nothing', (tester) async {
      await _signedIn(tester, configure: (api) => api.appLatest = latest, installer: FakeAppInstaller(installed: 58));
      expect(find.text(S.updateTitle), findsNothing);
    });

    testWidgets('Později hides the card until the app starts again', (tester) async {
      final (api, _) = await _signedIn(tester, configure: (api) => api.appLatest = latest, installer: FakeAppInstaller(installed: 41));
      await tester.tap(find.text(S.updateLater));
      await settle(tester);
      expect(find.text(S.updateTitle), findsNothing);

      // A newer one than the hidden version shows again.
      api.appLatest = {...latest, 'versionName': '1.0.2', 'versionCode': 60};
      await tester.fling(find.byType(Scrollable).first, const Offset(0, 400), 1000);
      await settle(tester);
      expect(find.text(S.updateText('1.0.2', formatMegabytes(1234))), findsOneWidget);
    });

    testWidgets('a failed download says so and nothing is installed', (tester) async {
      final installer = FakeAppInstaller(installed: 41);
      await _signedIn(tester, configure: (api) => api
        ..appLatest = latest
        ..apkFails = true, installer: installer);
      await tester.tap(find.text(S.updateNow));
      await _untilReal(tester, () => find.text(S.updateFailed).evaluate().isNotEmpty);
      expect(find.text(S.updateFailed), findsOneWidget);
      expect(installer.installs, isEmpty);
    });
  });

  group('onboarding (#41)', () {
    testWidgets('runs once after login, saves ratings, daily goal and new cards, and never repeats on re-login or update', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      final api = FakeApi();
      final kv = MemoryKeyValueStore();
      final onboarding = OnboardingStore(kv);
      final tokenStore = MemoryTokenStore();
      final client = ApiClient(baseUrl: 'https://quizly.test', store: tokenStore, dio: Dio()..httpClientAdapter = api);
      await onboarding.init(alreadySignedIn: false);

      await tester.pumpWidget(ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          apiClientProvider.overrideWithValue(client),
          onboardingStoreProvider.overrideWithValue(onboarding),
          outboxStoreProvider.overrideWithValue(MemoryOutboxStore()),
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
          notificationsProvider.overrideWithValue(_notifications(FakeNotificationPlatform())),
        ],
        child: const QuizlyApp(),
      ));
      await settle(tester);

      // Login
      await tester.enterText(find.byType(TextField).at(0), 'kuba');
      await tester.enterText(find.byType(TextField).at(1), 'tajneheslo');
      await tester.tap(find.text(S.signIn));
      await settle(tester);

      // 1) About Quizly
      expect(find.text(S.onboardingAboutTitle), findsOneWidget);
      expect(find.text(S.onboardingAboutCardsTitle), findsOneWidget);
      expect(find.text(S.onboardingAboutStreakTitle), findsOneWidget);
      expect(find.text(S.onboardingAboutPointsTitle), findsOneWidget);
      await tester.tap(find.text(S.next));
      await settle(tester);

      // 2) FSRS algorithm
      expect(find.text(S.onboardingFsrsTitle), findsOneWidget);
      expect(find.text(S.onboardingFsrsTimingTitle), findsOneWidget);
      expect(find.text(S.onboardingFsrsKnowTitle), findsOneWidget);
      expect(find.text(S.onboardingFsrsDontKnowTitle), findsOneWidget);
      await tester.tap(find.text(S.next));
      await settle(tester);

      // 3) Vím / Nevím vs Nevím, Těžké, Vím, Snadné
      expect(find.text(S.onboardingRatingsTitle), findsOneWidget);
      await tester.tap(find.text(S.onboardingFourRatingsTitle));
      await settle(tester);
      await tester.tap(find.text(S.next));
      await settle(tester);

      // 4) Daily goal: 3 presets (Snadné, Střední, Těžké) + adjust at the bottom
      expect(find.text(S.onboardingGoalTitle), findsOneWidget);
      expect(find.text(S.presetEasy), findsOneWidget);
      expect(find.text(S.presetMedium), findsOneWidget);
      expect(find.text(S.presetHard), findsOneWidget);
      await tester.tap(find.text(S.presetHard));
      await settle(tester);
      expect(find.text('40'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(S.increaseGoal));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(S.increaseGoal));
      await settle(tester);
      expect(find.text('42'), findsOneWidget);
      await tester.tap(find.text(S.next));
      await settle(tester);

      // 5) New cards per day: 3 presets (Snadné, Střední, Těžké) + adjust at the bottom
      expect(find.text(S.onboardingNewTitle), findsOneWidget);
      await tester.tap(find.text(S.presetHard));
      await settle(tester);
      expect(find.text('10'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(S.fewerNew));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(S.fewerNew));
      await settle(tester);
      expect(find.text('8'), findsOneWidget);
      await tester.tap(find.text(S.next));
      await settle(tester);

      // 6) Welcome screen with "Přeji hezkou zábavu!"
      expect(find.text(S.onboardingWelcomeTitle), findsOneWidget);
      expect(find.text(S.onboardingFourRatingsTitle), findsOneWidget);
      expect(find.text(cards(42)), findsOneWidget);
      expect(find.text(cards(8)), findsOneWidget);
      await tester.tap(find.text(S.onboardingStart));
      await settle(tester);

      expect(find.text('Ahoj, Kuba!'), findsOneWidget);
      expect(api.savedSettings.last['fourRatings'], true);
      expect(api.savedSettings.last['dailyGoal'], 42);
      expect(api.savedSettings.last['newCardsPerDay'], 8);
      expect(onboarding.isDone, isTrue);

      // Sign out and sign back in: the intro must not run a second time.
      await tester.tap(find.text(S.navSettings).last);
      await settle(tester);
      await tester.scrollUntilVisible(find.text(S.signOut), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text(S.signOut));
      await settle(tester);
      await tester.tap(find.text(S.signOut).last);
      await settle(tester);
      expect(find.text(S.signIn), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'kuba');
      await tester.enterText(find.byType(TextField).at(1), 'tajneheslo');
      await tester.tap(find.text(S.signIn));
      await settle(tester);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.text('Ahoj, Kuba!'), findsOneWidget);
    });

    testWidgets('the update that brings the intro shows it once to a signed-in user, the next start does not', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final kv = MemoryKeyValueStore();

      Future<void> startSignedIn() async {
        final tokens = MemoryTokenStore(AuthTokens(
          accessToken: 'A',
          accessTokenExpiresAt: DateTime.utc(2099),
          refreshToken: 'R',
          refreshTokenExpiresAt: DateTime.utc(2099),
          user: const AppUser(id: 2, username: 'kuba', displayName: 'Kuba'),
        ));
        final client = ApiClient(baseUrl: 'https://quizly.test', store: tokens, dio: Dio()..httpClientAdapter = FakeApi());
        await client.restore();
        final onboarding = OnboardingStore(kv);
        await onboarding.init(alreadySignedIn: true);
        await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          retry: (retryCount, error) => null,
          overrides: [
            apiClientProvider.overrideWithValue(client),
            onboardingStoreProvider.overrideWithValue(onboarding),
            outboxStoreProvider.overrideWithValue(MemoryOutboxStore()),
            connectivityProvider.overrideWith((ref) => Stream.value(true)),
            notificationsProvider.overrideWithValue(_notifications(FakeNotificationPlatform())),
          ],
          child: const QuizlyApp(),
        ));
        await settle(tester);
      }

      // The updated app starts signed in, with nothing saved about the intro yet.
      await startSignedIn();
      expect(find.byType(OnboardingScreen), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text(S.next));
        await settle(tester);
      }
      await tester.tap(find.text(S.onboardingStart));
      await settle(tester);
      expect(find.text('Ahoj, Kuba!'), findsOneWidget);
      expect(kv.data['quizly.onboarding'], 'done');

      // A later update (or any restart): straight to Domů.
      await startSignedIn();
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.text('Ahoj, Kuba!'), findsOneWidget);
    });

    /// Logs in on a fresh install and taps through to "Přeji hezkou zábavu!".
    Future<OnboardingStore> throughOnboarding(WidgetTester tester, FakeApi api) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final onboarding = await _onboarding();
      final client = ApiClient(baseUrl: 'https://quizly.test', store: MemoryTokenStore(), dio: Dio()..httpClientAdapter = api);
      await tester.pumpWidget(ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          apiClientProvider.overrideWithValue(client),
          onboardingStoreProvider.overrideWithValue(onboarding),
          outboxStoreProvider.overrideWithValue(MemoryOutboxStore()),
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
          notificationsProvider.overrideWithValue(_notifications(FakeNotificationPlatform())),
        ],
        child: const QuizlyApp(),
      ));
      await settle(tester);
      await tester.enterText(find.byType(TextField).at(0), 'kuba');
      await tester.enterText(find.byType(TextField).at(1), 'tajneheslo');
      await tester.tap(find.text(S.signIn));
      await settle(tester);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text(S.next));
        await settle(tester);
      }
      expect(find.text(S.onboardingWelcomeTitle), findsOneWidget);
      return onboarding;
    }

    testWidgets('settings that did not load at the start are loaded before saving, so nothing else is reset', (tester) async {
      // A reinstall: the user hid from Žebříček and moved the evening reminder earlier.
      final api = FakeApi()
        ..settingsLoadFails = true
        ..settings = {
          ...FakeApi().settings,
          'eveningTime': '17:15', 'quietFrom': '21:30', 'showInLeaderboard': false, 'fourRatings': false,
        };
      await throughOnboarding(tester, api);

      // The steps showed the defaults; by the last one the server answers again.
      api.settingsLoadFails = false;
      await tester.tap(find.text(S.onboardingStart));
      await settle(tester);

      expect(find.text('Ahoj, Kuba!'), findsOneWidget);
      final saved = api.savedSettings.single;
      expect(saved['eveningTime'], '17:15');
      expect(saved['quietFrom'], '21:30');
      expect(saved['showInLeaderboard'], false);
      expect(saved['dailyGoal'], 20);
    });

    testWidgets('a failed save keeps the intro open; "Nastavím si to později" finishes without saving', (tester) async {
      final api = FakeApi()..settingsLoadFails = true;
      final onboarding = await throughOnboarding(tester, api);

      // The settings still can't be loaded: nothing is saved with defaults.
      await tester.tap(find.text(S.onboardingStart));
      await settle(tester);
      expect(find.text(S.onboardingWelcomeTitle), findsOneWidget);
      expect(find.text(S.onboardingLater), findsOneWidget);
      expect(api.savedSettings, isEmpty);

      // Now the settings load, but the save itself fails.
      api
        ..settingsLoadFails = false
        ..settingsSaveFails = true;
      await tester.tap(find.text(S.onboardingStart));
      await settle(tester);
      expect(find.text(S.onboardingWelcomeTitle), findsOneWidget);
      expect(api.savedSettings, isEmpty);

      await tester.tap(find.text(S.onboardingLater));
      await settle(tester);
      expect(find.text('Ahoj, Kuba!'), findsOneWidget);
      expect(onboarding.isDone, isTrue);
      expect(api.savedSettings, isEmpty);
    });
  });

  group('accessibility (CLAUDE.md §9.3)', () {
    // Touch targets ≥ 44 px, every tappable thing has a label, text contrast ≥ 4.5:1.
    const tapTargets = MinimumTapTargetGuideline(size: Size(44, 44), link: 'CLAUDE.md §9.3');

    Future<void> meetsAll(WidgetTester tester, String screen) async {
      await expectLater(tester, meetsGuideline(tapTargets), reason: screen);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: screen);
      await expectLater(tester, meetsGuideline(textContrastGuideline), reason: screen);
    }

    testWidgets('login', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final client = ApiClient(baseUrl: 'https://quizly.test', store: MemoryTokenStore(), dio: Dio()..httpClientAdapter = FakeApi());
      await tester.pumpWidget(ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          apiClientProvider.overrideWithValue(client),
          onboardingStoreProvider.overrideWithValue(await _onboarding()),
          outboxStoreProvider.overrideWithValue(MemoryOutboxStore()),
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
          notificationsProvider.overrideWithValue(_notifications(FakeNotificationPlatform())),
        ],
        child: const QuizlyApp(),
      ));
      await settle(tester);
      await meetsAll(tester, 'Přihlášení');

      await tester.enterText(find.byType(TextField).at(0), 'kuba');
      await tester.enterText(find.byType(TextField).at(1), 'tajneheslo');
      await tester.tap(find.text(S.signIn));
      await settle(tester);
      for (var step = 1; step <= 6; step++) {
        await meetsAll(tester, 'Onboarding step $step');
        if (step < 6) {
          await tester.tap(find.text(S.next));
          await settle(tester);
        }
      }
      semantics.dispose();
    });

    testWidgets('the tabs: Domů, Statistiky, Obchod, Nastavení', (tester) async {
      final semantics = tester.ensureSemantics();
      await _signedIn(
        tester,
        notifications: FakeNotificationPlatform()..allowed = false,
        configure: (api) => api.appLatest = {'versionName': '1.0.1', 'versionCode': 58, 'size': 1234},
        installer: FakeAppInstaller(installed: 41),
      );
      expect(find.text(S.updateTitle), findsOneWidget);
      await meetsAll(tester, 'Domů with the update and the reminder question');
      for (final tab in ['Statistiky', 'Obchod', 'Nastavení']) {
        await tester.tap(find.text(tab).last);
        await settle(tester);
        await meetsAll(tester, tab);
        if (tab == 'Statistiky') {
          await tester.tap(find.text(S.leaderboard));
          await settle(tester);
          await meetsAll(tester, S.leaderboard);
        }
      }
      semantics.dispose();
    });

    testWidgets('deck detail, study session and Hotovo', (tester) async {
      final semantics = tester.ensureSemantics();
      await _signedIn(tester);
      await _scrollTo(tester, find.text('C# základy'));
      await tester.tap(find.text('C# základy'));
      await settle(tester);
      await meetsAll(tester, 'Balíček');

      await tester.tap(find.byTooltip(S.back));
      await settle(tester);
      await _scrollTo(tester, find.text(S.studyAll(2)), up: true);
      await tester.tap(find.text(S.studyAll(2)));
      await settle(tester);
      await meetsAll(tester, 'Učení');
      await tester.tap(find.byType(SwipeCard));
      await settle(tester);
      await meetsAll(tester, 'Učení, answer side');

      await tester.tap(find.bySemanticsLabel(S.editCardTitle));
      await settle(tester);
      await meetsAll(tester, 'Upravit kartu');
      await tester.tap(find.byTooltip(S.back));
      await settle(tester);

      await _answer(tester, 'Vím');
      await _answer(tester, 'Vím');
      await meetsAll(tester, 'Hotovo');
      semantics.dispose();
    });
  });
}

/// The app with a stored login, on the home screen.
/// Notifications at a fixed time: Monday 2. 11. 2026, 12:00 in Prague (the fake API's today).
Notifications _notifications(FakeNotificationPlatform platform) => Notifications(
      platform: platform,
      store: MemoryKeyValueStore(),
      now: () => tz.TZDateTime(prague, 2026, 11, 2, 12),
      random: Random(1),
    );

/// Onboarding state as `main` restores it (#41): a fresh install, or one whose intro is [done].
Future<OnboardingStore> _onboarding({bool done = false}) async {
  final kv = MemoryKeyValueStore();
  if (done) kv.data['quizly.onboarding'] = 'done';
  final store = OnboardingStore(kv);
  await store.init(alreadySignedIn: done);
  return store;
}

Future<(FakeApi, MemoryTokenStore)> _signedIn(
  WidgetTester tester, {
  void Function(FakeApi api)? configure,
  FakeNotificationPlatform? notifications,
  FakeAppInstaller? installer,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final api = FakeApi();
  configure?.call(api);
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
      onboardingStoreProvider.overrideWithValue(await _onboarding(done: true)),
      outboxStoreProvider.overrideWithValue(MemoryOutboxStore()),
      connectivityProvider.overrideWith((ref) => Stream.value(true)),
      notificationsProvider.overrideWithValue(_notifications(notifications ?? FakeNotificationPlatform())),
      appInstallerProvider.overrideWithValue(installer ?? FakeAppInstaller()),
    ],
    child: const QuizlyApp(),
  ));
  await settle(tester);
  return (api, store);
}

/// Scrolls the visible list until [finder] is on screen (the deck list sits below the fold).
Future<void> _scrollTo(WidgetTester tester, Finder finder, {bool up = false}) async {
  await tester.scrollUntilVisible(finder, up ? -200 : 200, scrollable: find.byType(Scrollable).first);
  await tester.pump();
}

/// Vím / Nevím: turns the card over first when it isn't yet (the buttons show only then).
Future<void> _answer(WidgetTester tester, String label) async {
  if (find.bySemanticsLabel(label).evaluate().isEmpty) {
    await tester.tap(find.byType(SwipeCard));
    await settle(tester);
  }
  await tester.tap(find.bySemanticsLabel(label).first);
  await settle(tester);
}

/// The deck detail's list (not the search field's own scrollable).
final _deckList = find.descendant(of: find.byType(DeckScreen), matching: find.byType(Scrollable)).first;

/// The card editor's list (not a text field's own scrollable).
final _editorList = find.descendant(of: find.byType(CardEditorScreen), matching: find.byType(Scrollable)).first;

/// Lets real I/O (a file download) and the test's clock take turns until [done], at most ~5 s.
Future<void> _untilReal(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await settle(tester);
}

/// Android's side of an update, without Android: a temporary file and a list of installs.
class FakeAppInstaller implements AppInstaller {
  FakeAppInstaller({this.installed = 1});

  final int installed;
  final installs = <String>[];
  late final String path = '${Directory.systemTemp.createTempSync('quizly-update').path}/quizly-update.apk';

  @override
  Future<int> installedVersionCode() async => installed;

  @override
  Future<String> downloadPath() async => path;

  @override
  Future<void> install(String path) async {
    installs.add(path);
  }
}
