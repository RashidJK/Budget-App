import 'dart:convert';

import 'api_http.dart';

/// The outcome of a sync call, so the caller can tell an expired session apart
/// from a transient (offline/server) failure.
sealed class SyncResult {
  const SyncResult();
}

/// Success — the server's `{cursor, changes}`.
class SyncOk extends SyncResult {
  const SyncOk(this.data);
  final Map<String, dynamic> data;
}

/// The session is no longer valid (401/403) — re-authenticate.
class SyncAuthExpired extends SyncResult {
  const SyncAuthExpired();
}

/// Network, server or parse failure — transient; keep the session and retry.
class SyncFailed extends SyncResult {
  const SyncFailed();
}

/// Just the sync call, so [SyncService] can be tested against a fake.
abstract class SyncApi {
  /// Push [changes], pull everything since [since].
  Future<SyncResult> sync({
    required String token,
    required int since,
    required Map<String, List<Map<String, dynamic>>> changes,
  });
}

/// Talks to the Budget/Spaces API.
class ApiClient implements SyncApi {
  ApiClient(this.base);

  /// e.g. https://api.yourdomain.com — no trailing slash.
  final String base;

  /// Exchange a Google ID token for our session. Returns `{token, email,
  /// name}`, or null on failure.
  Future<Map<String, dynamic>?> authGoogle(String idToken) async {
    final res = await postJson('$base/auth/google', body: {'idToken': idToken});
    if (res.status != 200) return null;
    return _decode(res.body);
  }

  @override
  Future<SyncResult> sync({
    required String token,
    required int since,
    required Map<String, List<Map<String, dynamic>>> changes,
  }) async {
    final res = await postJson(
      '$base/sync',
      headers: {'authorization': 'Bearer $token'},
      body: {'since': since, 'changes': changes},
    );
    if (res.status == 401 || res.status == 403) return const SyncAuthExpired();
    if (res.status != 200) return const SyncFailed();
    final data = _decode(res.body);
    return data == null ? const SyncFailed() : SyncOk(data);
  }

  Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
