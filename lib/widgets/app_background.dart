import 'package:flutter/material.dart';

import '../theme.dart';

/// Paints the app's graded wash behind a tab body, so every screen shares one
/// continuous lit canvas rather than a flat sheet.
///
/// Wrap each tab's Scaffold body in this and set that Scaffold's
/// `backgroundColor` to transparent so the wash shows through.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: context.surfaceGradient),
      child: child,
    );
  }
}
