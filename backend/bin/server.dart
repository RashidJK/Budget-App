import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:budget_api/airtel_client.dart';
import 'package:budget_api/auth.dart';
import 'package:budget_api/db.dart';
import 'package:budget_api/limits.dart';
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
  final maxBodyBytes = int.tryParse(env['MAX_BODY_BYTES'] ?? '') ?? 5000000;
  final rateMax = int.tryParse(env['RATE_LIMIT_MAX'] ?? '') ?? 300;
  final rateWindow = Duration(
    seconds: int.tryParse(env['RATE_LIMIT_WINDOW_SECONDS'] ?? '') ?? 60,
  );
  final tombstoneTtl = Duration(
    days: int.tryParse(env['TOMBSTONE_TTL_DAYS'] ?? '') ?? 90,
  );

  // Postgres may still be booting when we start (docker compose); retry briefly.
  late final Db db;
  for (var attempt = 1;; attempt++) {
    try {
      db = await Db.open(dbUrl);
      break;
    } catch (e) {
      if (attempt >= 15) rethrow;
      stderr.writeln('DB not ready ($e); retrying in 2s…');
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  // Keep the document table from accumulating ancient tombstones. Run once now,
  // then daily; failures are logged, never fatal.
  Future<void> prune() async {
    try {
      final removed = await db.pruneTombstones(tombstoneTtl);
      if (removed > 0) {
        stdout.writeln(
            'pruned $removed tombstone(s) older than ${tombstoneTtl.inDays}d');
      }
    } catch (e) {
      stderr.writeln('tombstone prune failed: $e');
    }
  }

  await prune();
  Timer.periodic(const Duration(hours: 24), (_) => prune());

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
        return Response(400,
            body: 'Query params "from" and "to" are required.');
      }
      try {
        final result = await client.transactions(
          from: from,
          to: to,
          limit: q['limit'] ?? '100',
          offset: q['offset'] ?? '0',
        );
        return Response.ok(result,
            headers: {'content-type': 'application/json'});
      } catch (e) {
        stderr.writeln('transactions error: $e');
        return Response.internalServerError(body: 'Upstream error.');
      }
    });

  // One shared limiter for the process; sweep expired windows periodically so
  // the map tracks only active clients.
  final limiter = FixedWindowLimiter(max: rateMax, window: rateWindow);
  Timer.periodic(rateWindow, (_) => limiter.sweep(DateTime.now()));

  // CORS is outermost so even a 413/429 carries the headers the browser needs
  // to read it; the limits sit just inside it, before any real work.
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors(corsOrigin))
      .addMiddleware(limitBody(maxBodyBytes))
      .addMiddleware(rateLimit(limiter))
      .addHandler(router.call);

  final port = int.parse(env['PORT'] ?? '8080');
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('budget_api listening on :${server.port}');
}

/// Allow the configured frontend origin(s) to call the API, and answer the
/// preflight OPTIONS the browser sends first. CORS_ORIGIN may be a single
/// origin, a comma-separated list (e.g. the Pages site + localhost for dev),
/// or `*`. A browser needs the response to echo its exact Origin, so we match
/// the request's Origin against the allowlist.
Middleware _cors(String originConfig) {
  final allowed = originConfig
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  final allowAll = allowed.contains('*');

  Map<String, String> headersFor(Request request) {
    final requestOrigin = request.headers['origin'];
    final allow = allowAll
        ? '*'
        : (requestOrigin != null && allowed.contains(requestOrigin)
            ? requestOrigin
            : (allowed.isEmpty ? '*' : allowed.first));
    return {
      'Access-Control-Allow-Origin': allow,
      'Vary': 'Origin',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
      'Access-Control-Max-Age': '86400',
    };
  }

  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok(null, headers: headersFor(request));
      }
      final response = await innerHandler(request);
      return response
          .change(headers: {...response.headers, ...headersFor(request)});
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
