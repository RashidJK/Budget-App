/// Fallback for platforms that are neither dart:io nor the browser. Sync is
/// never active there, so this is unused in practice.
Future<({int status, String body})> postJson(
  String url, {
  Map<String, String>? headers,
  Object? body,
}) async => (status: 0, body: '');
