import 'dart:convert';
import 'dart:io';

/// Mobile/desktop JSON POST via dart:io. Never throws — a failed request
/// returns status 0.
Future<({int status, String body})> postJson(
  String url, {
  Map<String, String>? headers,
  Object? body,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.set('content-type', 'application/json');
    headers?.forEach(request.headers.set);
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 25));
    final text = await response
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    return (status: response.statusCode, body: text);
  } catch (_) {
    return (status: 0, body: '');
  } finally {
    client.close(force: true);
  }
}
