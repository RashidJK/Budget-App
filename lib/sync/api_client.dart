import 'dart:convert';

import 'api_http.dart';

/// Just the sync call, so [SyncService] can be tested against a fake.
abstract class SyncApi {
  /// Push [changes], pull everything since [since]. Returns the server's
  /// `{cursor, changes}`, or null if the call failed.
  Future<Map<String, dynamic>?> sync({
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
  Future<Map<String, dynamic>?> sync({
    required String token,
    required int since,
    required Map<String, List<Map<String, dynamic>>> changes,
  }) async {
    final res = await postJson(
      '$base/sync',
      headers: {'authorization': 'Bearer $token'},
      body: {'since': since, 'changes': changes},
    );
    if (res.status != 200) return null;
    return _decode(res.body);
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
