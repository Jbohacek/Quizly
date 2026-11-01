import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/api/api_exception.dart';
import 'package:quizly/core/api/models.dart';
import 'package:quizly/features/session/review_sync.dart';

import 'fixtures.dart';

ReviewItem item(int n, [Rating rating = Rating.know]) =>
    ReviewItem(id: '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}', cardId: n, rating: rating);

const network = ApiException(status: null, code: 'network');

/// A fake `POST /reviews`: answers with the queued outcomes, or applies everything.
class FakeServer {
  final batches = <List<ReviewItem>>[];
  final outcomes = <Object>[];

  Future<ReviewBatchResult> send(List<ReviewItem> batch) async {
    batches.add(batch);
    if (outcomes.isNotEmpty) {
      final next = outcomes.removeAt(0);
      if (next is ApiException) throw next;
      return next as ReviewBatchResult;
    }
    return appliedAll(batch);
  }
}

void main() {
  late FakeServer server;
  late MemoryOutboxStore store;
  late List<Duration> sleeps;

  ReviewSync sync({Sleep? sleep}) => ReviewSync(
        userId: 7,
        store: store,
        send: server.send,
        sleep: sleep ??
            (d) async {
              sleeps.add(d);
            },
      );

  setUp(() {
    server = FakeServer();
    store = MemoryOutboxStore();
    sleeps = [];
  });

  test('sends an answer at once and empties the outbox', () async {
    final s = sync();
    await s.start();
    final results = <ReviewBatchResult>[];
    s.results.listen(results.add);
    await s.add(item(1));
    await s.whenIdle();
    expect(server.batches.single.single.id, item(1).id);
    expect(s.pending, isEmpty);
    expect(store.data[7], isEmpty);
    await pumpEventQueue();
    expect(results, hasLength(1));
  });

  test('retries the same UUIDs with back-off and goes offline after 2 failures', () async {
    server.outcomes.addAll([network, network, network]);
    final statuses = <SyncStatus>[];
    final s = sync();
    s.statuses.listen(statuses.add);
    await s.start();
    await s.add(item(1));
    await s.whenIdle();

    expect(server.batches, hasLength(4));
    expect(server.batches.map((b) => b.single.id).toSet(), {item(1).id});
    expect(sleeps, const [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)]);
    expect(statuses.any((x) => x.offline), isTrue);
    expect(s.status.offline, isFalse);
    expect(s.status.failures, 0);
  });

  test('back-off is capped at 30 s', () async {
    server.outcomes.addAll(List.filled(8, network));
    final s = sync();
    await s.start();
    await s.add(item(1));
    await s.whenIdle();
    expect(sleeps.map((d) => d.inSeconds), [1, 2, 4, 8, 15, 30, 30, 30]);
  });

  test('429 waits for Retry-After', () async {
    server.outcomes.add(const ApiException(status: 429, code: 'rateLimited', retryAfter: Duration(seconds: 42)));
    final s = sync();
    await s.start();
    await s.add(item(1));
    await s.whenIdle();
    expect(sleeps, const [Duration(seconds: 42)]);
    expect(server.batches, hasLength(2));
  });

  test('a 4xx client error drops the batch', () async {
    server.outcomes.add(const ApiException(status: 400, code: 'validation'));
    final s = sync();
    await s.start();
    await s.add(item(1));
    await s.whenIdle();
    expect(server.batches, hasLength(1));
    expect(s.pending, isEmpty);
  });

  test('401 stops sending and keeps the outbox for the next login', () async {
    server.outcomes.add(const ApiException(status: 401, code: 'refreshTokenInvalid'));
    final s = sync();
    await s.start();
    await s.add(item(1));
    await pumpEventQueue();
    expect(s.status.stopped, isTrue);
    expect(s.pending, hasLength(1));
    expect(store.data[7], hasLength(1));
  });

  test('sends at most 50 answers per request, oldest first, one request at a time', () async {
    final gate = Completer<void>();
    var inFlight = 0;
    var maxInFlight = 0;
    final s = ReviewSync(
      userId: 7,
      store: store,
      send: (batch) async {
        inFlight++;
        maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
        server.batches.add(batch);
        await gate.future;
        inFlight--;
        return appliedAll(batch);
      },
    );
    await s.start();
    for (var i = 1; i <= 60; i++) {
      await s.add(item(i));
    }
    gate.complete();
    await s.whenIdle();
    expect(maxInFlight, 1);
    // The first request left with answer 1 alone; the next took 50, the last the rest.
    expect(server.batches.map((b) => b.length), [1, 50, 9]);
    expect(server.batches.expand((b) => b).map((i) => i.cardId), List.generate(60, (i) => i + 1));
  });

  test('the outbox survives a restart and is sent on the next start', () async {
    server.outcomes.add(const ApiException(status: 401, code: 'unauthorized'));
    final first = sync();
    await first.start();
    await first.add(item(1, Rating.dontKnow));
    await pumpEventQueue();
    first.dispose();

    final second = sync();
    await second.start();
    await second.whenIdle();
    expect(server.batches.last.single.id, item(1).id);
    expect(server.batches.last.single.rating, Rating.dontKnow);
    expect(store.data[7], isEmpty);
  });

  test('no connectivity shows offline; coming back retries at once', () async {
    final never = Completer<void>();
    server.outcomes.add(network);
    final s = sync(sleep: (_) => never.future);
    await s.start();
    await s.add(item(1));
    await pumpEventQueue();
    s.setConnectivity(connected: false);
    expect(s.status.offline, isTrue);
    s.setConnectivity(connected: true);
    await s.whenIdle();
    expect(s.status.offline, isFalse);
    expect(server.batches, hasLength(2));
  });
}
