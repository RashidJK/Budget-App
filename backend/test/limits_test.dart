import 'dart:convert';

import 'package:budget_api/limits.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  Request post(String body, {Map<String, String>? headers}) => Request(
        'POST',
        Uri.parse('http://localhost/sync'),
        body: body,
        headers: headers,
      );

  Future<Response> run(Middleware middleware, Request request) async {
    final handler = middleware((_) async => Response.ok('ok'));
    return await handler(request);
  }

  group('limitBody', () {
    test('passes a body within the cap', () async {
      final res = await run(limitBody(1000), post('{"a":1}'));
      expect(res.statusCode, 200);
    });

    test('rejects a body over the cap with 413', () async {
      final res = await run(limitBody(4), post('way too long'));
      expect(res.statusCode, 413);
    });

    test('passes when no length is declared (cap is best-effort)', () async {
      final streamed = Request(
        'POST',
        Uri.parse('http://localhost/sync'),
        body: Stream.fromIterable([utf8.encode('hello')]),
      );
      expect(streamed.contentLength, isNull);
      final res = await run(limitBody(1), streamed);
      expect(res.statusCode, 200);
    });
  });

  group('FixedWindowLimiter', () {
    final t = DateTime(2026, 1, 1, 12);

    test('allows up to max, then blocks within the window', () {
      final limiter =
          FixedWindowLimiter(max: 3, window: const Duration(seconds: 60));
      expect(limiter.hit('a', t).allowed, isTrue);
      expect(limiter.hit('a', t).allowed, isTrue);
      expect(limiter.hit('a', t).allowed, isTrue);
      final blocked = limiter.hit('a', t);
      expect(blocked.allowed, isFalse);
      expect(blocked.remaining, 0);
    });

    test('keeps a separate budget per key', () {
      final limiter =
          FixedWindowLimiter(max: 1, window: const Duration(seconds: 60));
      expect(limiter.hit('a', t).allowed, isTrue);
      expect(limiter.hit('b', t).allowed, isTrue); // a different client
      expect(limiter.hit('a', t).allowed, isFalse);
    });

    test('resets once the window elapses', () {
      final limiter =
          FixedWindowLimiter(max: 1, window: const Duration(seconds: 60));
      expect(limiter.hit('a', t).allowed, isTrue);
      expect(limiter.hit('a', t).allowed, isFalse);
      final later = t.add(const Duration(seconds: 61));
      expect(limiter.hit('a', later).allowed, isTrue); // a fresh window
    });

    test('sweep forgets fully-elapsed windows', () {
      final limiter =
          FixedWindowLimiter(max: 5, window: const Duration(seconds: 60));
      limiter.hit('a', t);
      expect(limiter.trackedKeys, 1);
      limiter.sweep(t.add(const Duration(seconds: 61)));
      expect(limiter.trackedKeys, 0);
    });
  });

  group('clientKey', () {
    test('prefers CF-Connecting-IP', () {
      final r = post('{}', headers: {
        'cf-connecting-ip': '9.9.9.9',
        'x-forwarded-for': '1.1.1.1, 2.2.2.2',
      });
      expect(clientKey(r), '9.9.9.9');
    });

    test('falls back to the first X-Forwarded-For hop', () {
      final r = post('{}', headers: {'x-forwarded-for': '1.1.1.1, 2.2.2.2'});
      expect(clientKey(r), '1.1.1.1');
    });

    test('is "unknown" with no proxy headers and no socket info', () {
      expect(clientKey(post('{}')), 'unknown');
    });
  });

  group('rateLimit middleware', () {
    final clock = DateTime(2026, 1, 1, 12);

    test('returns 429 with Retry-After once over budget', () async {
      final limiter =
          FixedWindowLimiter(max: 1, window: const Duration(seconds: 30));
      final mw = rateLimit(limiter, clock: () => clock);
      final headers = {'cf-connecting-ip': '5.5.5.5'};

      expect((await run(mw, post('{}', headers: headers))).statusCode, 200);
      final second = await run(mw, post('{}', headers: headers));
      expect(second.statusCode, 429);
      expect(second.headers['retry-after'], isNotNull);
    });

    test('never counts preflight OPTIONS', () async {
      final limiter =
          FixedWindowLimiter(max: 1, window: const Duration(seconds: 30));
      final mw = rateLimit(limiter, clock: () => clock);
      final options = Request(
        'OPTIONS',
        Uri.parse('http://localhost/sync'),
        headers: {'cf-connecting-ip': '5.5.5.5'},
      );

      await run(mw, options);
      await run(mw, options);
      expect(limiter.trackedKeys, 0); // preflight left no trace
    });
  });
}
