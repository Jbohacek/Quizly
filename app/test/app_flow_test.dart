import 'dart:convert';
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
import 'package:quizly/features/notifications/notification_store.dart';
import 'package:quizly/features/notifications/notifications.dart';
import 'package:quizly/features/notifications/planner.dart';
import 'package:quizly/features/session/review_sync.dart';
import 'package:quizly/main.dart';
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
  final savedSettings = <Map<String, Object?>>[];
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
      'GET /api/decks/1/cards' when !hasDeckCards => _json({'code': 'notFound', 'title': 'Tohle jsme nenašli.'}, 404),
      'GET /api/decks/1/cards' => _json({
          'deck': {
            'id': 1, 'name': 'C# základy', 'description': 'Základní pojmy jazyka C#', 'color': '#BAD69B',
            'totalCards': 3, 'dueNow': 1, 'newAvailable': 1, 'masteredPercent': 33,
          },
          'cards': [
            {'id': 101, 'question': 'Co je struct?', 'answer': 'Hodnotový typ.', 'status': 'mastered'},
            {'id': 102, 'question': 'Co je class?', 'answer': 'Referenční typ.', 'status': 'learning'},
            {'id': 103, 'question': 'Co je record?', 'answer': 'Typ s hodnotovou rovností.', 'status': 'new'},
          ],
        }),
      'POST /api/me/password' => _changePassword(body as Map<String, Object?>),
      'GET /api/stats' => _json(stats((statsQueries..add(options.uri.queryParameters['deckId'])).last)),
      'GET /api/shop' => _json(shop),
      'GET /api/claims' => _json({'items': claims.reversed.toList()}),
      final r when r.startsWith('PUT /api/wishlist/') || r.startsWith('DELETE /api/wishlist/') => _wishlist(r),
      final r when r.startsWith('POST /api/shop/') => _claim(r, body as Map<String, Object?>),
      'GET /api/me/settings' => _json(settings),
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
      final points = r['rating'] == 'know' ? 11 : 2;
      balance += points;
      graded++;
      results.add({'id': r['id'], 'status': 'applied', 'pointsAwarded': points, 'multiplier': 1.1});
    }
    return _json({'results': results, 'summary': summary, 'points': {'know': 11, 'dontKnow': 2}, 'events': reviewEvents});
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
    expect(find.text('Zvládnuto'), findsOneWidget);
    expect(find.text('Učím se'), findsOneWidget);
    expect(find.text('Nová'), findsOneWidget);
    expect(find.text('Hodnotový typ.'), findsNothing);
    await tester.tap(find.text('Co je struct?'));
    await settle(tester);
    expect(find.text('Hodnotový typ.'), findsOneWidget);

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
    await tester.tap(find.bySemanticsLabel('Vím').first);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Vím').first);
    await settle(tester);

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

    // Nastavení still offers the Android settings.
    await tester.tap(find.text('Nastavení'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text(S.openSystemSettings), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(S.openSystemSettings));
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
    await tester.tap(find.bySemanticsLabel('Vím').first);
    await settle(tester);

    expect(platform.shown.map((n) => n.body), contains('7 dní v řadě! 🎉'));
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

Future<(FakeApi, MemoryTokenStore)> _signedIn(
  WidgetTester tester, {
  void Function(FakeApi api)? configure,
  FakeNotificationPlatform? notifications,
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
      outboxStoreProvider.overrideWithValue(MemoryOutboxStore()),
      connectivityProvider.overrideWith((ref) => Stream.value(true)),
      notificationsProvider.overrideWithValue(_notifications(notifications ?? FakeNotificationPlatform())),
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
