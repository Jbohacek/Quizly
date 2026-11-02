import '../../core/api/models.dart';

/// The in-memory queue of one study session (CLAUDE.md §5.2, spec §4.2).
///
/// - Vím / Nevím remove the card. A Nevím card goes once more to the end of the queue;
///   the second answer is a normal review and is never re-queued again.
/// - Přeskočit moves the card to the end and sends nothing.
/// - "Karta X z Y": Y = initial length + re-queued cards; skips don't change it.
class SessionQueue {
  SessionQueue(List<SessionCard> cards)
      : _queue = [for (final c in cards) _Entry(c, requeued: false)],
        _initial = cards.length;

  final List<_Entry> _queue;
  int _initial;
  int _requeued = 0;
  int _graded = 0;

  SessionCard? get current => _queue.isEmpty ? null : _queue.first.card;

  /// The card after [current], for the stack preview.
  SessionCard? get next => _queue.length < 2 ? null : _queue[1].card;

  bool get isDone => _queue.isEmpty;

  /// Cards left, including [current].
  int get remaining => _queue.length;

  /// Graded answers so far.
  int get graded => _graded;

  /// Y in "Karta X z Y".
  int get total => _initial + _requeued;

  /// X in "Karta X z Y".
  int get position => (_graded + 1).clamp(1, total == 0 ? 1 : total);

  /// Records Vím / Nevím for [current] and moves on.
  void answer(Rating rating) {
    final entry = _queue.removeAt(0);
    _graded++;
    if (rating == Rating.dontKnow && !entry.requeued) {
      _queue.add(_Entry(entry.card, requeued: true));
      _requeued++;
    }
  }

  /// Moves [current] to the end of the queue.
  void skip() {
    if (_queue.length < 2) return;
    _queue.add(_queue.removeAt(0));
  }

  /// The card was edited during the session (#23): every copy shows the new text.
  void replaceText(int cardId, {required String question, required String answer}) {
    for (var i = 0; i < _queue.length; i++) {
      final entry = _queue[i];
      if (entry.card.cardId == cardId) {
        _queue[i] = _Entry(entry.card.withText(question: question, answer: answer), requeued: entry.requeued);
      }
    }
  }

  /// The card was deleted during the session: it leaves the queue and "Karta X z Y".
  void remove(int cardId) {
    for (final entry in _queue.where((e) => e.card.cardId == cardId).toList()) {
      _queue.remove(entry);
      if (entry.requeued) {
        _requeued--;
      } else {
        _initial--;
      }
    }
  }
}

class _Entry {
  const _Entry(this.card, {required this.requeued});

  final SessionCard card;
  final bool requeued;
}

/// Points and counts of one session, for the header and the Hotovo screen (spec §4.3).
///
/// Shows the predicted points at once and replaces them with the server's `pointsAwarded`
/// when the review response arrives (api.md §11.2–4).
class SessionTally {
  final _answers = <String, _Answer>{};
  final _milestones = <AppEvent>[];
  final _wishlistReached = <AppEvent>[];
  bool goalMetInSession = false;
  double? lastMultiplier;

  /// Records an answer with the points it is predicted to earn.
  void add(ReviewItem item, int predicted) => _answers[item.id] = _Answer(item.rating, predicted);

  /// Applies a review response: real points for our answers, events.
  void apply(ReviewBatchResult response) {
    // Responses for answers of an earlier session (outbox left over from the last run) aren't ours.
    if (!response.results.any((r) => _answers.containsKey(r.id))) return;
    for (final r in response.results) {
      final answer = _answers[r.id];
      if (answer == null) continue;
      if (r.status == 'rejected') {
        _answers.remove(r.id);
      } else {
        answer.awarded = r.pointsAwarded;
        lastMultiplier = r.multiplier ?? lastMultiplier;
      }
    }
    for (final e in response.events) {
      if (e.type == 'goalMet') goalMetInSession = true;
      if (e.type == 'milestone') _milestones.add(e);
      if (e.type == 'wishlistReached') _wishlistReached.add(e);
    }
  }

  Iterable<_Answer> _of(Rating rating) => _answers.values.where((a) => a.rating == rating);

  int get knowCount => _of(Rating.know).length;
  int get dontKnowCount => _of(Rating.dontKnow).length;
  int get graded => _answers.length;
  int get knowPoints => _of(Rating.know).fold(0, (sum, a) => sum + a.points);
  int get dontKnowPoints => _of(Rating.dontKnow).fold(0, (sum, a) => sum + a.points);
  List<AppEvent> get milestones => List.unmodifiable(_milestones);

  /// Wishlist items the balance reached during this session.
  List<AppEvent> get wishlistReached => List.unmodifiable(_wishlistReached);
  int get bonusPoints => _milestones.fold(0, (sum, e) => sum + (e.bonus ?? 0));

  /// Everything earned in this session.
  int get points => knowPoints + dontKnowPoints + bonusPoints;
}

class _Answer {
  _Answer(this.rating, this.predicted);

  final Rating rating;
  final int predicted;
  int? awarded;

  int get points => awarded ?? predicted;
}
