// Web: mirror the active Space into the URL so Back/Forward, refresh and
// shareable links work. Uses the hash fragment (e.g. /#/brain) via the History
// API — hash routing needs no server rewrite, so a hard refresh works on any
// static host, and it stays out of the way of Flutter's own router.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

String _hashPath() {
  final h = html.window.location.hash;
  var p = h.startsWith('#') ? h.substring(1) : h;
  if (p.isEmpty) return '/';
  if (!p.startsWith('/')) p = '/$p';
  return p;
}

/// The path the page was opened at (from the hash), or null if there's none.
String? initialRoutePath() {
  final p = _hashPath();
  return p == '/' ? null : p;
}

void pushRoutePath(String path, {bool replace = false}) {
  final url = '#$path';
  if (replace) {
    html.window.history.replaceState(null, '', url);
  } else {
    html.window.history.pushState(null, '', url);
  }
}

/// Fires on browser Back/Forward with the path now in the address bar.
void listenRoutePop(void Function(String path) onPop) {
  html.window.onPopState.listen((_) => onPop(_hashPath()));
}
