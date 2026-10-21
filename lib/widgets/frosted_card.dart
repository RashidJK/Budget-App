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
    this.radius = 22,
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
    // A lit rim so the glass reads as a raised edge catching light, not a flat
    // fill — brighter on dark, a soft white hairline on light.
    final rim = dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.55);
    return DecoratedBox(
      // The shadow lives on an outer box so the glass clip doesn't crop it.
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: dark
                ? Colors.black.withValues(alpha: 0.30)
                : const Color(0xFF0E5A3C).withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: width,
            padding: padding,
            decoration: BoxDecoration(
              // Translucent green glass — a touch brighter at the top-left so it
              // reads as lit, sheer enough to let the blur through.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0x99243F2F), Color(0x73101E16)]
                    : const [Color(0xB3ECF6F0), Color(0x8CD6ECDE)],
              ),
              borderRadius: r,
              border: Border.all(color: rim),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
