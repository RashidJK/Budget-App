import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../models/phosphor.dart';
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

/// The app's bottom navigation, in two floating islands:
///
///   ┌ destinations ─────────┐   ╭───╮
///   │ ▣  ▤   ◐   ▥ │        │ + │
///   └───────────────────────┘   ╰───╯
///
/// The left island holds the destinations; only the *selected* one expands to
/// show its label, the rest sit as bare icons.
///
/// Press the "+" and the bar **turns into capture in place**: the left island
/// *becomes* an expense prompt (type "5000 lunch", "received 500k salary", "move
/// 200k to mpesa" — the parser sorts the rest) and the right circle flips to the
/// icon of the tab you were on, so one tap takes you back where you were. No
/// modal, no dimming — the bar itself is the prompt.
///
/// It's context-aware: each screen hands it different [items], so the islands
/// morph per screen (inside an account they become that account's destinations).
class MorphNavBar extends StatefulWidget {
  const MorphNavBar({
    super.key,
    required this.items,
    required this.activeIndex,
    required this.onSelect,
    required this.onCapture,
    this.captureHint = "Try 'Transfer 100k to M-Pesa'",
  });

  final List<MorphNavItem> items;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  /// Parse + record the typed prompt. Returns true when handled (so the bar can
  /// close its prompt); false to keep the field open.
  final Future<bool> Function(String text) onCapture;

  final String captureHint;

  @override
  State<MorphNavBar> createState() => _MorphNavBarState();
}

class _MorphNavBarState extends State<MorphNavBar> {
  bool _capturing = false;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCapture() {
    HapticFeedback.lightImpact();
    setState(() => _capturing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _endCapture() {
    _focus.unfocus();
    _controller.clear();
    setState(() => _capturing = false);
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final handled = await widget.onCapture(text);
    if (handled && mounted) _endCapture();
  }

  @override
  Widget build(BuildContext context) {
    // A bottomNavigationBar doesn't rise for the keyboard on its own, so lift
    // the bar by the keyboard inset while capturing — the prompt stays in view.
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final activeItem = widget.items[widget.activeIndex.clamp(
      0,
      widget.items.length - 1,
    )];

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + (_capturing ? insets : 0)),
        child: Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _capturing
                    ? _PromptIsland(
                        key: const ValueKey('prompt'),
                        controller: _controller,
                        focus: _focus,
                        hint: widget.captureHint,
                        onSubmit: _submit,
                      )
                    : _DestinationIsland(
                        key: const ValueKey('destinations'),
                        items: widget.items,
                        activeIndex: widget.activeIndex,
                        onSelect: widget.onSelect,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            _RightButton(
              capturing: _capturing,
              // While capturing, the circle wears the icon of the tab you left,
              // so it reads as "back to Home / Planner / …".
              backItem: activeItem,
              onTap: _capturing ? _endCapture : _startCapture,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared glass treatment for the island, so the destinations and the prompt
/// read as the same surface morphing.
class _IslandShell extends StatelessWidget {
  const _IslandShell({required this.child});

  final Widget child;

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
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The left island in its normal state — destinations, active one expanded.
class _DestinationIsland extends StatelessWidget {
  const _DestinationIsland({
    super.key,
    required this.items,
    required this.activeIndex,
    required this.onSelect,
  });

  final List<MorphNavItem> items;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return _IslandShell(
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

/// The left island in capture mode — the expense prompt, in place.
class _PromptIsland extends StatelessWidget {
  const _PromptIsland({
    super.key,
    required this.controller,
    required this.focus,
    required this.hint,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return _IslandShell(
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(PhosphorR.lightning, size: 20, color: context.scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
              cursorColor: AppTheme.brandGreen,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(
                  color: context.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // The send affordance lights up once there's something to record.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final ready = value.text.trim().isNotEmpty;
              return IconButton(
                onPressed: ready ? onSubmit : null,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  size: 22,
                  color: ready ? AppTheme.brandGreen : context.muted,
                ),
                tooltip: 'Record',
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The right island. Normally the universal "+"; while capturing it wears the
/// icon of the tab you came from, as a one-tap way back.
class _RightButton extends StatelessWidget {
  const _RightButton({
    required this.capturing,
    required this.backItem,
    required this.onTap,
  });

  final bool capturing;
  final MorphNavItem backItem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: capturing ? 'Back to ${backItem.label}' : 'Add or capture',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: capturing ? null : AppTheme.brandGradient,
            color: capturing ? context.card : null,
            border: capturing ? Border.all(color: context.hairline) : null,
            boxShadow: [
              BoxShadow(
                color: capturing
                    ? Colors.black.withValues(alpha: context.isDark ? 0.3 : 0.1)
                    : AppTheme.brandGreen.withValues(alpha: 0.42),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: capturing
                ? Icon(
                    backItem.activeIcon,
                    key: ValueKey('back-${backItem.label}'),
                    color: backItem.accent ?? context.scheme.primary,
                    size: 24,
                  )
                : const Icon(
                    Icons.add_rounded,
                    key: ValueKey('add'),
                    color: Colors.white,
                    size: 30,
                  ),
          ),
        ),
      ),
    );
  }
}
