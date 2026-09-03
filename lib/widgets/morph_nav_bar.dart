import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../theme.dart';

/// One destination in a [MorphNavBar]'s island.
class MorphNavItem {
  const MorphNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.accent,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// The colour the tab wears when selected. Defaults to the scheme primary.
  final Color? accent;
}

/// One choice in the "+" button's pop-up menu — a quick action that rises above
/// the bar (mirrors the status picker in the reference).
class MorphAction {
  const MorphAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;
}

/// The app's bottom navigation, in two floating islands:
///
///   ┌ destinations ─────────┐   ╭───╮
///   │ ▣  ▤   ◐   ▥ │        │ + │
///   └───────────────────────┘   ╰───╯
///
/// The left island holds the destinations; only the *selected* one expands to
/// show its label, the rest sit as bare icons, so the bar reads at a glance and
/// re-flows as you move. The right island is the universal "+", always one tap
/// from capture — press it and a small menu of actions rises above the bar.
///
/// It's context-aware: each screen hands it different [items], so the islands
/// *morph* as you move deeper (e.g. into an account) while the "+" stays put.
class MorphNavBar extends StatefulWidget {
  const MorphNavBar({
    super.key,
    required this.items,
    required this.activeIndex,
    required this.onSelect,
    required this.actions,
  });

  final List<MorphNavItem> items;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  /// The actions offered by the "+" menu. Capture-first: Add, Income, Transfer…
  final List<MorphAction> actions;

  @override
  State<MorphNavBar> createState() => _MorphNavBarState();
}

class _MorphNavBarState extends State<MorphNavBar> {
  bool _menuOpen = false;

  Future<void> _openMenu() async {
    HapticFeedback.lightImpact();
    setState(() => _menuOpen = true);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Quick actions',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => _QuickActionMenu(actions: widget.actions),
      transitionBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            alignment: Alignment.bottomRight,
            scale: Tween(begin: 0.9, end: 1.0).animate(curved),
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.1),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
    if (mounted) setState(() => _menuOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: _DestinationIsland(
                items: widget.items,
                activeIndex: widget.activeIndex,
                onSelect: widget.onSelect,
              ),
            ),
            const SizedBox(width: 12),
            _AddButton(open: _menuOpen, onTap: _openMenu),
          ],
        ),
      ),
    );
  }
}

/// The left island — a frosted pill of destinations, active one expanded.
class _DestinationIsland extends StatelessWidget {
  const _DestinationIsland({
    required this.items,
    required this.activeIndex,
    required this.onSelect,
  });

  final List<MorphNavItem> items;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final fill = dark
        ? const Color(0xFF232322).withValues(alpha: 0.62)
        : Colors.white.withValues(alpha: 0.72);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? 0.14 : 0.6),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < items.length; i++)
                  _MorphTab(
                    data: items[i],
                    selected: i == activeIndex,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One destination. Collapsed it's a bare icon; selected it grows a coloured
/// pill and reveals its label.
class _MorphTab extends StatelessWidget {
  const _MorphTab({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final MorphNavItem data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = data.accent ?? context.scheme.primary;
    final color = selected ? accent : context.muted;

    return Semantics(
      button: true,
      selected: selected,
      label: data.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        // The outer Semantics already carries the label + selected state; hide
        // the inner icon/label so the tab is a single accessible node.
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 14 : 11,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: context.isDark ? 0.26 : 0.13)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? data.activeIcon : data.icon,
                  size: 22,
                  color: color,
                ),
                // The label reveals only when selected, animating pill width.
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: selected
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 96),
                            child: Text(
                              data.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The right island — the universal "+", green from the brand mark. Tapping it
/// raises the quick-action menu; the glyph rotates to an "×" while it's open.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add or capture',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppTheme.brandGradient,
            boxShadow: [
              BoxShadow(
                color: AppTheme.brandGreen.withValues(alpha: 0.42),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AnimatedRotation(
            turns: open ? 0.125 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}

/// The floating menu that rises above the "+" — one tappable row per action,
/// each a coloured circle and a label.
class _QuickActionMenu extends StatelessWidget {
  const _QuickActionMenu({required this.actions});

  final List<MorphAction> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          // Clear of the bar: island height (60) + its bottom pad (12) + gap.
          padding: const EdgeInsets.only(right: 16, bottom: 84),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minWidth: 190, maxWidth: 280),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: context.hairline),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: context.isDark ? 0.4 : 0.16,
                    ),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final action in actions)
                      _QuickActionRow(action: action),
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

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({required this.action});

  final MorphAction action;

  @override
  Widget build(BuildContext context) {
    final accent = action.accent ?? context.scheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).pop();
        action.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: context.isDark ? 0.26 : 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(action.icon, size: 18, color: accent),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
