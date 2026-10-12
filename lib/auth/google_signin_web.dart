// Renders the official Google Identity Services button inside the Flutter tree
// via a platform view, and forwards the ID token from its callback. Uses
// dart:js_util (+ dart:html) rather than package:web so no dependency is added.
// dart:js_util still ships with the web compiler (the web build uses it) but
// the analyzer no longer lists it, so the URI check is a false positive here.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, uri_does_not_exist
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

var _seq = 0;

Widget googleSignInButton({
  required void Function(String idToken) onCredential,
  required String clientId,
}) => _GoogleButton(onCredential: onCredential, clientId: clientId);

class _GoogleButton extends StatefulWidget {
  const _GoogleButton({required this.onCredential, required this.clientId});

  final void Function(String idToken) onCredential;
  final String clientId;

  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton> {
  late final String _viewType;
  late final html.DivElement _host;

  @override
  void initState() {
    super.initState();
    _viewType = 'gsi-button-${_seq++}';
    _host = html.DivElement()
      ..style.width = '240px'
      ..style.height = '44px';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _host);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  /// GIS loads from a <script defer>, so it may not be on `window` yet — retry
  /// a few times before giving up.
  void _init([int attempt = 0]) {
    final google = js_util.getProperty<Object?>(html.window, 'google');
    if (google == null) {
      if (attempt < 20) {
        Timer(const Duration(milliseconds: 250), () => _init(attempt + 1));
      }
      return;
    }
    final accounts = js_util.getProperty<Object>(google, 'accounts');
    final id = js_util.getProperty<Object>(accounts, 'id');

    final config = js_util.newObject<Object>();
    js_util.setProperty(config, 'client_id', widget.clientId);
    js_util.setProperty(
      config,
      'callback',
      js_util.allowInterop((Object response) {
        final credential = js_util.getProperty<Object?>(response, 'credential');
        if (credential is String && credential.isNotEmpty) {
          widget.onCredential(credential);
        }
      }),
    );
    js_util.callMethod<void>(id, 'initialize', [config]);

    final options = js_util.newObject<Object>();
    js_util.setProperty(options, 'theme', 'outline');
    js_util.setProperty(options, 'size', 'large');
    js_util.setProperty(options, 'type', 'standard');
    js_util.setProperty(options, 'shape', 'pill');
    js_util.callMethod<void>(id, 'renderButton', [_host, options]);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 44,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
