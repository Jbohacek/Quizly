import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/api/models.dart';
import 'package:quizly/features/session/session_queue.dart';

import 'fixtures.dart';

void main() {
  group('SessionQueue', () {
    test('Vím removes the card and moves on', () {
      final q = SessionQueue([card(1), card(2)]);
      expect(q.current!.cardId, 1);
      expect((q.position, q.total), (1, 2));
      q.answer(Rating.know);
      expect(q.current!.cardId, 2);
      expect((q.position, q.total), (2, 2));
      q.answer(Rating.know);
      expect(q.isDone, isTrue);
      expect(q.current, isNull);
    });

    test('Nevím re-queues the card once at the end and raises the total', () {
      final q = SessionQueue([card(1), card(2)]);
      q.answer(Rating.dontKnow);
      expect(q.total, 3);
      expect(q.current!.cardId, 2);
      q.answer(Rating.know);
      expect(q.current!.cardId, 1);
      expect((q.position, q.total), (3, 3));
      // Second Nevím on the same card is a normal review, not re-queued again.
      q.answer(Rating.dontKnow);
      expect(q.isDone, isTrue);
      expect(q.total, 3);
      expect(q.graded, 3);
    });

    test('#23: an edited card shows its new text and tags in every copy', () {
      final q = SessionQueue([card(1), card(2)]);
      q.answer(Rating.dontKnow); // card 1 waits at the end again
      q.replaceCard(1, question: 'Nová otázka', answer: 'Nová odpověď', tags: ['ai_gen']);
      q.answer(Rating.know);
      expect((q.current!.cardId, q.current!.question, q.current!.answer), (1, 'Nová otázka', 'Nová odpověď'));
      expect(q.current!.tags, ['ai_gen']);
    });

    test('#23: a deleted card leaves the queue and the total', () {
      final q = SessionQueue([card(1), card(2), card(3)]);
      q.answer(Rating.dontKnow); // 1 answered and re-queued: total 4
      q.remove(1); // only its waiting copy goes; the answer stays counted
      expect((q.current!.cardId, q.total, q.remaining), (2, 3, 2));
      q.remove(2);
      expect((q.current!.cardId, q.position, q.total), (3, 2, 2));
      q.remove(3);
      expect(q.isDone, isTrue);
    });

    test('Přeskočit moves the card to the end without counting', () {
      final q = SessionQueue([card(1), card(2), card(3)]);
      q.skip();
      expect(q.current!.cardId, 2);
      expect(q.next!.cardId, 3);
      expect((q.position, q.total, q.remaining), (1, 3, 3));
      q.answer(Rating.know);
      q.answer(Rating.know);
      expect(q.current!.cardId, 1);
    });

    test('skipping the last card keeps it', () {
      final q = SessionQueue([card(1)]);
      q.skip();
      expect(q.current!.cardId, 1);
    });

    test('empty session', () {
      final q = SessionQueue([]);
      expect(q.isDone, isTrue);
      expect((q.position, q.total), (1, 0));
    });

    test('#31: isRelearn is true only when the front card was re-queued after dontKnow', () {
      final q = SessionQueue([card(1), card(2)]);
      expect(q.isRelearn, isFalse);
      q.answer(Rating.dontKnow); // card 1 requeued to end
      expect(q.isRelearn, isFalse); // current is card 2 (not requeued)
      q.answer(Rating.know); // card 2 finished
      expect(q.isRelearn, isTrue); // current is card 1 (requeued!)
      expect(q.current!.cardId, 1);
      q.answer(Rating.know); // card 1 finished
      expect(q.isDone, isTrue);
      expect(q.isRelearn, isFalse);
    });
  });

  group('SessionTally', () {
    const know = ReviewItem(id: 'a', cardId: 1, rating: Rating.know);
    const dontKnow = ReviewItem(id: 'b', cardId: 2, rating: Rating.dontKnow);

    test('shows predicted points until the server answers', () {
      final t = SessionTally()
        ..add(know, 11)
        ..add(dontKnow, 2);
      expect(t.points, 13);
      expect((t.knowCount, t.dontKnowCount, t.graded), (1, 1, 2));
    });

    test('#19: Těžké and Snadné count as correct and add their points', () {
      final t = SessionTally()
        ..add(know, 11)
        ..add(dontKnow, 2)
        ..add(const ReviewItem(id: 'c', cardId: 3, rating: Rating.hard), 11)
        ..add(const ReviewItem(id: 'd', cardId: 4, rating: Rating.easy), 11);
      expect((t.graded, t.correctCount, t.knowCount), (4, 3, 1));
      expect((t.countOf(Rating.hard), t.pointsOf(Rating.easy)), (1, 11));
      expect(t.points, 35);
      // An older server sends no Těžké / Snadné values: they are worth a Vím.
      final points = PointsValue.fromJson({'know': 11, 'dontKnow': 2});
      expect((points.of(Rating.hard), points.of(Rating.easy)), (11, 11));
    });

    test('server points win, rejected answers are dropped, milestones add a bonus', () {
      final t = SessionTally()
        ..add(know, 11)
        ..add(dontKnow, 2)
        ..add(const ReviewItem(id: 'c', cardId: 3, rating: Rating.know), 11);
      t.apply(batchResult(
        [
          const ReviewResult(id: 'a', status: 'applied', pointsAwarded: 12, multiplier: 1.2),
          const ReviewResult(id: 'b', status: 'duplicate', pointsAwarded: 2, multiplier: 1.2),
          const ReviewResult(id: 'c', status: 'rejected', code: 'cardNotFound'),
        ],
        events: const [AppEvent(type: 'goalMet'), AppEvent(type: 'milestone', days: 7, bonus: 50)],
      ));
      expect(t.knowPoints, 12);
      expect(t.dontKnowPoints, 2);
      expect(t.bonusPoints, 50);
      expect(t.points, 64);
      expect(t.graded, 2);
      expect(t.goalMetInSession, isTrue);
      expect(t.lastMultiplier, 1.2);
      expect(t.milestones.single.days, 7);
    });

    test('ignores responses for answers of another session', () {
      final t = SessionTally()..add(know, 11);
      t.apply(batchResult(
        [const ReviewResult(id: 'zzz', status: 'applied', pointsAwarded: 10, multiplier: 1)],
        events: const [AppEvent(type: 'goalMet')],
      ));
      expect(t.points, 11);
      expect(t.goalMetInSession, isFalse);
    });
  });

  group('CardIntervals (#31)', () {
    test('parses full JSON and maps ratings correctly', () {
      final intervals = CardIntervals.fromJson({
        'dontKnow': '1m',
        'hard': '6m',
        'know': '10m',
        'easy': '8d',
      });
      expect(intervals.dontKnow, '1m');
      expect(intervals.hard, '6m');
      expect(intervals.know, '10m');
      expect(intervals.easy, '8d');
      expect(intervals.forRating(Rating.dontKnow), '1m');
      expect(intervals.forRating(Rating.hard), '6m');
      expect(intervals.forRating(Rating.know), '10m');
      expect(intervals.forRating(Rating.easy), '8d');
      expect(intervals.toJson(), {
        'dontKnow': '1m',
        'hard': '6m',
        'know': '10m',
        'easy': '8d',
      });
    });

    test('parses partial JSON with nullable hard and easy', () {
      final intervals = CardIntervals.fromJson({
        'dontKnow': '10m',
        'know': '1d',
      });
      expect(intervals.dontKnow, '10m');
      expect(intervals.hard, isNull);
      expect(intervals.know, '1d');
      expect(intervals.easy, isNull);
      expect(intervals.forRating(Rating.hard), isNull);
      expect(intervals.forRating(Rating.easy), isNull);
      expect(intervals.toJson(), {
        'dontKnow': '10m',
        'know': '1d',
      });
    });

    test('SessionCard parses intervals and relearnIntervals and preserves them on edit', () {
      final cardJson = {
        'cardId': 42,
        'deckId': 1,
        'question': 'Otázka',
        'answer': 'Odpověď',
        'kind': 'review',
        'tags': ['csharp'],
        'intervals': {'dontKnow': '10m', 'hard': '1d', 'know': '3d', 'easy': '7d'},
        'relearnIntervals': {'dontKnow': '10m', 'hard': '15m', 'know': '1d', 'easy': '3d'},
      };
      final sc = SessionCard.fromJson(cardJson);
      expect(sc.intervals?.know, '3d');
      expect(sc.relearnIntervals?.hard, '15m');

      final edited = sc.edited(question: 'Nová', answer: 'Nová', tags: ['csharp']);
      expect(edited.intervals?.know, '3d');
      expect(edited.relearnIntervals?.hard, '15m');
    });
  });
}
