// Browser JSON POST via XHR. onLoadEnd fires for success and HTTP errors
// alike, so we always resolve with the real status; network/CORS failures
// resolve with status 0.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

Future<({int status, String body})> postJson(
  String url, {
  Map<String, String>? headers,
  Object? body,
}) {
  final completer = Completer<({int status, String body})>();
  final request = html.HttpRequest();
  request.open('POST', url);
  request.setRequestHeader('content-type', 'application/json');
  headers?.forEach(request.setRequestHeader);
  request.onLoadEnd.listen((_) {
    if (completer.isCompleted) return;
    completer.complete((status: request.status ?? 0, body: request.responseText ?? ''));
  });
  request.onError.listen((_) {
    if (!completer.isCompleted) completer.complete((status: 0, body: ''));
  });
  request.send(body != null ? jsonEncode(body) : null);
  return completer.future;
}
