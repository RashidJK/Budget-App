import 'dart:convert';
import 'dart:io';

import 'package:budget_api/airtel_client.dart';
import 'package:budget_api/auth.dart';
import 'package:budget_api/db.dart';
import 'package:budget_api/sync.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

/// The Budget/Spaces product API.
///
///   POST /auth/google  { idToken }        → { token, email, name }
///   POST /sync         (Bearer token)     → push local changes, pull remote
///   GET  /transactions (Airtel proxy, unchanged)
///   GET  /health
///
/// Config is all environment variables (see .env.example). Nothing secret ever
/// reaches the app.
Future<void> main() async {
  final env = Platform.environment;
  final dbUrl = _require(env, 'DATABASE_URL');
  final googleClientId = _require(env, 'GOOGLE_CLIENT_ID');
  final sessionSecret = _require(env, 'SESSION_SECRET');
  final corsOrigin = env['CORS_ORIGIN'] ?? '*';

  // Postgres may still be booting when we start (docker compose); retry briefly.
  late final Db db;
  for (var attempt = 1; ; attempt++) {
    try {
      db = await Db.open(dbUrl);
      break;
    } catch (e) {
      if (attempt >= 15) rethrow;
      stderr.writeln('DB not ready ($e); retrying in 2s…');
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  // The Airtel proxy is optional — only wired when credentials are present.
  AirtelClient? airtel;
  if ((env['AIRTEL_CLIENT_ID'] ?? '').isNotEmpty) {
    airtel = AirtelClient(
      baseUrl: env['AIRTEL_BASE_URL'] ?? 'https://openapi.airtel.co.tz',
      clientId: env['AIRTEL_CLIENT_ID']!,
      clientSecret: env['AIRTEL_CLIENT_SECRET'] ?? '',
      country: env['AIRTEL_COUNTRY'] ?? 'TZ',
      currency: env['AIRTEL_CURRENCY'] ?? 'TZS',
    );
  }
  final proxyApiKey = env['PROXY_API_KEY'];

  String? userFor(Request r) {
    final auth = r.headers['authorization'];
    if (auth == null || !auth.startsWith('Bearer ')) return null;
    return verifySession(auth.substring(7), sessionSecret);
  }

  final router = Router()
    ..get('/health', (Request _) => Response.ok('ok'))
    ..post('/auth/google', (Request request) async {
      final raw = await request.readAsString();
      Map<String, dynamic> body;
      try {
        body = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return Response(400, body: 'Invalid JSON.');
      }
      final idToken = body['idToken']?.toString();
      if (idToken == null || idToken.isEmpty) {
        return Response(400, body: 'Missing idToken.');
      }
      final identity = await verifyGoogleIdToken(idToken, googleClientId);
      if (identity == null) return Response.forbidden('Invalid Google token.');
      final userId = await db.upsertUser(
        googleSub: identity.sub,
        email: identity.email,
        name: identity.name,
      );
      return Response.ok(
        jsonEncode({
          'token': issueSession(userId, sessionSecret),
          'email': identity.email,
          'name': identity.name,
        }),
        headers: {'content-type': 'application/json'},
      );
    })
    ..post('/sync', (Request request) async {
      final userId = userFor(request);
      if (userId == null) return Response.forbidden('Sign in required.');
      return handleSync(db, userId, request);
    })
    ..get('/transactions', (Request request) async {
      final client = airtel;
      if (client == null) {
        return Response.notFound('Airtel proxy not configured.');
      }
      if (proxyApiKey != null &&
          request.headers['authorization'] != 'Bearer $proxyApiKey') {
        return Response.forbidden('Invalid or missing API key.');
      }
      final q = request.url.queryParameters;
      final from = q['from'];
      final to = q['to'];
      if (from == null || to == null) {
        return Response(400, body: 'Query params "from" and "to" are required.');
      }
      try {
        final result = await client.transactions(
          from: from,
          to: to,
          limit: q['limit'] ?? '100',
          offset: q['offset'] ?? '0',
        );
        return Response.ok(result, headers: {'content-type': 'application/json'});
      } catch (e) {
        stderr.writeln('transactions error: $e');
        return Response.internalServerError(body: 'Upstream error.');
      }
    });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors(corsOrigin))
      .addHandler(router.call);

  final port = int.parse(env['PORT'] ?? '8080');
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('budget_api listening on :${server.port}');
}

/// Allow the Cloudflare Pages frontend (a different origin) to call the API,
/// and answer the preflight OPTIONS the browser sends first.
Middleware _cors(String origin) {
  final headers = {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
    'Access-Control-Max-Age': '86400',
  };
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok(null, headers: headers);
      }
      final response = await innerHandler(request);
      return response.change(headers: {...response.headers, ...headers});
    };
  };
}

String _require(Map<String, String> env, String key) {
  final value = env[key];
  if (value == null || value.isEmpty) {
    stderr.writeln('Missing required environment variable: $key');
    exit(64); // EX_USAGE
  }
  return value;
}
