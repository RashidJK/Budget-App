import 'dart:convert';

import 'package:budget_api/auth.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const secret = 'test-secret-test-secret-test-secret-0123';

String b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

// Signs a token the way Focus's server does (jsonwebtoken, HS256).
String sign(Map<String, dynamic> payload, {String key = secret, String alg = 'HS256'}) {
  final header = b64u(utf8.encode(jsonEncode({'alg': alg, 'typ': 'JWT'})));
  final body = b64u(utf8.encode(jsonEncode(payload)));
  final sig = Hmac(sha256, utf8.encode(key)).convert(utf8.encode('$header.$body')).bytes;
  return '$header.$body.${b64u(sig)}';
}

int inSeconds(int s) => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + s;

void main() {
  group('verifyFocusLink', () {
    test('accepts a fresh token for budget, lower-casing the email', () {
      final t = sign({'email': 'Owner@Example.com', 'app': 'budget', 'exp': inSeconds(300)});
      expect(verifyFocusLink(t, secret), 'owner@example.com');
    });

    test('rejects an expired token', () {
      final t = sign({'email': 'owner@example.com', 'app': 'budget', 'exp': inSeconds(-1)});
      expect(verifyFocusLink(t, secret), isNull);
    });

    test('rejects a token signed with another secret', () {
      final t = sign({'email': 'owner@example.com', 'app': 'budget', 'exp': inSeconds(300)}, key: 'another-secret-another-secret-0123456');
      expect(verifyFocusLink(t, secret), isNull);
    });

    test('rejects a token for another app', () {
      final t = sign({'email': 'owner@example.com', 'app': 'notes', 'exp': inSeconds(300)});
      expect(verifyFocusLink(t, secret), isNull);
    });

    test('rejects alg none and garbage', () {
      final t = sign({'email': 'owner@example.com', 'app': 'budget', 'exp': inSeconds(300)}, alg: 'none');
      expect(verifyFocusLink(t, secret), isNull);
      expect(verifyFocusLink('not.a.token', secret), isNull);
      expect(verifyFocusLink('', secret), isNull);
    });

    test('rejects a tampered payload', () {
      final t = sign({'email': 'owner@example.com', 'app': 'budget', 'exp': inSeconds(300)});
      final parts = t.split('.');
      final forged = b64u(utf8.encode(jsonEncode({'email': 'someone@else.com', 'app': 'budget', 'exp': inSeconds(300)})));
      expect(verifyFocusLink('${parts[0]}.$forged.${parts[2]}', secret), isNull);
    });
  });

  test('parseEmailAliases', () {
    expect(parseEmailAliases('A@x.com=b@Y.com, c@x.com = d@y.com'), {'a@x.com': 'b@y.com', 'c@x.com': 'd@y.com'});
    expect(parseEmailAliases(null), isEmpty);
  });
}
