import 'dart:io';

import 'package:airtel_proxy/airtel_client.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

/// A minimal Airtel Money OAuth2 proxy.
///
///   `GET /transactions?from=<epoch>&to=<epoch>&limit=&offset=`
///     → Airtel's /merchant/v1/transactions body, verbatim.
///
/// The Budget app points [HttpTransactionSource] at this and parses the result.
/// Config comes from environment variables (see .env.example); nothing secret is
/// ever sent to the app.
Future<void> main() async {
  final env = Platform.environment;

  final airtel = AirtelClient(
    baseUrl: env['AIRTEL_BASE_URL'] ?? 'https://openapi.airtel.co.tz',
    clientId: _require(env, 'AIRTEL_CLIENT_ID'),
    clientSecret: _require(env, 'AIRTEL_CLIENT_SECRET'),
    country: env['AIRTEL_COUNTRY'] ?? 'TZ',
    currency: env['AIRTEL_CURRENCY'] ?? 'TZS',
  );

  // Optional shared key for the app↔backend call. If set, callers must send
  // `Authorization: Bearer <PROXY_API_KEY>`. This is NOT the Airtel token.
  final apiKey = env['PROXY_API_KEY'];

  final router = Router()
    ..get('/health', (Request _) => Response.ok('ok'))
    ..get('/transactions', (Request request) async {
      if (apiKey != null &&
          request.headers['authorization'] != 'Bearer $apiKey') {
        return Response.forbidden('Invalid or missing API key.');
      }

      final q = request.url.queryParameters;
      final from = q['from'];
      final to = q['to'];
      if (from == null || to == null) {
        return Response(400, body: 'Query params "from" and "to" are required.');
      }

      try {
        final body = await airtel.transactions(
          from: from,
          to: to,
          limit: q['limit'] ?? '100',
          offset: q['offset'] ?? '0',
        );
        return Response.ok(
          body,
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        stderr.writeln('transactions error: $e');
        return Response.internalServerError(body: 'Upstream error.');
      }
    });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final port = int.parse(env['PORT'] ?? '8080');
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('Airtel proxy listening on :${server.port}');
}

String _require(Map<String, String> env, String key) {
  final value = env[key];
  if (value == null || value.isEmpty) {
    stderr.writeln('Missing required environment variable: $key');
    exit(64); // EX_USAGE
  }
  return value;
}
