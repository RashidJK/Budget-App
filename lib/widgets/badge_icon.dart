import 'package:flutter/material.dart';

import '../theme.dart';

/// The size steps a [BadgeIcon] comes in.
enum BadgeSize { sm, md, lg }

/// The app's signature tinted rounded-square "coin" — one component for every
/// category / insight / snapshot icon, so a badge tweak is a single-file edit
/// and every badge reads as the same designed chip rather than a hand-rolled
/// container.
///
/// A faint vertical gradient tint gives it a little enamel depth; the glyph
/// stays single-tone accent for contrast. The hero's circular quick actions
/// are a deliberately different treatment and don't use this.
class BadgeIcon extends StatelessWidget {
  const BadgeIcon({
    super.key,
    required this.icon,
    required this.accent,
    this.size = BadgeSize.md,
  });

  final IconData icon;
  final Color accent;
  final BadgeSize size;

  double get _box => switch (size) {
    BadgeSize.sm => 36,
    BadgeSize.md => 40,
    BadgeSize.lg => 48,
  };

  double get _radius => switch (size) {
    BadgeSize.sm => 11,
    BadgeSize.md => 12,
    BadgeSize.lg => 14,
  };

  double get _glyph => switch (size) {
    BadgeSize.sm => 18,
    BadgeSize.md => 20,
    BadgeSize.lg => 24,
  };

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Container(
      width: _box,
      height: _box,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: dark ? 0.30 : 0.16),
            accent.withValues(alpha: dark ? 0.20 : 0.09),
          ],
        ),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Icon(icon, size: _glyph, color: accent),
    );
  }
}
