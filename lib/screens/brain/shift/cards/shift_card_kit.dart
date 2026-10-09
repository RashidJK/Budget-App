import 'package:flutter/material.dart';

import '../../../../theme.dart';

/// Shared chrome for the morph preview cards: a rounded surface with an
/// accent header strip, optional left edge, and a slot for badges.

class ShiftBadge {
  const ShiftBadge(this.icon, this.label, {this.caution = false});
  final IconData icon;
  final String label;
  final bool caution;
}

class ShiftShell extends StatelessWidget {
  const ShiftShell({
    super.key,
    required this.accent,
    required this.icon,
    required this.label,
    required this.child,
    this.badges = const [],
    this.edge,
  });

  final Color accent;
  final IconData icon;
  final String label;
  final Widget child;
  final List<ShiftBadge> badges;
  final Color? edge;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final card = Container(
      decoration: BoxDecoration(
        color: context.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            color: accent.withValues(alpha: dark ? 0.18 : 0.09),
            child: Row(
              children: [
                Icon(icon, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: accent,
                  ),
                ),
                const Spacer(),
                for (final b in badges) ...[
                  const SizedBox(width: 6),
                  _BadgeChip(b, accent: accent),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: child,
          ),
        ],
      ),
    );

    if (edge == null) return card;
    return Stack(
      children: [
        card,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Container(
            width: 3,
            decoration: BoxDecoration(
              color: edge,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
            ),
          ),
        ),
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip(this.badge, {required this.accent});
  final ShiftBadge badge;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = badge.caution ? context.caution : accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            badge.label,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// A small inline metadata chip (date, person, location, …).
class ShiftChip extends StatelessWidget {
  const ShiftChip(this.icon, this.text, {super.key, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white10 : const Color(0xFFF2F1F8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// Parse a "#rrggbb" string into a Color, or null.
Color? shiftHexColor(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}
