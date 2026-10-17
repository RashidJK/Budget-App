import 'dart:io';

import 'package:shelf/shelf.dart';

/// Request guards for a public deployment: a body-size cap and a per-client
/// rate limit. Both are in-memory and per-isolate, which is all a
/// single-instance VPS needs — no Redis, no extra dependency.

/// Reject bodies larger than [maxBytes] up front, from the `Content-Length` the
/// client sends. Cheap, and it covers the normal JSON path — the `http` client
/// always sets the header — without having to buffer the stream to measure it.
Middleware limitBody(int maxBytes) {
  return (Handler inner) {
    return (Request request) async {
      final length = request.contentLength;
      if (length != null && length > maxBytes) {
        return Response(413, body: 'Payload too large.');
      }
      return inner(request);
    };
  };
}

/// A fixed-window rate limiter: at most [max] hits per [window] for each key.
///
/// Fixed windows can let through up to 2× [max] across a window boundary; for
/// an abuse guard (not billing) that's an acceptable trade for O(1) memory per
/// key and trivially testable behaviour.
class FixedWindowLimiter {
  FixedWindowLimiter({required this.max, required this.window});

  final int max;
  final Duration window;
  final Map<String, _Window> _windows = {};

  /// Records a hit for [key] at [now] and reports whether it's allowed. [now] is
  /// passed in so tests can drive time without waiting.
  RateDecision hit(String key, DateTime now) {
    final current = _windows[key];
    if (current == null || now.difference(current.start) >= window) {
      _windows[key] = _Window(start: now, count: 1);
      return RateDecision(allowed: true, remaining: max - 1, resetIn: window);
    }
    current.count++;
    final resetIn = window - now.difference(current.start);
    final remaining = (max - current.count).clamp(0, max);
    return RateDecision(
      allowed: current.count <= max,
      remaining: remaining,
      resetIn: resetIn,
    );
  }

  /// Forget windows that have fully elapsed, so the map tracks only active
  /// clients rather than every key ever seen.
  void sweep(DateTime now) {
    _windows.removeWhere((_, w) => now.difference(w.start) >= window);
  }

  int get trackedKeys => _windows.length;
}

class _Window {
  _Window({required this.start, required this.count});
  final DateTime start;
  int count;
}

/// The result of recording a hit: whether to serve it, how many remain in the
/// window, and how long until the window resets.
class RateDecision {
  const RateDecision({
    required this.allowed,
    required this.remaining,
    required this.resetIn,
  });

  final bool allowed;
  final int remaining;
  final Duration resetIn;
}

/// A best-effort client identity behind Cloudflare + nginx: the real visitor's
/// IP when a trusted proxy forwarded it, else the socket peer. Good enough to
/// bucket requests — not an authorization signal, and spoofable if the server
/// is ever exposed without the proxy in front.
String clientKey(Request request) {
  final cfIp = request.headers['cf-connecting-ip'];
  if (cfIp != null && cfIp.trim().isNotEmpty) return cfIp.trim();
  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.trim().isNotEmpty) {
    return forwarded.split(',').first.trim();
  }
  final conn = request.context['shelf.io.connection_info'];
  if (conn is HttpConnectionInfo) return conn.remoteAddress.address;
  return 'unknown';
}

/// Turn away a client that's over its [limiter] budget with a 429 and a
/// `Retry-After`. Preflight (OPTIONS) is never counted — the browser sends it
/// automatically and it carries no work.
Middleware rateLimit(FixedWindowLimiter limiter, {DateTime Function()? clock}) {
  final now = clock ?? DateTime.now;
  return (Handler inner) {
    return (Request request) async {
      if (request.method == 'OPTIONS') return inner(request);
      final decision = limiter.hit(clientKey(request), now());
      if (!decision.allowed) {
        final retryAfter = decision.resetIn.inSeconds.clamp(1, 3600);
        return Response(
          429,
          body: 'Too many requests.',
          headers: {'Retry-After': '$retryAfter'},
        );
      }
      return inner(request);
    };
  };
}
