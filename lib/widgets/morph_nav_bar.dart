import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../theme.dart';

/// One destination in a [MorphNavBar].
class MorphNavItem {
  const MorphNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// The app's frosted-glass bottom bar — a raised universal "+" docked in the
/// middle, flanked by destinations. It's context-aware: different screens hand
/// it different [items], so the bar *morphs* as you move through the app while
/// the centre "+" stays constant (capture is always one tap away).
class MorphNavBar extends StatelessWidget {
  const MorphNavBar({
    super.key,
    required this.items,
    required this.activeIndex,
    required this.onSelect,
    required this.onAdd,
  });

  /// An even number of destinations; the "+" docks between the two halves.
  final List<MorphNavItem> items;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final fill = dark
        ? const Color(0xFF232322).withValues(alpha: 0.62)
        : Colors.white.withValues(alpha: 0.7);

    final half = items.length ~/ 2;
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i == half) children.add(_AddButton(onTap: onAdd));
      children.add(
        _MorphNavItemView(
          data: items[i],
          selected: i == activeIndex,
          onTap: () => onSelect(i),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.3 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: 66,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: dark ? 0.14 : 0.6),
                  ),
                ),
                child: Row(children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MorphNavItemView extends StatelessWidget {
  const _MorphNavItemView({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final MorphNavItem data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.scheme.primary : context.muted;

    return Expanded(
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: selected,
          label: data.label,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            borderRadius: BorderRadius.circular(16),
            child: ExcludeSemantics(
              // Cross-fade the glyph/label so a context change reads as the bar
              // morphing rather than snapping.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Column(
                  key: ValueKey('${data.label}-$selected'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      selected ? data.activeIcon : data.icon,
                      size: 23,
                      color: color,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The raised centre "+" — always the universal command action, green from the
/// brand mark.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: MergeSemantics(
          child: Semantics(
            button: true,
            label: 'Add or capture',
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.brandGreen.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                child: Ink(
                  decoration: const BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                  ),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onTap();
                    },
                    borderRadius: BorderRadius.circular(18),
                    splashColor: Colors.white.withValues(alpha: 0.25),
                    child: const SizedBox(
                      width: 52,
                      height: 52,
                      child: Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
