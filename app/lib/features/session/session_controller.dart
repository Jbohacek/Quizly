import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import 'review_sync.dart';
import 'session_queue.dart';

enum SessionPhase { loading, error, empty, studying, saving, finished }

/// "Ještě 5 nových karet": new cards one tap adds over today's allowance.
const extraNewStep = 5;

/// Route of a session: one deck or all ([deckId] null), optionally with new cards over the allowance.
String sessionPath({int? deckId, int extraNew = 0}) => Uri(
      path: '/session',
      queryParameters: {if (deckId != null) 'deck': '$deckId', if (extraNew > 0) 'extra': '$extraNew'},
    ).toString();

/// What the Hotovo screen shows (spec §4.3).
class SessionResult {
  const SessionResult({required this.deckId, required this.tally, required this.summary, required this.knowPoints});

  final int? deckId;
  final SessionTally tally;
  final Summary summary;

  /// What the next Vím is worth (for "to je zhruba N × Vím" on the wishlist card).
  final int knowPoints;
}

/// One study session: loads the queue, records answers into the outbox, follows the
/// review responses (points, multiplier) and finishes once every answer is saved.
class SessionController extends ChangeNotifier {
  SessionController({
    required this._client,
    required this._sync,
    required this.deckId,
    this.extraNew = 0,
    String Function()? newId,
  })  : _newId = newId ?? const Uuid().v4 {
    _results = _sync.results.listen(_onResults);
    _statuses = _sync.statuses.listen((_) => _onStatus());
    _onStatus();
  }

  final ApiClient _client;
  final ReviewSync _sync;
  final String Function() _newId;
  final int? deckId;

  /// New cards asked for over today's allowance.
  final int extraNew;
  late final StreamSubscription<ReviewBatchResult> _results;
  late final StreamSubscription<SyncStatus> _statuses;

  SessionPhase phase = SessionPhase.loading;
  String? error;
  SessionQueue queue = SessionQueue(const []);
  final tally = SessionTally();
  PointsValue points = const PointsValue(know: 10, dontKnow: 2);
  double multiplier = 1;

  /// Four answer buttons (Nevím, Těžké, Vím, Snadné) instead of two (#19).
  bool fourRatings = false;
  Summary? summary;
  SessionResult? result;
  bool offline = false;

  /// The answer just given and its predicted points (the floating "+N"); null after a skip.
  ({Rating rating, int points})? lastAnswer;

  /// Changes on every answer or skip; keys the card widget so a returning card starts fresh.
  int turn = 0;

  bool _disposed = false;

  bool get canAnswer => phase == SessionPhase.studying && !offline && queue.current != null;

  Future<void> load() async {
    phase = SessionPhase.loading;
    error = null;
    _notify();
    try {
      final data = await _client.session(deckId: deckId, extraNew: extraNew);
      queue = SessionQueue(data.cards);
      points = data.points;
      multiplier = data.multiplier;
      fourRatings = data.fourRatings;
      phase = queue.isDone ? SessionPhase.empty : SessionPhase.studying;
    } on ApiException catch (e) {
      phase = SessionPhase.error;
      error = e.message;
    }
    _notify();
  }

  /// Vím or Nevím on the current card.
  void answer(Rating rating) {
    if (!canAnswer) return;
    final card = queue.current!;
    final item = ReviewItem(id: _newId(), cardId: card.cardId, rating: rating);
    tally.add(item, points.of(rating));
    lastAnswer = (rating: rating, points: points.of(rating));
    queue.answer(rating);
    turn++;
    unawaited(_sync.add(item));
    if (queue.isDone) {
      unawaited(_finish());
    }
    _notify();
  }

  /// Přeskočit: no points, nothing sent; the card goes to the end.
  void skip() {
    if (!canAnswer) return;
    queue.skip();
    lastAnswer = null;
    turn++;
    _notify();
  }

  /// The current card was edited (#23): the session goes on with the new text and tags.
  void cardEdited(int cardId, {required String question, required String answer, required List<String> tags}) {
    queue.replaceCard(cardId, question: question, answer: answer, tags: tags);
    _notify();
  }

  /// The current card was deleted: nothing is graded, the next card comes.
  void cardDeleted(int cardId) {
    queue.remove(cardId);
    lastAnswer = null;
    turn++;
    if (queue.isDone) {
      if (tally.graded == 0) {
        phase = SessionPhase.empty;
      } else {
        unawaited(_finish());
      }
    }
    _notify();
  }

  Future<void> _finish() async {
    phase = SessionPhase.saving;
    _notify();
    await _sync.whenIdle();
    if (_disposed) return;
    try {
      summary ??= (await _client.me()).summary;
    } on ApiException {
      // Shown without a summary refresh; the home screen reloads anyway.
    }
    if (_disposed) return;
    final s = summary;
    if (s == null) {
      phase = SessionPhase.error;
      error = null;
    } else {
      result = SessionResult(deckId: deckId, tally: tally, summary: s, knowPoints: points.know);
      phase = SessionPhase.finished;
    }
    _notify();
  }

  void _onResults(ReviewBatchResult response) {
    tally.apply(response);
    points = response.points;
    multiplier = response.summary.multiplier;
    summary = response.summary;
    _notify();
  }

  void _onStatus() {
    final next = _sync.status.offline;
    if (next == offline) return;
    offline = next;
    _notify();
  }

  /// Tries a waiting batch again now (the offline banner's button).
  void retrySync() => _sync.retryNow();

  /// The error screen's "Zkusit znovu": reload the queue, or finish again if answers were given.
  Future<void> recover() => tally.graded == 0 && turn == 0 ? load() : _finish();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _results.cancel();
    _statuses.cancel();
    super.dispose();
  }
}
