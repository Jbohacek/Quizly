import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';

/// Persists the review outbox per user, so killing the app loses no answers (api.md §11.5).
abstract interface class OutboxStore {
  Future<List<ReviewItem>> load(int userId);
  Future<void> save(int userId, List<ReviewItem> items);
}

class PrefsOutboxStore implements OutboxStore {
  String _key(int userId) => 'quizly.outbox.$userId';

  @override
  Future<List<ReviewItem>> load(int userId) async {
    final raw = (await SharedPreferences.getInstance()).getString(_key(userId));
    if (raw == null) return [];
    return [for (final j in jsonDecode(raw) as List) ReviewItem.fromJson(j as Json)];
  }

  @override
  Future<void> save(int userId, List<ReviewItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_key(userId));
    } else {
      await prefs.setString(_key(userId), jsonEncode([for (final i in items) i.toJson()]));
    }
  }
}

class MemoryOutboxStore implements OutboxStore {
  final data = <int, List<ReviewItem>>{};

  @override
  Future<List<ReviewItem>> load(int userId) async => [...?data[userId]];

  @override
  Future<void> save(int userId, List<ReviewItem> items) async => data[userId] = [...items];
}

@immutable
class SyncStatus {
  const SyncStatus({this.pending = 0, this.failures = 0, this.offline = false, this.stopped = false});

  /// Answers not confirmed by the server yet.
  final int pending;

  /// Failed attempts in a row.
  final int failures;

  /// Shown as "Jsi offline": 2 failures in a row or no connectivity (api.md §11.7).
  final bool offline;

  /// Sending stopped because the login ended; the outbox waits for the next login.
  final bool stopped;

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.pending == pending &&
      other.failures == failures &&
      other.offline == offline &&
      other.stopped == stopped;

  @override
  int get hashCode => Object.hash(pending, failures, offline, stopped);
}

typedef SendReviews = Future<ReviewBatchResult> Function(List<ReviewItem> batch);
typedef Sleep = Future<void> Function(Duration duration);

/// Sends answers to `POST /api/reviews` following the sync contract (api.md §11):
/// oldest first, max 50 per request, one request in flight, the same UUIDs on retry,
/// back-off 1, 2, 4, 8, 15, 30 s and then every 30 s, `Retry-After` on 429.
class ReviewSync {
  ReviewSync({required this.userId, required this._store, required this._send, Sleep? sleep})
      : _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  static const maxBatch = 50;
  static const backoff = [1, 2, 4, 8, 15, 30];

  final int userId;
  final OutboxStore _store;
  final SendReviews _send;
  final Sleep _sleep;

  final _outbox = <ReviewItem>[];
  final _results = StreamController<ReviewBatchResult>.broadcast();
  final _statuses = StreamController<SyncStatus>.broadcast();
  final _idle = <Completer<void>>[];

  SyncStatus _status = const SyncStatus();
  bool _noConnectivity = false;
  bool _running = false;
  bool _disposed = false;
  Completer<void>? _wake;

  /// Every successful response, in order.
  Stream<ReviewBatchResult> get results => _results.stream;

  Stream<SyncStatus> get statuses => _statuses.stream;

  SyncStatus get status => _status;

  List<ReviewItem> get pending => List.unmodifiable(_outbox);

  /// Loads the stored outbox and sends what's left from the last run.
  Future<void> start() async {
    _outbox.addAll(await _store.load(userId));
    _update();
    _pump();
  }

  /// Queues an answer and sends it right away (with anything still waiting).
  Future<void> add(ReviewItem item) async {
    _outbox.add(item);
    _update();
    await _store.save(userId, _outbox);
    _pump();
  }

  /// Completes once the outbox is empty.
  Future<void> whenIdle() {
    if (_outbox.isEmpty) return Future.value();
    final c = Completer<void>();
    _idle.add(c);
    return c.future;
  }

  /// The OS connectivity changed. Coming back online retries at once.
  void setConnectivity({required bool connected}) {
    _noConnectivity = !connected;
    _update();
    if (connected) retryNow();
  }

  /// Cuts a back-off wait short.
  void retryNow() {
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
    _pump();
  }

  void dispose() {
    _disposed = true;
    retryNow();
    _results.close();
    _statuses.close();
  }

  Future<void> _pump() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      while (_outbox.isNotEmpty && !_disposed) {
        final batch = _outbox.take(maxBatch).toList();
        try {
          final response = await _send(batch);
          if (_disposed) return;
          // applied, duplicate and rejected are all final; the whole batch leaves the outbox.
          _removeBatch(batch);
          await _store.save(userId, _outbox);
          _setFailures(0);
          _results.add(response);
        } on ApiException catch (e) {
          if (_disposed) return;
          if (e.status == 401) {
            // The login ended (api.md §11.8). Keep the outbox for the next login of this user.
            _status = SyncStatus(pending: _outbox.length, stopped: true);
            _statuses.add(_status);
            return;
          }
          if (!e.isTransient) {
            debugPrint('Review batch dropped: ${e.code} (${batch.length} answers)');
            _removeBatch(batch);
            await _store.save(userId, _outbox);
            _setFailures(0);
            continue;
          }
          _setFailures(_status.failures + 1);
          final wait = e.status == 429 && e.retryAfter != null
              ? e.retryAfter!
              : Duration(seconds: backoff[(_status.failures - 1).clamp(0, backoff.length - 1)]);
          final wake = _wake = Completer<void>();
          await Future.any([_sleep(wait), wake.future]);
          _wake = null;
        }
      }
    } finally {
      _running = false;
      _update();
      if (_outbox.isEmpty) {
        for (final c in _idle) {
          c.complete();
        }
        _idle.clear();
      }
    }
  }

  void _removeBatch(List<ReviewItem> batch) {
    final ids = {for (final b in batch) b.id};
    _outbox.removeWhere((i) => ids.contains(i.id));
  }

  void _setFailures(int failures) {
    _status = SyncStatus(pending: _outbox.length, failures: failures);
    _update();
  }

  void _update() {
    final next = SyncStatus(
      pending: _outbox.length,
      failures: _status.failures,
      offline: _noConnectivity || _status.failures >= 2,
      stopped: _status.stopped && _outbox.isNotEmpty,
    );
    if (next == _status) return;
    _status = next;
    if (!_statuses.isClosed) _statuses.add(next);
  }
}
