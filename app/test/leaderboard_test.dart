import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/api/api_client.dart';
import 'package:quizly/core/api/models.dart';
import 'package:quizly/core/providers.dart';
import 'package:quizly/core/strings.dart';
import 'package:quizly/features/stats/stats_screen.dart';

class _FakeLeaderboardApiClient extends Fake implements ApiClient {
  _FakeLeaderboardApiClient({required this.user, required this.leaderboardData});

  @override
  final AppUser user;

  Leaderboard leaderboardData;
  LeaderboardQuery? lastQuery;

  @override
  Future<Leaderboard> getLeaderboard({String period = 'week', String metric = 'points'}) async {
    lastQuery = (period: period, metric: metric);
    return leaderboardData;
  }

  @override
  Future<Stats> stats({int? deckId}) async {
    return Stats(
      deckId: null,
      tiles: const StatsTiles(streak: 5, bestStreak: 10, successRate30d: 85, sparkline: [], totalReviews: 100, totalPointsEarned: 1500),
      heatmap: Heatmap(from: DateTime.utc(2026, 7, 13), today: DateTime.utc(2026, 11, 4), weeks: const []),
      goal: 20,
      daily: const [],
      weekdays: const [],
      bestTime: null,
      deckProgress: const [],
    );
  }
}

class _FakeAuthController extends Notifier<AuthState> implements AuthController {
  _FakeAuthController(this._user);

  final AppUser _user;

  @override
  AuthState build() => AuthState(user: _user);

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() async {}
}

void main() {
  group('Leaderboard Models', () {
    test('LeaderboardEntry deserializes and serializes properly', () {
      final json = {
        'rank': 1,
        'userId': 42,
        'displayName': 'Alice',
        'points': 520,
        'currentStreak': 7,
        'cardsStudied': 64,
      };

      final entry = LeaderboardEntry.fromJson(json);
      expect(entry.rank, 1);
      expect(entry.userId, 42);
      expect(entry.displayName, 'Alice');
      expect(entry.points, 520);
      expect(entry.currentStreak, 7);
      expect(entry.cardsStudied, 64);

      final out = entry.toJson();
      expect(out['rank'], 1);
      expect(out['userId'], 42);
      expect(out['displayName'], 'Alice');
      expect(out['points'], 520);
      expect(out['currentStreak'], 7);
      expect(out['cardsStudied'], 64);
    });

    test('Leaderboard deserializes entries and currentUserRank', () {
      final json = {
        'period': 'week',
        'metric': 'points',
        'entries': [
          {
            'rank': 1,
            'userId': 1,
            'displayName': 'První',
            'points': 1000,
            'currentStreak': 14,
            'cardsStudied': 120,
          },
          {
            'rank': 2,
            'userId': 2,
            'displayName': 'Druhý',
            'points': 800,
            'currentStreak': 10,
            'cardsStudied': 90,
          },
        ],
        'currentUserRank': 2,
      };

      final leaderboard = Leaderboard.fromJson(json);
      expect(leaderboard.period, 'week');
      expect(leaderboard.metric, 'points');
      expect(leaderboard.entries, hasLength(2));
      expect(leaderboard.currentUserRank, 2);
      expect(leaderboard.entries[0].displayName, 'První');
      expect(leaderboard.entries[1].displayName, 'Druhý');

      final serialized = leaderboard.toJson();
      expect(serialized['period'], 'week');
      expect(serialized['metric'], 'points');
      expect(serialized['currentUserRank'], 2);
    });
  });

  group('Leaderboard UI Widget Tests', () {
    const testUser = AppUser(id: 2, username: 'kuba', displayName: 'Kuba');

    final testLeaderboard = Leaderboard(
      period: 'week',
      metric: 'points',
      entries: const [
        LeaderboardEntry(rank: 1, userId: 1, displayName: 'Admin', points: 500, currentStreak: 15, cardsStudied: 80),
        LeaderboardEntry(rank: 2, userId: 2, displayName: 'Kuba', points: 350, currentStreak: 12, cardsStudied: 50),
        LeaderboardEntry(rank: 3, userId: 3, displayName: 'Petra', points: 200, currentStreak: 8, cardsStudied: 30),
        LeaderboardEntry(rank: 4, userId: 4, displayName: 'Honza', points: 100, currentStreak: 2, cardsStudied: 10),
      ],
      currentUserRank: 2,
    );

    Widget createTestApp({required _FakeLeaderboardApiClient client}) {
      return ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          authProvider.overrideWith(() => _FakeAuthController(client.user)),
          homeProvider.overrideWith((ref) async => HomeData(
                me: Me(
                  user: testUser,
                  summary: Summary(
                    balance: 100,
                    streak: 12,
                    bestStreak: 20,
                    multiplier: 1.1,
                    nextMultiplier: null,
                    today: Today(
                      date: DateTime.utc(2026, 11, 4),
                      graded: 5,
                      correct: 5,
                      goal: 20,
                      goalMet: false,
                      points: 50,
                    ),
                  ),
                  dueNow: 5,
                ),
                decks: const DeckList(items: [], newAllowanceLeft: 0),
                week: null,
              )),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: StatsScreen(),
          ),
        ),
      );
    }

    testWidgets('Žebříček ranks everyone, highlights me and words the numbers in Czech', (tester) async {
      final client = _FakeLeaderboardApiClient(user: testUser, leaderboardData: testLeaderboard);

      await tester.pumpWidget(createTestApp(client: client));
      await tester.pumpAndSettle();
      expect(find.text(S.myStats), findsOneWidget);

      await tester.tap(find.text(S.leaderboard));
      await tester.pumpAndSettle();

      for (final label in [S.metricPoints, S.metricStreak, S.periodWeek, S.periodAllTime]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text(S.yourRankBadge(2)), findsOneWidget);
      // Ranks are numbers (CLAUDE.md §9.3: no emoji as UI icons).
      for (final rank in [1, 2, 3, 4]) {
        expect(find.text(S.rankPosition(rank)), findsOneWidget);
      }
      for (final name in ['Admin', 'Kuba', 'Petra', 'Honza']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text(S.youBadge), findsOneWidget);
      // Czech plurals and number formatting.
      expect(find.text('500 bodů'), findsOneWidget);
      expect(find.text('Série: 2 dny · 10 karet'), findsOneWidget);

      await tester.tap(find.text(S.periodAllTime));
      await tester.pumpAndSettle();
      expect(client.lastQuery, (period: 'allTime', metric: 'points'));
    });

    testWidgets('Série has no period: a streak is not counted per week', (tester) async {
      final client = _FakeLeaderboardApiClient(
        user: testUser,
        leaderboardData: const Leaderboard(
          period: 'allTime',
          metric: 'streak',
          entries: [
            LeaderboardEntry(rank: 1, userId: 1, displayName: 'Admin', points: 1, currentStreak: 1, cardsStudied: 1),
            LeaderboardEntry(rank: 1, userId: 2, displayName: 'Kuba', points: 1457, currentStreak: 1, cardsStudied: 3),
          ],
          currentUserRank: 1,
        ),
      );

      await tester.pumpWidget(createTestApp(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.leaderboard));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.metricStreak));
      await tester.pumpAndSettle();

      expect(client.lastQuery?.metric, 'streak');
      expect(find.text(S.periodWeek), findsNothing);
      expect(find.text(S.periodAllTime), findsNothing);
      // A tie shares the rank.
      expect(find.text(S.rankPosition(1)), findsNWidgets(2));
      expect(find.text('1 den'), findsNWidgets(2));
      expect(find.text('1 bod · 1 karta'), findsOneWidget);
      expect(find.text('1 457 bodů · 3 karty'), findsOneWidget);
    });

    testWidgets('A hidden user is told how to show up again', (tester) async {
      final client = _FakeLeaderboardApiClient(
        user: testUser,
        leaderboardData: Leaderboard(
          period: 'week',
          metric: 'points',
          entries: [for (final e in testLeaderboard.entries) if (e.userId != testUser.id) e],
          currentUserRank: null,
        ),
      );

      await tester.pumpWidget(createTestApp(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.leaderboard));
      await tester.pumpAndSettle();

      expect(find.text(S.hiddenFromLeaderboard), findsOneWidget);
      expect(find.text(S.youBadge), findsNothing);
    });

    testWidgets('Empty leaderboard shows empty state message', (tester) async {
      const emptyLeaderboard = Leaderboard(
        period: 'week',
        metric: 'points',
        entries: [],
        currentUserRank: null,
      );
      final client = _FakeLeaderboardApiClient(user: testUser, leaderboardData: emptyLeaderboard);

      await tester.pumpWidget(createTestApp(client: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text(S.leaderboard));
      await tester.pumpAndSettle();

      expect(find.text(S.emptyLeaderboard), findsOneWidget);
    });
  });
}
