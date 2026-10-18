import 'package:budget/services/link_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// The URL normalisation behind "open link": a bare domain gets https, a real
/// scheme is left alone, and junk returns null (so the caller falls back to
/// copying rather than launching nonsense).
void main() {
  test('a bare domain gains https', () {
    expect(normaliseLinkUri('vercel.com')?.toString(), 'https://vercel.com');
    expect(
      normaliseLinkUri('vercel.com/blog')?.toString(),
      'https://vercel.com/blog',
    );
  });

  test('an explicit scheme is preserved', () {
    expect(
      normaliseLinkUri('http://example.com')?.toString(),
      'http://example.com',
    );
    expect(
      normaliseLinkUri('https://a.test/x?y=1')?.toString(),
      'https://a.test/x?y=1',
    );
    expect(normaliseLinkUri('mailto:a@b.com')?.toString(), 'mailto:a@b.com');
  });

  test('surrounding whitespace is trimmed', () {
    expect(
      normaliseLinkUri('  vercel.com  ')?.toString(),
      'https://vercel.com',
    );
  });

  test('empty input is null', () {
    expect(normaliseLinkUri(''), isNull);
    expect(normaliseLinkUri('   '), isNull);
  });
}
