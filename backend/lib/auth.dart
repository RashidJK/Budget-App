import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// A verified Google identity.
class GoogleIdentity {
  GoogleIdentity(this.sub, this.email, this.name);
  final String sub; // stable Google account id
  final String? email;
  final String? name;
}

/// Verify a Google ID token by asking Google's tokeninfo endpoint (Google does
/// the RSA signature check), then confirm it was minted for *our* app. Returns
/// null on anything suspicious. Only called at sign-in, so the round-trip is
/// fine. [client] is injectable for tests.
Future<GoogleIdentity?> verifyGoogleIdToken(
  String idToken,
  String clientId, {
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final res = await c.get(
      Uri.parse('https://oauth2.googleapis.com/tokeninfo?id_token=$idToken'),
    );
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['aud']?.toString() != clientId) return null; // different app
    final exp = int.tryParse(data['exp']?.toString() ?? '');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (exp == null || now >= exp) return null;
    final sub = data['sub']?.toString();
    if (sub == null || sub.isEmpty) return null;
    return GoogleIdentity(sub, data['email']?.toString(), data['name']?.toString());
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

// --- Session tokens: a minimal HS256 JWT signed with our own secret ----------

String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

List<int> _b64uDecode(String s) {
  final pad = (4 - s.length % 4) % 4;
  return base64Url.decode(s + ('=' * pad));
}

/// Mint a signed session token carrying the user id.
String issueSession(
  String userId,
  String secret, {
  Duration ttl = const Duration(days: 30),
}) {
  final header = _b64u(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
  final exp = DateTime.now().toUtc().add(ttl).millisecondsSinceEpoch ~/ 1000;
  final payload = _b64u(utf8.encode(jsonEncode({'sub': userId, 'exp': exp})));
  final signingInput = '$header.$payload';
  final sig = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(signingInput)).bytes;
  return '$signingInput.${_b64u(sig)}';
}

/// Return the user id if [token] is a valid, unexpired session, else null.
String? verifySession(String token, String secret) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  final signingInput = '${parts[0]}.${parts[1]}';
  final expected = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(signingInput)).bytes;
  if (!_constantTimeEquals(expected, _b64uDecode(parts[2]))) return null;
  try {
    final payload = jsonDecode(utf8.decode(_b64uDecode(parts[1]))) as Map<String, dynamic>;
    final exp = int.tryParse(payload['exp']?.toString() ?? '');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (exp == null || now >= exp) return null;
    return payload['sub']?.toString();
  } catch (_) {
    return null;
  }
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

// --- Focus link tokens --------------------------------------------------------
//
// Focus (the desktop app) can open this product as one of its private Spaces.
// For an account it allows in, Focus's server signs a five-minute HS256 token
// with a secret the two servers share (FOCUS_LINK_SECRET here,
// BUDGET_LINK_SECRET there): {"email": ..., "app": "budget", "exp": ...}.
// POST /auth/focus trades it for one of our sessions, so Focus never needs
// Google sign-in and its own tokens never reach this server.

/// The email a valid, unexpired Focus link token names, else null.
String? verifyFocusLink(String token, String secret) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final header = jsonDecode(utf8.decode(_b64uDecode(parts[0]))) as Map<String, dynamic>;
    if (header['alg'] != 'HS256') return null;
    final signingInput = '${parts[0]}.${parts[1]}';
    final expected = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(signingInput)).bytes;
    if (!_constantTimeEquals(expected, _b64uDecode(parts[2]))) return null;
    final payload = jsonDecode(utf8.decode(_b64uDecode(parts[1]))) as Map<String, dynamic>;
    final exp = int.tryParse(payload['exp']?.toString() ?? '');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (exp == null || now >= exp) return null;
    if (payload['app'] != 'budget') return null;
    final email = payload['email']?.toString().trim().toLowerCase();
    return (email == null || email.isEmpty) ? null : email;
  } catch (_) {
    return null;
  }
}

/// `FOCUS_EMAIL_ALIASES`: "focus@x.com=google@y.com,…", for an owner whose
/// Focus account uses a different email from the Google account they sign in
/// to Budget with.
Map<String, String> parseEmailAliases(String? raw) => {
      for (final pair in (raw ?? '').split(','))
        if (pair.contains('='))
          pair.split('=')[0].trim().toLowerCase(): pair.split('=')[1].trim().toLowerCase(),
    };
