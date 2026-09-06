import 'dart:math' as math;
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

/// The app's bottom navigation as islands and circles.
///
/// At rest: a **nav island** (the destinations, active one expanded) on the
/// left, and one **right island** holding two circles — the **+** and a
/// **Functions** circle.
///
/// Tap **+** and it opens the capture prompt directly: the island splits, the
/// nav collapses to the current-tab dot, and the prompt takes the middle.
/// Tap **Functions** and the island splits into separate circles as it expands
/// into contextual controls (back · forward · more). Either way the tab-dot is
/// one tap back to where you were.
enum _Mode { rest, add, fn }

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

class _MorphNavBarState extends State<MorphNavBar>
    with SingleTickerProviderStateMixin {
  _Mode _mode = _Mode.rest;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  // Drives the Siri-style gradient stroke around the prompt while capturing.
  late final AnimationController _stroke;

  @override
  void initState() {
    super.initState();
    _stroke = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
  }

  @override
  void dispose() {
    _stroke.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toRest() {
    _stroke.stop();
    _focus.unfocus();
    _controller.clear();
    setState(() => _mode = _Mode.rest);
  }

  void _toAdd() {
    HapticFeedback.lightImpact();
    _stroke
      ..value = 0
      ..repeat();
    setState(() => _mode = _Mode.add);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _toFn() {
    _stroke.stop();
    HapticFeedback.lightImpact();
    setState(() => _mode = _Mode.fn);
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final handled = await widget.onCapture(text);
    if (handled && mounted) _toRest();
  }

  @override
  Widget build(BuildContext context) {
    final insets = _mode == _Mode.add
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;
    final active = widget.items[widget.activeIndex.clamp(
      0,
      widget.items.length - 1,
    )];

    final row = switch (_mode) {
      _Mode.rest => Row(
        key: const ValueKey('rest'),
        children: [
          Expanded(child: _navIsland()),
          const SizedBox(width: 12),
          _groupedRight(),
        ],
      ),
      // Capture is exactly the prompt as before: the wide prompt island with
      // the "back to your tab" circle on the right — nothing else.
      _Mode.add => Row(
        key: const ValueKey('add'),
        children: [
          Expanded(
            child: _SiriStroke(t: _stroke, child: _promptIsland()),
          ),
          const SizedBox(width: 12),
          _tabDot(active),
        ],
      ),
      _Mode.fn => Row(
        key: const ValueKey('fn'),
        children: [
          _tabDot(active),
          const SizedBox(width: 12),
          _AddCircle(onTap: _toAdd),
          const SizedBox(width: 12),
          Expanded(child: _functionsIsland()),
        ],
      ),
    };

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + insets),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(anim),
              child: child,
            ),
          ),
          child: row,
        ),
      ),
    );
  }

  // --- rest -----------------------------------------------------------------

  Widget _navIsland() {
    return _IslandShell(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < widget.items.length; i++)
            _MorphTab(
              data: widget.items[i],
              selected: i == widget.activeIndex,
              onTap: () => widget.onSelect(i),
            ),
        ],
      ),
    );
  }

  /// The right island at rest: the + and the Functions "⋯", grouped on one
  /// frosted pill. The "⋯" is a bare icon so the island's glass shows through.
  Widget _groupedRight() {
    return _IslandShell(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AddCircle(onTap: _toAdd, size: 46),
          const SizedBox(width: 4),
          _FnCircle(onTap: _toFn),
        ],
      ),
    );
  }

  // --- add ------------------------------------------------------------------

  Widget _promptIsland() {
    return _IslandShell(
      child: Row(
        children: [
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              cursorColor: AppTheme.brandGreen,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: widget.captureHint,
                hintStyle: TextStyle(
                  color: context.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final ready = value.text.trim().isNotEmpty;
              return IconButton(
                onPressed: ready ? _submit : null,
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

  // --- fn -------------------------------------------------------------------

  Widget _functionsIsland() {
    return _IslandShell(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _fnAction(
            Icons.chevron_left_rounded,
            'Back',
            onTap: _toRest,
          ),
          _fnAction(Icons.chevron_right_rounded, 'Forward', onTap: null),
          _fnAction(Icons.more_horiz_rounded, 'More', onTap: () {}),
        ],
      ),
    );
  }

  Widget _fnAction(IconData icon, String label, {VoidCallback? onTap}) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        radius: 26,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(
            icon,
            size: 24,
            color: enabled
                ? context.scheme.onSurface
                : context.scheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  // --- shared circles -------------------------------------------------------

  Widget _tabDot(MorphNavItem item) {
    return Semantics(
      button: true,
      label: 'Back to ${item.label}',
      child: GestureDetector(
        onTap: _toRest,
        child: _GlassCircle(
          child: Icon(
            item.activeIcon,
            color: item.accent ?? context.scheme.primary,
            size: 24,
          ),
        ),
      ),
    );
  }
}

/// Shared frosted-glass shell for an island or a wide segment.
class _IslandShell extends StatelessWidget {
  const _IslandShell({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 6),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final fill = dark
        ? const Color(0xFF232322).withValues(alpha: 0.62)
        : Colors.white.withValues(alpha: 0.72);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 60,
            padding: padding,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(30),
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
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 13 : 9,
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

/// The green brand "+" circle.
class _AddCircle extends StatelessWidget {
  const _AddCircle({required this.onTap, this.size = 60});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add or capture',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppTheme.brandGradient,
            boxShadow: [
              BoxShadow(
                color: AppTheme.brandGreen.withValues(alpha: 0.42),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(Icons.add_rounded, color: Colors.white, size: size * 0.5),
        ),
      ),
    );
  }
}

/// The Functions "⋯" inside the grouped island — a bare icon sitting on the
/// island's frosted glass (no disc of its own), so the glass reads through.
class _FnCircle extends StatelessWidget {
  const _FnCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Functions',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(
            Icons.more_horiz_rounded,
            size: 24,
            color: context.muted,
          ),
        ),
      ),
    );
  }
}

/// A Siri-style stroke: a multi-hue sweep gradient that rotates around the
/// prompt's edge with a soft outer glow, so the capture field feels "listening".
class _SiriStroke extends StatelessWidget {
  const _SiriStroke({required this.t, required this.child});

  final Animation<double> t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, inner) => CustomPaint(
        foregroundPainter: _StrokePainter(t.value),
        child: inner,
      ),
      child: child,
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.t);

  final double t;

  // Brand green flowing through teal, cyan and indigo and back — Siri-ish, but
  // anchored to the app's green.
  static const _colors = [
    Color(0xFF97E29E),
    Color(0xFF3CA98B),
    Color(0xFF33B1E0),
    Color(0xFF6C7BF5),
    Color(0xFF97E29E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.height / 2);
    final shader = SweepGradient(
      colors: _colors,
      stops: const [0.0, 0.28, 0.55, 0.8, 1.0],
      transform: GradientRotation(t * 2 * math.pi),
    ).createShader(rect);

    // Soft outer glow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1.4), radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Crisp stroke on the edge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1.1), radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_StrokePainter old) => old.t != t;
}

/// A frosted-glass circle matching the island shell.
class _GlassCircle extends StatelessWidget {
  const _GlassCircle({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final fill = dark
        ? const Color(0xFF232322).withValues(alpha: 0.62)
        : Colors.white.withValues(alpha: 0.72);

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
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
