import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/storage.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/brain_state.dart';
import 'api_client.dart';
import 'merge.dart';

/// What the sync layer is doing right now, for the status indicator.
enum SyncStatus { idle, syncing, synced, error }

/// Pushes every collection and pulls what changed, merging the two with the
/// same last-write-wins logic the app already uses ([mergeById]). Records are
/// moved as raw JSON maps, so this stays generic over every model — each one
/// already carries the id / updatedAt / deletedAt that merging needs.
///
/// It's a [ChangeNotifier] so the UI can show live status, and it listens to
/// the local stores so an edit syncs shortly after, not only on the next poll.
class SyncService extends ChangeNotifier {
  SyncService({
    required this.storage,
    required this.api,
    required this.auth,
    required this.appState,
    required this.brainState,
    this.pushDebounce = const Duration(seconds: 2),
  }) {
    // A local edit should reach the server without waiting for the next poll.
    appState.addListener(_onLocalChange);
    brainState.addListener(_onLocalChange);
  }

  final Storage storage;
  final SyncApi api;
  final AuthState auth;
  final AppState appState;
  final BrainState brainState;

  /// How long to wait after the last local edit before pushing — coalesces a
  /// burst of edits into one round-trip. Tests shorten it.
  final Duration pushDebounce;

  bool _busy = false;
  bool _applyingRemote = false;
  Timer? _pushTimer;

  SyncStatus _status = SyncStatus.idle;
  DateTime? _lastSyncedAt;

  /// What the sync layer is doing right now.
  SyncStatus get status => _status;

  /// When the last successful round-trip completed, or null if none yet.
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// collection name ⇄ how to read/write it from storage.
  late final Map<String, _Collection> _collections = {
    'expenses': _Collection(storage.readExpenses, storage.writeExpenses),
    'activities': _Collection(storage.readActivities, storage.writeActivities),
    'people': _Collection(storage.readPeople, storage.writePeople),
    'scenarios': _Collection(storage.readScenarios, storage.writeScenarios),
    'categories': _Collection(storage.readCategories, storage.writeCategories),
    'profiles': _Collection(storage.readProfiles, storage.writeProfiles),
    'accounts': _Collection(storage.readAccounts, storage.writeAccounts),
    'brain': _Collection(storage.readBrainItems, storage.writeBrainItems),
  };

  /// One push+pull round-trip. Returns true if it completed and applied the
  /// server's response. Safe to call often — overlapping calls are dropped.
  Future<bool> syncNow() async {
    final token = auth.token;
    if (token == null || token.isEmpty || _busy) return false;
    _busy = true;
    _pushTimer?.cancel();
    _setStatus(SyncStatus.syncing);
    try {
      final changes = {
        for (final entry in _collections.entries) entry.key: entry.value.read(),
      };
      final since = storage.readSyncCursor();

      final result = await api.sync(
        token: token,
        since: since,
        changes: changes,
      );
      switch (result) {
        case SyncAuthExpired():
          // The session is no longer valid — sign out so the gate prompts a
          // fresh sign-in rather than failing silently forever.
          await auth.signOut();
          _setStatus(SyncStatus.idle);
          return false;
        case SyncFailed():
          _setStatus(SyncStatus.error);
          return false;
        case SyncOk(:final data):
          var touched = false;
          final remote = data['changes'];
          if (remote is Map) {
            for (final entry in remote.entries) {
              final collection = _collections[entry.key.toString()];
              final value = entry.value;
              if (collection == null || value is! List) continue;
              final remoteMaps = value
                  .whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .toList();
              if (remoteMaps.isEmpty) continue;
              final merged = _merge(collection.read(), remoteMaps);
              await collection.write(merged);
              touched = true;
            }
          }
          final cursor = int.tryParse(data['cursor']?.toString() ?? '');
          if (cursor != null) await storage.writeSyncCursor(cursor);
          if (touched) {
            // Our own reload notifies AppState/BrainState; the guard keeps that
            // from bouncing straight back as another push.
            _applyingRemote = true;
            appState.reload();
            brainState.reload();
            _applyingRemote = false;
          }
          _lastSyncedAt = DateTime.now();
          _status = SyncStatus.synced;
          notifyListeners();
          return true;
      }
    } finally {
      _busy = false;
    }
  }

  /// Debounced push: after the last of a burst of local edits, sync once.
  void _onLocalChange() {
    if (_applyingRemote || !auth.isSignedIn) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDebounce, () => syncNow());
  }

  void _setStatus(SyncStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    appState.removeListener(_onLocalChange);
    brainState.removeListener(_onLocalChange);
    super.dispose();
  }

  List<Map<String, dynamic>> _merge(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> remote,
  ) {
    final merged = mergeById<_MapRecord>(
      local: local.map(_MapRecord.new).toList(),
      remote: remote.map(_MapRecord.new).toList(),
    );
    return merged.map((r) => r.map).toList();
  }
}

class _Collection {
  _Collection(this.read, this.write);
  final List<Map<String, dynamic>> Function() read;
  final Future<void> Function(List<Map<String, dynamic>>) write;
}

/// Adapts a raw storage map to [SyncFields] so [mergeById] can merge maps
/// without deserialising every model.
class _MapRecord implements SyncFields {
  _MapRecord(this.map);
  final Map<String, dynamic> map;

  @override
  String get id => map['id']?.toString() ?? '';

  @override
  DateTime get updatedAt =>
      DateTime.tryParse(map['updatedAt']?.toString() ?? '') ?? DateTime(2000);

  @override
  DateTime? get deletedAt {
    final raw = map['deletedAt'];
    return raw == null ? null : DateTime.tryParse(raw.toString());
  }
}
