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
}
