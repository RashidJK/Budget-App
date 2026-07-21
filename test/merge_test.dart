import 'package:budget/sync/merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stand-in for a syncable record, so the merge rules are tested
/// without dragging in expenses, categories or Firebase.
class _Record implements SyncFields {
  const _Record(
    this.id,
    this.value, {
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  final String id;

  @override
  final DateTime updatedAt;

  @override
  final DateTime? deletedAt;

  /// Marker so tests can tell which copy of a record survived.
  final String value;
}

DateTime _at(int minute) => DateTime(2026, 7, 20, 12, minute);

void main() {
  group('merge', () {
    test('records unique to one side are all kept', () {
      final merged = mergeById(
        local: [_Record('a', 'local', updatedAt: _at(1))],
        remote: [_Record('b', 'remote', updatedAt: _at(1))],
      );

      expect(merged.map((r) => r.id).toSet(), {'a', 'b'});
    });

    test('the newer version of a conflicting record wins', () {
      final merged = mergeById(
        local: [_Record('a', 'older', updatedAt: _at(1))],
        remote: [_Record('a', 'newer', updatedAt: _at(5))],
      );

      expect(merged.single.value, 'newer');
    });

    test('a newer local edit is not clobbered by stale remote data', () {
      final merged = mergeById(
        local: [_Record('a', 'local edit', updatedAt: _at(9))],
        remote: [_Record('a', 'stale', updatedAt: _at(2))],
      );

      expect(merged.single.value, 'local edit');
    });

    test('a local-only record survives — absence is not deletion', () {
      // The record was created on this device and never pushed. If an empty
      // remote meant "deleted", every first sync would wipe the device.
      final merged = mergeById(
        local: [_Record('a', 'unpushed', updatedAt: _at(1))],
        remote: <_Record>[],
      );

      expect(merged, hasLength(1));
      expect(merged.single.value, 'unpushed');
    });

    test('a remote tombstone deletes a record this device still has', () {
      final merged = mergeById(
        local: [_Record('a', 'alive', updatedAt: _at(1))],
        remote: [
          _Record('a', 'gone', updatedAt: _at(5), deletedAt: _at(5)),
        ],
      );

      expect(merged.single.isDeleted, isTrue);
      expect(visible(merged), isEmpty);
    });

    test('a deleted record stays deleted against an older edit', () {
      // The classic resurrection bug: another device edits an expense before
      // learning it was deleted. The older edit must not revive it.
      final merged = mergeById(
        local: [
          _Record('a', 'deleted', updatedAt: _at(5), deletedAt: _at(5)),
        ],
        remote: [_Record('a', 'edited earlier', updatedAt: _at(3))],
      );

      expect(merged.single.isDeleted, isTrue);
    });

    test('an edit newer than the delete revives the record', () {
      // Deliberate: the user deleted it, then edited it on another device
      // afterwards. The later action is the one they meant.
      final merged = mergeById(
        local: [
          _Record('a', 'deleted', updatedAt: _at(3), deletedAt: _at(3)),
        ],
        remote: [_Record('a', 'edited later', updatedAt: _at(8))],
      );

      expect(merged.single.isDeleted, isFalse);
      expect(merged.single.value, 'edited later');
    });

    test('an exact timestamp tie resolves in favour of the delete', () {
      final merged = mergeById(
        local: [_Record('a', 'edit', updatedAt: _at(4))],
        remote: [
          _Record('a', 'delete', updatedAt: _at(4), deletedAt: _at(4)),
        ],
      );

      expect(merged.single.isDeleted, isTrue);
    });

    test('a tie is resolved the same way regardless of argument order', () {
      final oneWay = mergeById(
        local: [_Record('a', 'edit', updatedAt: _at(4))],
        remote: [
          _Record('a', 'delete', updatedAt: _at(4), deletedAt: _at(4)),
        ],
      );
      final otherWay = mergeById(
        local: [
          _Record('a', 'delete', updatedAt: _at(4), deletedAt: _at(4)),
        ],
        remote: [_Record('a', 'edit', updatedAt: _at(4))],
      );

      // Order-dependent merges produce devices that disagree forever.
      expect(oneWay.single.isDeleted, otherWay.single.isDeleted);
    });

    test('merging is idempotent', () {
      final local = [_Record('a', 'x', updatedAt: _at(1))];
      final remote = [_Record('a', 'y', updatedAt: _at(5))];

      final once = mergeById(local: local, remote: remote);
      final twice = mergeById(local: once, remote: remote);

      expect(twice, hasLength(1));
      expect(twice.single.value, once.single.value);
    });

    test('merging empty sides is safe', () {
      expect(mergeById(local: <_Record>[], remote: <_Record>[]), isEmpty);
    });
  });

  group('changedSince', () {
    test('a never-synced device owes everything', () {
      final records = [
        _Record('a', 'x', updatedAt: _at(1)),
        _Record('b', 'y', updatedAt: _at(2)),
      ];

      expect(changedSince(records, null), hasLength(2));
    });

    test('only records touched since the last sync are outstanding', () {
      final records = [
        _Record('old', 'x', updatedAt: _at(1)),
        _Record('new', 'y', updatedAt: _at(9)),
      ];

      final outstanding = changedSince(records, _at(5));
      expect(outstanding.single.id, 'new');
    });

    test('a record written exactly at the boundary is re-sent', () {
      final records = [_Record('edge', 'x', updatedAt: _at(5))];

      // Pushing twice is harmless; dropping it loses the edit forever.
      expect(changedSince(records, _at(5)), hasLength(1));
    });

    test('tombstones are pushed like any other change', () {
      final records = [
        _Record('a', 'x', updatedAt: _at(9), deletedAt: _at(9)),
      ];

      expect(changedSince(records, _at(5)), hasLength(1));
    });
  });

  group('tombstones', () {
    test('live records are never pruned', () {
      final records = [_Record('a', 'x', updatedAt: _at(1))];

      expect(pruneTombstones(records, now: DateTime(2030)), hasLength(1));
    });

    test('a recent tombstone is retained so other devices still see it', () {
      final records = [
        _Record(
          'a',
          'x',
          updatedAt: DateTime(2026, 7, 20),
          deletedAt: DateTime(2026, 7, 20),
        ),
      ];

      final kept = pruneTombstones(records, now: DateTime(2026, 7, 25));
      expect(kept, hasLength(1));
    });

    test('a tombstone past the retention window is dropped', () {
      final records = [
        _Record(
          'a',
          'x',
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 1),
        ),
      ];

      final kept = pruneTombstones(records, now: DateTime(2026, 7, 20));
      expect(kept, isEmpty);
    });
  });

  group('visible', () {
    test('hides tombstones from the UI', () {
      final records = [
        _Record('a', 'alive', updatedAt: _at(1)),
        _Record('b', 'gone', updatedAt: _at(1), deletedAt: _at(1)),
      ];

      expect(visible(records).single.id, 'a');
    });
  });
}
