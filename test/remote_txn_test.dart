import 'package:budget/integrations/remote_txn.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parses the real Airtel "Transactions Summary" response shape.
Map<String, dynamic> _airtelResponse() => {
  'data': {
    'count': 4,
    'transactions': [
      // Merchant payment received (you are the payee) → money in.
      {
        'payee': {'currency': 'TZS', 'msisdn': '785000000', 'name': 'My Shop'},
        'payer': {'currency': 'TZS', 'msisdn': '754111111', 'name': 'Amina'},
        'service': {'type': 'MERCHPAY'},
        'transaction': {
          'airtel_money_id': 'AM-1001',
          'amount': '15000',
          'created_at': 1773040000000,
          'id': 5551,
          'reference_number': 'REF-1001',
          'status': 'TS',
        },
      },
      // Cash-in to the wallet (you are the payee) → money in.
      {
        'payee': {'currency': 'TZS', 'msisdn': '785000000', 'name': 'My Shop'},
        'payer': {'currency': 'TZS', 'msisdn': '0', 'name': 'Agent'},
        'service': {'type': 'CASHIN'},
        'transaction': {
          'airtel_money_id': 'AM-1002',
          'amount': '50000',
          'created_at': 1773030000000,
          'id': 5552,
          'status': 'TS',
        },
      },
      // Merchant payment where you are the payer → money out.
      {
        'payee': {'currency': 'TZS', 'msisdn': '900001', 'name': 'DAWASA'},
        'payer': {'currency': 'TZS', 'msisdn': '785000000', 'name': 'My Shop'},
        'service': {'type': 'MERCHPAY'},
        'transaction': {
          'airtel_money_id': 'AM-1003',
          'amount': '12000',
          'created_at': 1772940000000,
          'id': 5553,
          'status': 'TS',
        },
      },
      // Failed transaction — must be dropped.
      {
        'payee': {'currency': 'TZS', 'msisdn': '785000000', 'name': 'My Shop'},
        'payer': {'currency': 'TZS', 'msisdn': '754222222', 'name': 'Juma'},
        'service': {'type': 'MERCHPAY'},
        'transaction': {
          'airtel_money_id': 'AM-1004',
          'amount': '9000',
          'created_at': 1772800000000,
          'id': 5554,
          'status': 'TF',
        },
      },
    ],
  },
  'status': {'code': 200, 'message': 'SUCCESS', 'success': true},
};

void main() {
  test('parses successful transactions and drops failed ones', () {
    final txns = RemoteTxn.parseAirtelSummary(
      _airtelResponse(),
      userMsisdn: '785000000',
    );
    // The TF one is dropped.
    expect(txns.length, 3);
    expect(txns.every((t) => t.reference != 'AM-1004'), isTrue);
  });

  test('sets direction and type from service.type and who you are', () {
    final byRef = {
      for (final t in RemoteTxn.parseAirtelSummary(
        _airtelResponse(),
        userMsisdn: '785000000',
      ))
        t.reference: t,
    };

    // MERCHPAY, you are payee → money in, classed as received from the payer.
    final received = byRef['AM-1001']!;
    expect(received.direction, TxnDirection.inbound);
    expect(received.type, RemoteTxnType.receiveMoney);
    expect(received.counterparty, 'Amina');
    expect(received.amount, 15000);

    // CASHIN → a wallet top-up, money in.
    final cashin = byRef['AM-1002']!;
    expect(cashin.direction, TxnDirection.inbound);
    expect(cashin.type, RemoteTxnType.bankToWallet);

    // MERCHPAY, you are payer → money out, a bill payment to the payee.
    final paid = byRef['AM-1003']!;
    expect(paid.direction, TxnDirection.outbound);
    expect(paid.type, RemoteTxnType.billPay);
    expect(paid.counterparty, 'DAWASA');
  });

  test('reads epoch-millisecond timestamps', () {
    final txn = RemoteTxn.parseAirtelSummary(
      _airtelResponse(),
      userMsisdn: '785000000',
    ).firstWhere((t) => t.reference == 'AM-1001');
    expect(txn.timestamp, DateTime.fromMillisecondsSinceEpoch(1773040000000));
  });

  test('empty or malformed payloads yield no transactions', () {
    expect(RemoteTxn.parseAirtelSummary(const {}), isEmpty);
    expect(RemoteTxn.parseAirtelSummary({'data': null}), isEmpty);
    expect(RemoteTxn.parseAirtelSummary({'data': {}}), isEmpty);
  });
}
