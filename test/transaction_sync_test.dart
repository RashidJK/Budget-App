import 'package:budget/integrations/remote_txn.dart';
import 'package:budget/integrations/transaction_source.dart';
import 'package:budget/integrations/transaction_sync.dart';
import 'package:budget/models/activity.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records a fixed list of transactions, so a test controls exactly what syncs.
class _FixedSource implements TransactionSource {
  _FixedSource(this.txns);
  final List<RemoteTxn> txns;
  @override
  String get label => 'Fixed';
  @override
  Future<List<RemoteTxn>> fetchSince(DateTime? since) async => txns;
}

Future<AppState> _freshState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await Storage.open());
}

RemoteTxn _txn(
  String ref,
  double amount,
  TxnDirection dir,
  RemoteTxnType type, {
  String? party,
}) {
  return RemoteTxn(
    reference: ref,
    amount: amount,
    direction: dir,
    type: type,
    timestamp: DateTime(2026, 3, 10, 9),
    counterparty: party,
  );
}

void main() {
  test('maps each transaction type to the right ledger entry', () async {
    final state = await _freshState();
    final source = _FixedSource([
      _txn(
        'r1',
        15000,
        TxnDirection.inbound,
        RemoteTxnType.receiveMoney,
        party: 'Amina',
      ),
      _txn(
        'r2',
        50000,
        TxnDirection.inbound,
        RemoteTxnType.bankToWallet,
        party: 'NMB',
      ),
      _txn('r3', 20000, TxnDirection.outbound, RemoteTxnType.cashOut),
      _txn('r4', 5000, TxnDirection.outbound, RemoteTxnType.airtime),
      _txn(
        'r5',
        8000,
        TxnDirection.outbound,
        RemoteTxnType.sendMoney,
        party: 'John',
      ),
    ]);

    final result = await TransactionSync(state: state, source: source).run();

    expect(result.imported, 5);
    expect(result.skipped, 0);

    // Inbound receive + both transfers (bank->wallet, cash-out) become
    // activities; airtime and send-money become expenses.
    expect(state.activities.length, 3);
    expect(state.expenses.length, 2);

    final incomes = state.activities.where(
      (a) => a.type == ActivityType.income,
    );
    final transfers = state.activities.where(
      (a) => a.type == ActivityType.transfer,
    );
    expect(incomes.length, 1);
    expect(transfers.length, 2);

    final airtime = state.expenses.firstWhere((e) => e.title == 'Airtime');
    expect(airtime.amount, 5000);
    expect(state.expenses.any((e) => e.title == 'Sent to John'), isTrue);
  });

  test('does not import the same reference twice', () async {
    final state = await _freshState();
    final source = _FixedSource([
      _txn('dup', 9000, TxnDirection.outbound, RemoteTxnType.airtime),
    ]);
    final sync = TransactionSync(state: state, source: source);

    final first = await sync.run();
    expect(first.imported, 1);

    // A second run over the same feed skips what's already recorded.
    final second = await sync.run();
    expect(second.imported, 0);
    expect(second.skipped, 1);
    expect(state.expenses.length, 1);
  });

  test('stamps entries with their import reference for dedup', () async {
    final state = await _freshState();
    final source = _FixedSource([
      _txn('AIR-1', 1000, TxnDirection.inbound, RemoteTxnType.receiveMoney),
    ]);
    await TransactionSync(state: state, source: source).run();

    final activity = state.activities.single;
    expect(activity.metadata['importRef'], 'AIR-1');
    expect(activity.source, ActivitySource.import_);
  });

  test('the Airtel mock source yields transactions the sync records', () async {
    final state = await _freshState();
    final result = await TransactionSync(
      state: state,
      source: const MockAirtelSource(),
    ).run();
    expect(result.imported, greaterThan(0));
  });
}
