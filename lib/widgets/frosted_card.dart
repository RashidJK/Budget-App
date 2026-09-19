import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// A translucent "frosted glass" content card — a soft green-tinted fill over a
/// real backdrop blur, so the card reads as glass lit by the green wash behind
/// it rather than a flat panel. A drop-in for the solid card: same rounding and
/// footprint, so swapping it in changes only the finish.
class FrostedCard extends StatelessWidget {
  const FrostedCard({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding,
    this.width,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      // The shadow lives on an outer box so the glass clip doesn't crop it.
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: dark
                ? Colors.black.withValues(alpha: 0.30)
                : const Color(0xFF0E5A3C).withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: width,
            padding: padding,
            decoration: BoxDecoration(
              // Translucent green glass — light enough to keep dark text legible,
              // sheer enough to let the blur read.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0x8C213E2E), Color(0x73101E16)]
                    : const [Color(0xA6E9F5EE), Color(0x8CD6ECDE)],
              ),
              borderRadius: r,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
