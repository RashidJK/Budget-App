import 'package:budget/models/brain_item.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/state/auth_state.dart';
import 'package:budget/state/brain_state.dart';
import 'package:budget/sync/api_client.dart';
import 'package:budget/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi implements SyncApi {
  _FakeApi(this.result);
  SyncResult result;
  Map<String, dynamic>? lastSent;

  @override
  Future<SyncResult> sync({
    required String token,
    required int since,
    required Map<String, List<Map<String, dynamic>>> changes,
  }) async {
    lastSent = {'token': token, 'since': since, 'changes': changes};
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Storage> freshStorage() async {
    SharedPreferences.setMockInitialValues({});
    return Storage.open();
  }

  SyncService service(Storage storage, SyncApi api, AuthState auth) =>
      SyncService(
        storage: storage,
        api: api,
        auth: auth,
        appState: AppState(storage),
        brainState: BrainState(storage),
      );

  test(
    'pull merges a remote record into storage and bumps the cursor',
    () async {
      final storage = await freshStorage();
      final auth = AuthState(storage);
      await auth.setSession('tok', email: 'a@b.c');
      final brainState = BrainState(storage);

      final now = DateTime(2026, 1, 1).toIso8601String();
      final api = _FakeApi(
        SyncOk({
          'cursor': 42,
          'changes': {
            'brain': [
              {
                'id': 'r1',
                'kind': 'note',
                'text': 'from another device',
                'createdAt': now,
                'updatedAt': now,
              },
            ],
          },
        }),
      );
      final sync = SyncService(
        storage: storage,
        api: api,
        auth: auth,
        appState: AppState(storage),
        brainState: brainState,
      );

      expect(await sync.syncNow(), isTrue);
      expect(storage.readSyncCursor(), 42);
      expect(storage.readBrainItems().any((m) => m['id'] == 'r1'), isTrue);
      expect(brainState.items.any((i) => i.id == 'r1'), isTrue);
      expect((api.lastSent!['changes'] as Map).containsKey('brain'), isTrue);
    },
  );

  test(
    'last-write-wins keeps the newer local edit over an older remote one',
    () async {
      final storage = await freshStorage();
      final auth = AuthState(storage);
      await auth.setSession('tok');
      final older = DateTime(2026, 1, 1).toIso8601String();
      final newer = DateTime(2026, 2, 1).toIso8601String();
      await storage.writeBrainItems([
        {
          'id': 'r1',
          'kind': 'note',
          'text': 'local newer',
          'createdAt': older,
          'updatedAt': newer,
        },
      ]);

      final api = _FakeApi(
        SyncOk({
          'cursor': 7,
          'changes': {
            'brain': [
              {
                'id': 'r1',
                'kind': 'note',
                'text': 'remote older',
                'createdAt': older,
                'updatedAt': older,
              },
            ],
          },
        }),
      );
      await service(storage, api, auth).syncNow();

      final r1 = storage.readBrainItems().firstWhere((m) => m['id'] == 'r1');
      expect(r1['text'], 'local newer');
    },
  );

  test('syncNow is a no-op when signed out', () async {
    final storage = await freshStorage();
    final auth = AuthState(storage); // no session
    final api = _FakeApi(const SyncFailed());
    expect(await service(storage, api, auth).syncNow(), isFalse);
    expect(api.lastSent, isNull);
  });

  test('an expired session signs the user out', () async {
    final storage = await freshStorage();
    final auth = AuthState(storage);
    await auth.setSession('tok', email: 'a@b.c');
    expect(auth.isSignedIn, isTrue);

    final api = _FakeApi(const SyncAuthExpired());
    expect(await service(storage, api, auth).syncNow(), isFalse);
    expect(auth.isSignedIn, isFalse); // bounced to signed-out
  });

  test('a successful round-trip reports synced with a timestamp', () async {
    final storage = await freshStorage();
    final auth = AuthState(storage);
    await auth.setSession('tok');
    final sync = service(storage, _FakeApi(SyncOk({'cursor': 1})), auth);

    expect(sync.status, SyncStatus.idle);
    await sync.syncNow();
    expect(sync.status, SyncStatus.synced);
    expect(sync.lastSyncedAt, isNotNull);
  });

  test('a transient failure reports an error and keeps the session', () async {
    final storage = await freshStorage();
    final auth = AuthState(storage);
    await auth.setSession('tok');
    final sync = service(storage, _FakeApi(const SyncFailed()), auth);

    await sync.syncNow();
    expect(sync.status, SyncStatus.error);
    expect(auth.isSignedIn, isTrue); // not an auth failure — stay signed in
  });

  test(
    'a local edit pushes shortly after, without waiting for a poll',
    () async {
      final storage = await freshStorage();
      final auth = AuthState(storage);
      await auth.setSession('tok');
      final brainState = BrainState(storage);
      final api = _FakeApi(SyncOk({'cursor': 1}));
      SyncService(
        storage: storage,
        api: api,
        auth: auth,
        appState: AppState(storage),
        brainState: brainState,
        pushDebounce: const Duration(milliseconds: 5),
      );

      expect(api.lastSent, isNull); // nothing synced yet
      await brainState.capture(BrainKind.note, 'jotted on this device');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(api.lastSent, isNotNull); // the edit triggered a push on its own
      final pushed = (api.lastSent!['changes'] as Map)['brain'] as List;
      expect(
        pushed.any((m) => (m as Map)['text'] == 'jotted on this device'),
        isTrue,
      );
    },
  );
}
