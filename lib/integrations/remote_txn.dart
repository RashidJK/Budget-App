/// Which way money moved in a remote transaction.
enum TxnDirection { inbound, outbound }

/// The kinds of Airtel Money transaction we know how to record. The source
/// classifies each message into one of these so the sync can map it to the
/// right ledger entry without re-parsing narratives downstream.
enum RemoteTxnType {
  /// Withdrawing cash from the wallet (wallet → cash on hand).
  cashOut,

  /// Sending money to another person or number.
  sendMoney,

  /// Receiving money from another person or number.
  receiveMoney,

  /// Topping the wallet up from a linked bank account (bank → wallet).
  bankToWallet,

  /// Buying airtime or a data bundle.
  airtime,

  /// Paying a biller or merchant (utilities, goods).
  billPay,

  /// Anything else the source couldn't classify.
  unknown,
}

/// A single transaction as it comes from a remote money source (Airtel Money),
/// already normalized: one amount, one direction, one stable [reference] used to
/// deduplicate so a transaction is never recorded twice.
///
/// This is deliberately provider-agnostic. A real Airtel backend response, or
/// the [MockAirtelSource], both produce these; the rest of the app only ever
/// sees this shape.
class RemoteTxn {
  const RemoteTxn({
    required this.reference,
    required this.amount,
    required this.direction,
    required this.type,
    required this.timestamp,
    this.counterparty,
    this.description = '',
    this.balanceAfter,
  });

  /// The provider's unique id for this transaction — the dedup key.
  final String reference;

  /// Always positive; [direction] carries the sign.
  final double amount;

  final TxnDirection direction;
  final RemoteTxnType type;
  final DateTime timestamp;

  /// The other party — a name or phone number, when the message names one.
  final String? counterparty;

  /// The raw narrative, kept for the entry's note and for debugging mapping.
  final String description;

  /// Wallet balance after the transaction, when provided.
  final double? balanceAfter;

  factory RemoteTxn.fromJson(Map<String, dynamic> json) {
    return RemoteTxn(
      reference: json['reference'] as String,
      amount: (json['amount'] as num).toDouble(),
      direction: json['direction'] == 'inbound'
          ? TxnDirection.inbound
          : TxnDirection.outbound,
      type: RemoteTxnType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RemoteTxnType.unknown,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      counterparty: json['counterparty'] as String?,
      description: json['description'] as String? ?? '',
      balanceAfter: (json['balanceAfter'] as num?)?.toDouble(),
    );
  }
}
