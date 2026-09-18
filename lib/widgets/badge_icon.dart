import 'package:flutter/material.dart';

/// The size steps a [BadgeIcon] comes in.
enum BadgeSize { sm, md, lg }

/// A category / insight / snapshot icon, drawn as a single accent-tone glyph —
/// one component for every such icon, so a tweak is a single-file edit and every
/// one reads the same. It keeps a fixed footprint per size so rows and cards
/// stay aligned now that the glyph is background-free (was a tinted "coin"). The
/// hero's circular quick actions are a deliberately different treatment and
/// don't use this.
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

  // A touch larger than the old glyph, since a bare icon needs to fill the
  // footprint the tinted square used to hold.
  double get _glyph => switch (size) {
    BadgeSize.sm => 22,
    BadgeSize.md => 26,
    BadgeSize.lg => 30,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _box,
      height: _box,
      child: Center(child: Icon(icon, size: _glyph, color: accent)),
    );
  }
}
