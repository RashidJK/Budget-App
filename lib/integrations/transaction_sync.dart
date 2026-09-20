import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/activity.dart';
import '../state/app_state.dart';
import 'remote_txn.dart';
import 'transaction_source.dart';

/// What one sync run did, for a bit of feedback on the connect screen.
class SyncResult {
  const SyncResult({
    required this.imported,
    required this.skipped,
    required this.titles,
  });

  /// New entries recorded this run.
  final int imported;

  /// Transactions already imported on an earlier run, skipped.
  final int skipped;

  /// The titles of what was recorded, for a summary line.
  final List<String> titles;

  bool get isEmpty => imported == 0;
}

/// Pulls transactions from a [TransactionSource] and records the new ones into
/// the ledger, mapping each Airtel Money transaction to the right kind of entry.
///
/// Deduplication is by [RemoteTxn.reference]: every entry it creates stores that
/// reference in `metadata['importRef']`, and a run skips any reference already
/// present. Since expenses and activities persist, this survives restarts with
/// no extra bookkeeping.
class TransactionSync {
  TransactionSync({required this.state, required this.source});

  final AppState state;
  final TransactionSource source;

  static const _uuid = Uuid();
  static const _kLastSynced = 'airtel_last_synced';

  /// When the last successful sync finished, if ever.
  static Future<DateTime?> lastSynced() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastSynced);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<void> markSynced(DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSynced, when.toIso8601String());
  }

  /// Fetch from the source and record everything not already imported. Oldest
  /// first, so the ledger's order matches how the transactions happened.
  Future<SyncResult> run({DateTime? since}) async {
    final fetched = await source.fetchSince(since);
    final seen = _importedRefs();
    final ordered = [...fetched]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    var imported = 0;
    var skipped = 0;
    final titles = <String>[];
    for (final txn in ordered) {
      if (seen.contains(txn.reference)) {
        skipped++;
        continue;
      }
      titles.add(await _record(txn));
      seen.add(txn.reference);
      imported++;
    }
    return SyncResult(imported: imported, skipped: skipped, titles: titles);
  }

  /// Every import reference already in the ledger.
  Set<String> _importedRefs() {
    final refs = <String>{};
    for (final e in state.expenses) {
      final ref = e.metadata['importRef'];
      if (ref is String) refs.add(ref);
    }
    for (final a in state.activities) {
      final ref = a.metadata['importRef'];
      if (ref is String) refs.add(ref);
    }
    return refs;
  }

  Future<String> _record(RemoteTxn txn) async {
    final account = _airtelAccountId();
    final meta = <String, dynamic>{
      'importRef': txn.reference,
      'importSource': 'airtel',
    };
    final party = txn.counterparty;

    switch (txn.type) {
      case RemoteTxnType.receiveMoney:
        final title = party == null ? 'Received' : 'Received from $party';
        await _activity(ActivityType.income, txn, account, meta, title);
        return title;

      case RemoteTxnType.bankToWallet:
        final title = 'Top-up from ${party ?? 'bank'}';
        await _activity(
          ActivityType.transfer,
          txn,
          account,
          meta,
          title,
          source: party ?? 'Bank',
          destination: 'Airtel Money',
        );
        return title;

      case RemoteTxnType.cashOut:
        const title = 'Cash withdrawal';
        await _activity(
          ActivityType.transfer,
          txn,
          account,
          meta,
          title,
          source: 'Airtel Money',
          destination: 'Cash',
        );
        return title;

      case RemoteTxnType.airtime:
        const title = 'Airtime';
        await _expense(title, txn, _categoryId('airtime'), account, meta);
        return title;

      case RemoteTxnType.billPay:
        final title = party == null ? 'Bill payment' : 'Paid $party';
        await _expense(title, txn, _categoryId('bills'), account, meta);
        return title;

      case RemoteTxnType.sendMoney:
        final title = party == null ? 'Money sent' : 'Sent to $party';
        await _expense(title, txn, _categoryId('other'), account, meta);
        return title;

      case RemoteTxnType.unknown:
        if (txn.direction == TxnDirection.inbound) {
          final title = party == null ? 'Received' : 'Received from $party';
          await _activity(ActivityType.income, txn, account, meta, title);
          return title;
        }
        final title = txn.description.isEmpty ? 'Payment' : txn.description;
        await _expense(title, txn, _categoryId('other'), account, meta);
        return title;
    }
  }

  Future<void> _activity(
    ActivityType type,
    RemoteTxn txn,
    String? account,
    Map<String, dynamic> meta,
    String description, {
    String? source,
    String? destination,
  }) {
    return state.addActivity(
      Activity(
        id: _uuid.v4(),
        type: type,
        amount: txn.amount,
        date: txn.timestamp,
        updatedAt: DateTime.now(),
        description: description,
        accountId: account,
        sourceAccount: source,
        destinationAccount: destination,
        source: ActivitySource.import_,
        note: txn.description,
        metadata: meta,
      ),
    );
  }

  Future<void> _expense(
    String title,
    RemoteTxn txn,
    String categoryId,
    String? account,
    Map<String, dynamic> meta,
  ) {
    return state.addExpense(
      title: title,
      amount: txn.amount,
      categoryId: categoryId,
      date: txn.timestamp,
      accountId: account,
      note: txn.description,
      metadata: meta,
    );
  }

  /// The preferred category if it exists, else a safe fallback.
  String _categoryId(String preferred) {
    final ids = state.categories.map((c) => c.id).toSet();
    if (ids.contains(preferred)) return preferred;
    if (ids.contains('other')) return 'other';
    return state.categories.isNotEmpty ? state.categories.first.id : 'other';
  }

  /// The account these Airtel transactions belong to, matched by name, else null
  /// (which lets [AppState.addExpense] fall back to the default account).
  String? _airtelAccountId() {
    for (final account in state.accounts) {
      final name = account.name.toLowerCase();
      if (name.contains('airtel') || name.contains('mobile')) return account.id;
    }
    return null;
  }
}
