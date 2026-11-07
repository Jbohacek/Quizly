import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/features/notifications/notification_store.dart';
import 'package:quizly/features/onboarding/onboarding_store.dart';

/// A storage that fails every call (SharedPreferences can throw on a broken install).
class _BrokenStore implements KeyValueStore {
  @override
  Future<String?> read(String key) => Future.error(StateError('broken'));

  @override
  Future<void> write(String key, String? value) => Future.error(StateError('broken'));
}

/// OnboardingStore states (#41): the intro runs once per install and never after an update.
void main() {
  Future<OnboardingStore> start(KeyValueStore kv, {required bool signedIn}) async {
    final store = OnboardingStore(kv);
    await store.init(alreadySignedIn: signedIn);
    return store;
  }

  test('fresh install: nothing pending until the first login, then saved as pending', () async {
    final kv = MemoryKeyValueStore();
    final store = await start(kv, signedIn: false);
    expect(store.isPending, isFalse);
    expect(store.isDone, isFalse);

    expect(await store.onLogin(), isTrue);
    expect(store.isPending, isTrue);
    expect(kv.data['quizly.onboarding'], 'pending');
  });

  test('closed during the intro: it comes back on the next start while signed in', () async {
    final kv = MemoryKeyValueStore()..data['quizly.onboarding'] = 'pending';
    final store = await start(kv, signedIn: true);
    expect(store.isPending, isTrue);
    expect(store.isDone, isFalse);
  });

  test('closed during the intro and signed out since: it comes after the next login', () async {
    final kv = MemoryKeyValueStore()..data['quizly.onboarding'] = 'pending';
    final store = await start(kv, signedIn: false);
    expect(store.isPending, isFalse);
    expect(await store.onLogin(), isTrue);
  });

  test('finished: saved as done, never again on a restart or a later login', () async {
    final kv = MemoryKeyValueStore();
    final store = await start(kv, signedIn: false);
    await store.onLogin();
    await store.complete();
    expect(kv.data['quizly.onboarding'], 'done');
    expect(store.isPending, isFalse);
    expect(await store.onLogin(), isFalse);

    final restarted = await start(kv, signedIn: false);
    expect(restarted.isDone, isTrue);
    expect(await restarted.onLogin(), isFalse);
  });

  test('an update from a version without the intro, signed in: marked done and saved', () async {
    final kv = MemoryKeyValueStore();
    final store = await start(kv, signedIn: true);
    expect(store.isDone, isTrue);
    expect(kv.data['quizly.onboarding'], 'done');
    expect(await store.onLogin(), isFalse);
  });

  test('a broken storage never throws: the intro still runs once in this run', () async {
    final store = await start(_BrokenStore(), signedIn: false);
    expect(await store.onLogin(), isTrue);
    await store.complete();
    expect(store.isDone, isTrue);
    expect(await store.onLogin(), isFalse);
  });
}
