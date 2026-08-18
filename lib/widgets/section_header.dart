import 'package:flutter/material.dart';

import '../theme.dart';

/// The one section header used across the app — a bold title on the left, and
/// an optional right slot that is either a muted meta string (e.g. "12 days to
/// go") or a tappable "See all ›" action.
///
/// One header component means every section, on every tab, speaks in the same
/// voice instead of each hand-rolling its own Row.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.meta,
    this.actionLabel,
    this.onAction,
  });

  final String title;

  /// A quiet trailing note, shown when there's no [onAction].
  final String? meta;

  /// Trailing tappable action label (defaults to "See all"); pairs with a
  /// chevron. Ignored unless [onAction] is set.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (onAction != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Text(
                  actionLabel ?? 'See all',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: context.scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: context.scheme.primary,
                ),
              ],
            ),
          )
        else if (meta != null)
          Text(
            meta!,
            style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
          ),
      ],
    );
  }
}
