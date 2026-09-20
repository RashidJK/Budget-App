import 'remote_txn.dart';

/// A remote feed of money transactions the app can pull and record.
///
/// The real implementation will front *your backend* (which holds the Airtel
/// OAuth secrets and calls Airtel's Transactions-Summary API) — never Airtel
/// directly, since a mobile app can't safely hold merchant credentials. Until
/// that backend and its exact response shape exist, [MockAirtelSource] stands in
/// so the whole pipeline is built and tested.
abstract class TransactionSource {
  /// A human label for the source, shown on the connect screen.
  String get label;

  /// Transactions at or after [since] (null = everything the source will give),
  /// newest first. Implementations should be idempotent — the sync dedups by
  /// [RemoteTxn.reference], so returning overlap is safe.
  Future<List<RemoteTxn>> fetchSince(DateTime? since);
}

/// Stand-in Airtel Money source: a handful of realistic Tanzanian Airtel Money
/// transactions so the sync, mapping and UI can be exercised end-to-end before a
/// backend exists. Swap this for an HttpTransactionSource pointed at your proxy.
class MockAirtelSource implements TransactionSource {
  const MockAirtelSource();

  @override
  String get label => 'Airtel Money (demo)';

  @override
  Future<List<RemoteTxn>> fetchSince(DateTime? since) async {
    // A small, deliberate delay so the "Sync now" spinner is visible.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final now = DateTime.now();
    final all = <RemoteTxn>[
      RemoteTxn(
        reference: 'AIR-9001',
        amount: 50000,
        direction: TxnDirection.inbound,
        type: RemoteTxnType.bankToWallet,
        timestamp: now.subtract(const Duration(hours: 2)),
        counterparty: 'NMB Bank',
        description: 'Bank transfer to Airtel Money',
        balanceAfter: 73000,
      ),
      RemoteTxn(
        reference: 'AIR-9002',
        amount: 20000,
        direction: TxnDirection.outbound,
        type: RemoteTxnType.cashOut,
        timestamp: now.subtract(const Duration(hours: 5)),
        counterparty: 'Agent 044213',
        description: 'Cash withdrawal at agent',
        balanceAfter: 23000,
      ),
      RemoteTxn(
        reference: 'AIR-9003',
        amount: 8000,
        direction: TxnDirection.outbound,
        type: RemoteTxnType.sendMoney,
        timestamp: now.subtract(const Duration(days: 1)),
        counterparty: 'John M.',
        description: 'Sent to 0682xxxxxx John M.',
        balanceAfter: 43000,
      ),
      RemoteTxn(
        reference: 'AIR-9004',
        amount: 5000,
        direction: TxnDirection.outbound,
        type: RemoteTxnType.airtime,
        timestamp: now.subtract(const Duration(days: 1, hours: 3)),
        description: 'Airtime purchase',
        balanceAfter: 51000,
      ),
      RemoteTxn(
        reference: 'AIR-9005',
        amount: 15000,
        direction: TxnDirection.inbound,
        type: RemoteTxnType.receiveMoney,
        timestamp: now.subtract(const Duration(days: 2)),
        counterparty: 'Amina',
        description: 'Received from 0754xxxxxx Amina',
        balanceAfter: 56000,
      ),
    ];
    if (since == null) return all;
    return all.where((t) => t.timestamp.isAfter(since)).toList();
  }
}
