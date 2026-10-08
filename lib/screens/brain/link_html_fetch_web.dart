// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Web: the browser blocks cross-origin HTML fetches, so route the request
/// through a CORS proxy. Swap [_proxy] for your own backend endpoint (e.g. the
/// shelf server in `backend/`) to avoid sending link URLs to a third party.
/// Null on any failure.
const _proxy = 'https://api.allorigins.win/raw?url=';

Future<String?> fetchHtml(String url) async {
  try {
    final proxied = '$_proxy${Uri.encodeComponent(url)}';
    return await html.HttpRequest.getString(
      proxied,
    ).timeout(const Duration(seconds: 8));
  } catch (_) {
    return null;
  }
}
