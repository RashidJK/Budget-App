/// Conflict resolution for local-first sync.
///
/// No Flutter, no Firebase — merging is arithmetic on timestamps, and keeping
/// it pure is what makes it testable without a network or an emulator.
///
/// ## The model
///
/// Every syncable record carries an [SyncFields.updatedAt] and a nullable
/// [SyncFields.deletedAt]. Two devices editing the same record is resolved by
/// **last write wins**: whichever copy has the later `updatedAt` survives
/// wholesale. Field-level merging would be more precise but needs per-field
/// timestamps, and for expense records the extra complexity buys almost
/// nothing — two people rarely edit the same expense's separate fields.
///
/// ## Why deletes are tombstones
///
/// Deleting a record outright cannot survive sync. Phone A deletes an expense;
/// phone B still has it and, on its next push, faithfully re-uploads it. The
/// record rises from the dead and no amount of retrying fixes it, because
/// absence carries no timestamp and so loses every comparison.
///
/// Instead a delete stamps `deletedAt` and keeps the row. The tombstone is a
/// fact with a time on it, so it beats any older edit and loses to a newer
/// one — which is what makes "delete here, edit there" resolve consistently.
/// Tombstones are hidden from the UI and pruned once every device has
/// certainly seen them; see [pruneTombstones].
library;

/// The sync metadata every replicated record carries.
abstract class SyncFields {
  /// Stable identity across devices.
  String get id;

  /// When this version was written. Drives conflict resolution.
  DateTime get updatedAt;

  /// Set when the record was deleted. Null for live records.
  DateTime? get deletedAt;
}

extension SyncFieldsX on SyncFields {
  bool get isDeleted => deletedAt != null;
}

/// Merges [local] and [remote] into one set, newest version of each id wins.
///
/// Records present on only one side are kept as-is: a record the remote has
/// never seen is a local creation still waiting to be pushed, not a deletion.
/// That asymmetry is the whole reason absence can't mean "deleted".
List<T> mergeById<T extends SyncFields>({
  required List<T> local,
  required List<T> remote,
}) {
  final byId = <String, T>{};

  for (final record in local) {
    byId[record.id] = record;
  }

  for (final record in remote) {
    final existing = byId[record.id];
    if (existing == null || _isNewer(record, existing)) {
      byId[record.id] = record;
    }
  }

  return byId.values.toList();
}

/// True when [candidate] should replace [current].
///
/// Ties break in favour of the deletion. Equal timestamps mean the two devices
/// wrote within the same millisecond, so neither is genuinely "later" — and
/// resurrecting something the user deleted is the worse of the two mistakes.
bool _isNewer<T extends SyncFields>(T candidate, T current) {
  if (candidate.updatedAt.isAfter(current.updatedAt)) return true;
  if (candidate.updatedAt.isBefore(current.updatedAt)) return false;
  return candidate.isDeleted && !current.isDeleted;
}

/// Records changed since [since], i.e. the ones this device owes the server.
///
/// A null [since] means "never synced", so everything is outstanding.
/// The comparison is inclusive of the boundary: a record written in the same
/// millisecond the sync started could have been missed by that sync, and
/// pushing it twice is harmless where dropping it is not.
List<T> changedSince<T extends SyncFields>(List<T> records, DateTime? since) {
  if (since == null) return List.of(records);
  return records
      .where((record) => !record.updatedAt.isBefore(since))
      .toList();
}

/// Drops tombstones older than [retention].
///
/// Deleted records can't be discarded immediately — a device that has been
/// offline longer than the tombstone survived would never learn about the
/// delete and would re-upload the record. The retention window is therefore a
/// bet on the longest plausible offline stretch. Thirty days is generous for a
/// phone app; the cost of being wrong is one resurrected expense, and the cost
/// of a shorter window is nothing but disk.
List<T> pruneTombstones<T extends SyncFields>(
  List<T> records, {
  Duration retention = const Duration(days: 30),
  DateTime? now,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(retention);

  return records.where((record) {
    final deletedAt = record.deletedAt;
    if (deletedAt == null) return true;
    return deletedAt.isAfter(cutoff);
  }).toList();
}

/// The live records, with tombstones hidden.
///
/// Everything the UI reads goes through here, so a deleted record is invisible
/// even though it is still on disk waiting to be replicated.
List<T> visible<T extends SyncFields>(List<T> records) =>
    records.where((record) => !record.isDeleted).toList();
