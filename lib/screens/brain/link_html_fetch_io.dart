import 'dart:convert';
import 'dart:io';

/// Mobile/desktop: fetch the page directly and return the first slice of HTML
/// (the metadata lives in the `<head>`). Null on any failure.
Future<String?> fetchHtml(String url) async {
  final Uri uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return null;
  }

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..userAgent = 'Mozilla/5.0 (compatible; SecondBrain/1.0; +link-preview)';
  try {
    final request = await client.getUrl(uri);
    request.followRedirects = true;
    final response = await request.close().timeout(
      const Duration(seconds: 6),
    );
    if (response.statusCode >= 400) return null;

    final buffer = StringBuffer();
    await for (final chunk
        in response.transform(const Utf8Decoder(allowMalformed: true))) {
      buffer.write(chunk);
      if (buffer.length > 60000 || buffer.toString().contains('</head>')) {
        break;
      }
    }
    return buffer.toString();
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
