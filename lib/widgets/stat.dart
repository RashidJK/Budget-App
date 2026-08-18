import 'package:flutter/material.dart';

import '../services/format.dart';
import '../theme.dart';

/// A currency figure that counts smoothly to its new value.
///
/// Planner inputs recalculate on every keystroke, so a hard number swap would
/// flicker. Tweening gives the user something to follow and makes the size of
/// a change legible — a small edit crawls, a big one sweeps.
class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney({
    super.key,
    required this.value,
    this.style,
    this.compact = false,
    this.duration = const Duration(milliseconds: 420),
  });

  final double value;
  final TextStyle? style;

  /// Abbreviate to `TSh 1.8M`. Long-range projections reach nine digits, which
  /// would otherwise overflow a phone-width tile.
  final bool compact;

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.isFinite ? value : 0),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return Text(
          compact ? Money.compact(animated) : Money.format(animated),
          // Tabular (fixed-width) digits so the count-up doesn't wobble as
          // digit widths change frame to frame, and columns of figures align.
          style: (style ?? const TextStyle()).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

/// One headline figure with its label — the Daily / Weekly / Monthly / Yearly
/// tiles, and the equivalents on every other planner screen.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.accent,
    this.emphasis = false,
    this.compact = false,
    this.footnote,
  });

  final String label;
  final double value;

  /// Optional identity colour. Applied to the label rule, never to the number
  /// itself — figures stay in text ink so they keep full contrast.
  final Color? accent;

  /// Renders larger, for the figure the screen is really about.
  final bool emphasis;

  final bool compact;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = accent ?? context.scheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: context.muted,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Scales the figure down rather than abbreviating it. A yearly total
          // is exactly the number the user came for, so "TSh 1,825,000" stays
          // legible in full instead of collapsing to "TSh 1.8M" — the spoken
          // form belongs in the insight sentence, not the tile.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(
              value: value,
              compact: compact,
              style:
                  (emphasis
                          ? theme.textTheme.headlineMedium
                          : theme.textTheme.titleLarge)
                      ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Text(
              footnote!,
              style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The four-up Daily / Weekly / Monthly / Yearly grid.
///
/// Two columns rather than four across: on a phone, four figures in a row
/// would each be too narrow to hold seven digits.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.tiles});

  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 620 ? 4 : 2;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

/// A plain-language takeaway under the numbers.
///
/// The spec's core idea: a figure like "TSh 1,825,000" is easier to dismiss
/// than the sentence "you will spend about TSh 1.8 million a year on lunch".
class InsightCard extends StatelessWidget {
  const InsightCard({
    super.key,
    required this.message,
    this.icon = Icons.lightbulb_outline_rounded,
    this.tone = InsightTone.neutral,
  });

  final String message;
  final IconData icon;
  final InsightTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      InsightTone.good => context.good,
      InsightTone.warning => context.warn,
      InsightTone.neutral => context.scheme.primary,
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: context.isDark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: context.scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum InsightTone { neutral, good, warning }
