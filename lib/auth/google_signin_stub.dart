import 'package:flutter/widgets.dart';

/// Non-web: sign-in isn't wired, so there's no button. The gate only shows one
/// on web, so this is never actually displayed.
Widget googleSignInButton({
  required void Function(String idToken) onCredential,
  required String clientId,
}) => const SizedBox.shrink();
