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

  /// Parse the `data.transactions` list of an Airtel "Transactions Summary"
  /// response (`GET /merchant/v1/transactions`) into normalized transactions.
  ///
  /// [userMsisdn] — your wallet's number, no country code — sets the direction:
  /// you as the payee is money in, you as the payer is money out. Only
  /// successful transactions come through; failed/in-progress ones (status TF /
  /// TIP) are dropped.
  static List<RemoteTxn> parseAirtelSummary(
    Map<String, dynamic> json, {
    String? userMsisdn,
  }) {
    final data = json['data'];
    if (data is! Map) return const [];
    final raw = data['transactions'];
    final items = raw is List ? raw : (raw is Map ? [raw] : const <dynamic>[]);
    final out = <RemoteTxn>[];
    for (final item in items) {
      if (item is! Map) continue;
      final txn = _fromAirtel(item.cast<String, dynamic>(), userMsisdn);
      if (txn != null) out.add(txn);
    }
    return out;
  }

  static RemoteTxn? _fromAirtel(Map<String, dynamic> item, String? userMsisdn) {
    final t =
        (item['transaction'] as Map?)?.cast<String, dynamic>() ?? const {};
    final status = t['status']?.toString().toUpperCase();
    if (status == 'TF' || status == 'TIP') return null; // only successful (TS)

    final service =
        (item['service'] as Map?)?.cast<String, dynamic>() ?? const {};
    final payer = (item['payer'] as Map?)?.cast<String, dynamic>() ?? const {};
    final payee = (item['payee'] as Map?)?.cast<String, dynamic>() ?? const {};

    final reference =
        (t['airtel_money_id'] ?? t['reference_number'] ?? t['id'] ?? '')
            .toString();
    if (reference.isEmpty) return null;

    final amount = double.tryParse((t['amount'] ?? '0').toString()) ?? 0;
    final createdAt = t['created_at'];
    final timestamp = createdAt is num
        ? DateTime.fromMillisecondsSinceEpoch(_toMillis(createdAt))
        : DateTime.now();

    final serviceType = (service['type'] ?? '').toString().toUpperCase();
    final payerMsisdn = payer['msisdn']?.toString();
    final payeeMsisdn = payee['msisdn']?.toString();

    // You as the payer → money left your wallet; as the payee → money came in.
    // With no configured number, a merchant feed defaults to money received.
    final direction = (userMsisdn != null && payerMsisdn == userMsisdn)
        ? TxnDirection.outbound
        : (userMsisdn != null && payeeMsisdn == userMsisdn)
        ? TxnDirection.inbound
        : TxnDirection.inbound;

    final type = switch (serviceType) {
      'CASHIN' => RemoteTxnType.bankToWallet,
      'MERCHPAY' =>
        direction == TxnDirection.outbound
            ? RemoteTxnType.billPay
            : RemoteTxnType.receiveMoney,
      _ =>
        direction == TxnDirection.outbound
            ? RemoteTxnType.sendMoney
            : RemoteTxnType.receiveMoney,
    };

    final counterparty = direction == TxnDirection.outbound
        ? payee['name'] as String?
        : payer['name'] as String?;

    return RemoteTxn(
      reference: reference,
      amount: amount,
      direction: direction,
      type: type,
      timestamp: timestamp,
      counterparty: counterparty,
      description: serviceType,
    );
  }

  /// Airtel `created_at` is normally epoch milliseconds; treat small (10-digit)
  /// values as seconds.
  static int _toMillis(num epoch) {
    final value = epoch.toInt();
    return value > 100000000000 ? value : value * 1000;
  }
}
