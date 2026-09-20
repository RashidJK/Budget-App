import 'dart:convert';
import 'dart:io';

import 'remote_txn.dart';

/// A remote feed of money transactions the app can pull and record.
///
/// The real implementation ([HttpTransactionSource]) fronts *your backend*,
/// which holds the Airtel OAuth secrets and calls Airtel's Transactions-Summary
/// API (`GET /merchant/v1/transactions`) — never Airtel directly, since a mobile
/// app can't safely hold merchant credentials. [MockAirtelSource] emits the same
/// Airtel response shape so the exact same parser runs before a backend exists.
abstract class TransactionSource {
  /// A human label for the source, shown on the connect screen.
  String get label;

  /// Transactions at or after [since] (null = a sensible default window). The
  /// sync dedups by [RemoteTxn.reference], so returning overlap is safe.
  Future<List<RemoteTxn>> fetchSince(DateTime? since);
}

/// Pulls the Airtel "Transactions Summary" from a backend endpoint (your proxy)
/// and parses its real response shape. Point [endpoint] at your server; it does
/// Airtel's OAuth and returns the `{data:{transactions:[…]}}` body unchanged.
class HttpTransactionSource implements TransactionSource {
  const HttpTransactionSource({
    required this.endpoint,
    this.userMsisdn,
    this.authToken,
    this.pageSize = 100,
  });

  /// Your backend URL that returns Airtel-shaped transaction JSON.
  final Uri endpoint;

  /// Your wallet MSISDN (no country code), used to set each transaction's
  /// direction — you as payer is money out, as payee is money in.
  final String? userMsisdn;

  /// Bearer token for the app↔backend call, if your backend requires one.
  final String? authToken;

  final int pageSize;

  @override
  String get label => 'Airtel Money';

  @override
  Future<List<RemoteTxn>> fetchSince(DateTime? since) async {
    final from = (since ?? DateTime.now().subtract(const Duration(days: 30)))
        .millisecondsSinceEpoch;
    final to = DateTime.now().millisecondsSinceEpoch;
    final uri = endpoint.replace(
      queryParameters: {
        ...endpoint.queryParameters,
        'from': '$from',
        'to': '$to',
        'limit': '$pageSize',
        'offset': '0',
      },
    );

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (authToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $authToken',
        );
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        throw HttpException(
          'Transactions request failed (${response.statusCode})',
          uri: uri,
        );
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      return RemoteTxn.parseAirtelSummary(json, userMsisdn: userMsisdn);
    } finally {
      client.close(force: true);
    }
  }
}

/// Stand-in Airtel Money source. It builds a response in the **exact** Airtel
/// Transactions-Summary shape and runs it through the same parser the real
/// source uses, so the whole pipeline — parse, map, dedup, record — is exercised
/// before a backend exists. Swap this for [HttpTransactionSource] to go live.
class MockAirtelSource implements TransactionSource {
  const MockAirtelSource();

  /// The demo wallet number that "owns" these transactions.
  static const _me = '785000000';

  @override
  String get label => 'Airtel Money (demo)';

  @override
  Future<List<RemoteTxn>> fetchSince(DateTime? since) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final now = DateTime.now();
    int ms(Duration ago) => now.subtract(ago).millisecondsSinceEpoch;

    final response = <String, dynamic>{
      'data': {
        'count': 4,
        'transactions': [
          {
            'charges': {'service': '0'},
            'payee': {'currency': 'TZS', 'msisdn': _me, 'name': 'My Shop'},
            'payer': {
              'currency': 'TZS',
              'msisdn': '754111111',
              'name': 'Amina',
            },
            'service': {'type': 'MERCHPAY'},
            'transaction': {
              'airtel_money_id': 'AM-1001',
              'amount': '15000',
              'created_at': ms(const Duration(hours: 2)),
              'id': 5551,
              'reference_number': 'REF-1001',
              'status': 'TS',
            },
          },
          {
            'charges': {'service': '0'},
            'payee': {'currency': 'TZS', 'msisdn': _me, 'name': 'My Shop'},
            'payer': {
              'currency': 'TZS',
              'msisdn': '000000000',
              'name': 'Agent',
            },
            'service': {'type': 'CASHIN'},
            'transaction': {
              'airtel_money_id': 'AM-1002',
              'amount': '50000',
              'created_at': ms(const Duration(hours: 6)),
              'id': 5552,
              'reference_number': 'REF-1002',
              'status': 'TS',
            },
          },
          {
            'charges': {'service': '100'},
            'payee': {'currency': 'TZS', 'msisdn': '900001', 'name': 'DAWASA'},
            'payer': {'currency': 'TZS', 'msisdn': _me, 'name': 'My Shop'},
            'service': {'type': 'MERCHPAY'},
            'transaction': {
              'airtel_money_id': 'AM-1003',
              'amount': '12000',
              'created_at': ms(const Duration(days: 1)),
              'id': 5553,
              'reference_number': 'REF-1003',
              'status': 'TS',
            },
          },
          // A failed transaction — the parser drops it.
          {
            'payee': {'currency': 'TZS', 'msisdn': _me, 'name': 'My Shop'},
            'payer': {'currency': 'TZS', 'msisdn': '754222222', 'name': 'Juma'},
            'service': {'type': 'MERCHPAY'},
            'transaction': {
              'airtel_money_id': 'AM-1004',
              'amount': '9000',
              'created_at': ms(const Duration(days: 2)),
              'id': 5554,
              'reference_number': 'REF-1004',
              'status': 'TF',
            },
          },
        ],
      },
      'status': {
        'code': 200,
        'message': 'SUCCESS',
        'result_code': 'ESB000010',
        'success': true,
      },
    };

    final all = RemoteTxn.parseAirtelSummary(response, userMsisdn: _me);
    if (since == null) return all;
    return all.where((t) => t.timestamp.isAfter(since)).toList();
  }
}
