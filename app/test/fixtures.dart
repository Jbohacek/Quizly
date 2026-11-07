import 'package:quizly/core/api/models.dart';

SessionCard card(
  int id, {
  int deckId = 1,
  CardKind kind = CardKind.review,
  CardIntervals? intervals,
  CardIntervals? relearnIntervals,
}) =>
    SessionCard(
      cardId: id,
      deckId: deckId,
      question: 'Otázka $id',
      answer: 'Odpověď $id',
      kind: kind,
      intervals: intervals,
      relearnIntervals: relearnIntervals,
    );

Summary summary({int balance = 100, int streak = 3, int graded = 0, int goal = 20, bool goalMet = false}) => Summary(
      balance: balance,
      streak: streak,
      bestStreak: streak,
      multiplier: 1,
      nextMultiplier: const NextMultiplier(value: 1.1, inDays: 4),
      today: Today(date: DateTime(2026, 11, 2), graded: graded, correct: graded, goal: goal, goalMet: goalMet, points: 0),
    );

ReviewBatchResult batchResult(List<ReviewResult> results, {List<AppEvent> events = const [], Summary? sum}) =>
    ReviewBatchResult(
      results: results,
      summary: sum ?? summary(),
      points: const PointsValue(know: 10, dontKnow: 2),
      events: events,
    );

/// Applied results for every item of [batch].
ReviewBatchResult appliedAll(List<ReviewItem> batch) => batchResult([
      for (final r in batch)
        ReviewResult(id: r.id, status: 'applied', pointsAwarded: r.rating == Rating.know ? 10 : 2, multiplier: 1),
    ]);
