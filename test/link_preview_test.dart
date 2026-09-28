import 'package:budget/screens/brain/link_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pulls og:title and an absolute og:image', () {
    const html = '''
      <html><head>
        <meta property="og:title" content="Local-first software &amp; you">
        <meta property="og:image" content="/cover.png">
        <title>Ignored fallback</title>
      </head></html>''';
    final data = LinkPreview.parse(
      html,
      base: Uri.parse('https://example.com/article'),
    );
    expect(data.title, 'Local-first software & you');
    expect(data.image, 'https://example.com/cover.png');
  });

  test('handles content-before-property attribute order', () {
    const html =
        '<meta content="https://x.com/a.jpg" property="og:image">';
    final data = LinkPreview.parse(html);
    expect(data.image, 'https://x.com/a.jpg');
  });

  test('falls back to the <title> tag when there is no og:title', () {
    const html = '<html><head><title>  Just a Title  </title></head></html>';
    final data = LinkPreview.parse(html);
    expect(data.title, 'Just a Title');
    expect(data.image, isNull);
  });

  test('empty when nothing is present', () {
    expect(LinkPreview.parse('<html></html>').isEmpty, isTrue);
  });
}
