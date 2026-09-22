import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

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
/// At rest: a **nav island** (destinations, active one expanded) on the left,
/// and one **right island** holding two circles — the **+** and a **Functions**
/// "⋯".
///
/// Tap **+** and the prompt slides open in place; tap **Functions** and the
/// right island splits into circles as it expands into back · forward · more.
/// The islands don't cross-fade — they **morph**: the segment widths slide
/// between layouts while each piece stays crisp and is clipped as it goes.
enum _Mode { rest, add, fn }

class MorphNavBar extends StatefulWidget {
  const MorphNavBar({
    super.key,
    required this.items,
    required this.activeIndex,
    required this.onSelect,
    required this.onCapture,
    this.onScan,
    this.onBriefing,
    this.captureHint = "Try 'Transfer 100k to M-Pesa'",
  });

  final List<MorphNavItem> items;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  /// Parse + record the typed prompt. Returns true when handled (so the bar can
  /// close its prompt); false to keep the field open.
  final Future<bool> Function(String text) onCapture;

  /// Opens the receipt scanner. When null, the prompt shows no camera.
  final VoidCallback? onScan;

  /// Opens the blue briefing island. When null, the briefing icon is hidden.
  final VoidCallback? onBriefing;

  final String captureHint;

  @override
  State<MorphNavBar> createState() => _MorphNavBarState();
}

class _MorphNavBarState extends State<MorphNavBar>
    with TickerProviderStateMixin {
  _Mode _mode = _Mode.rest;
  _Mode _prev = _Mode.rest;

  final _controller = TextEditingController();
  final _focus = FocusNode();

  // Slides the segment widths between layouts on a mode change.
  late final AnimationController _morph;
  // The Siri-style gradient stroke around the prompt while capturing.
  late final AnimationController _stroke;

  @override
  void initState() {
    super.initState();
    _morph = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1,
    );
    _stroke = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
  }

  @override
  void dispose() {
    _morph.dispose();
    _stroke.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(_Mode mode) {
    if (mode == _mode) return;
    setState(() {
      _prev = _mode;
      _mode = mode;
    });
    _morph.forward(from: 0);
  }

  void _toRest() {
    _stroke.stop();
    _focus.unfocus();
    _controller.clear();
    _go(_Mode.rest);
  }

  void _toAdd() {
    HapticFeedback.lightImpact();
    _playRipple();
    _stroke
      ..value = 0
      ..repeat();
    _go(_Mode.add);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _toFn() {
    _stroke.stop();
    HapticFeedback.lightImpact();
    _go(_Mode.fn);
  }

  // Swipe up on the bar to open capture; swipe down to close it. The bar sits
  // above the home indicator, so this doesn't fight the iOS home gesture.
  void _onSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_mode == _Mode.rest && v < -320) {
      _toAdd();
    } else if (_mode == _Mode.add && v > 320) {
      _toRest();
    }
  }

  // A Siri-style ripple washing up the screen from the bottom, as capture opens.
  void _playRipple() {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _SiriRipple(onDone: entry.remove));
    overlay.insert(entry);
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final handled = await widget.onCapture(text);
    if (handled && mounted) _toRest();
  }

  // Seed the field from a quick-action pill, then let the user finish typing.
  void _prime(String starter) {
    HapticFeedback.selectionClick();
    _controller.text = starter;
    _controller.selection = TextSelection.collapsed(offset: starter.length);
    _focus.requestFocus();
  }

  // Segment layout for a mode: [nav, gap, capture, gap, aux], summing to [W].
  List<double> _layout(_Mode mode, double w) {
    switch (mode) {
      case _Mode.rest:
        return [w - 120, 12, 52, 4, 52];
      case _Mode.add:
        return [0, 12, w - 96, 12, 72];
      case _Mode.fn:
        return [72, 12, 72, 12, w - 168];
    }
  }

  double _presence(_Mode mode, double t) =>
      (_mode == mode ? t : 0) + (_prev == mode ? 1 - t : 0);

  @override
  Widget build(BuildContext context) {
    final insets = _mode == _Mode.add
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;
    final active =
        widget.items[widget.activeIndex.clamp(0, widget.items.length - 1)];

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + insets),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fullW = constraints.maxWidth;
            return AnimatedBuilder(
              animation: _morph,
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_morph.value);
                final animating = _morph.value < 1;
                final addness = _presence(_Mode.add, t).clamp(0.0, 1.0);
                // In add mode the chatbox backdrop pads the content in by 14 on
                // each side, so the bar lays out into a correspondingly narrower
                // width — otherwise the fixed slots overflow the padded panel.
                final w = fullW - 28 * addness;
                final a = _layout(_prev, w);
                final b = _layout(_mode, w);
                double at(int i) => lerpDouble(a[i], b[i], t)!;
                final w0 = at(0),
                    g0 = at(1),
                    w1 = at(2),
                    g1 = at(3),
                    w2 = at(3 + 1);
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragEnd: _onSwipe,
                  child: _chatboxBackdrop(
                    addness,
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _pillsBlock(addness),
                        SizedBox(
                          height: 60,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // The grouped pill behind the + and ⋯, only at rest.
                              Positioned(
                                left: w0 + g0,
                                top: 0,
                                bottom: 0,
                                width: w1 + g1 + w2,
                                child: Opacity(
                                  opacity: _presence(
                                    _Mode.rest,
                                    t,
                                  ).clamp(0.0, 1.0),
                                  child: const IgnorePointer(
                                    child: _GlassSurface(),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  SizedBox(
                                    width: w0,
                                    child: _navSlot(active, w, t, animating),
                                  ),
                                  SizedBox(width: g0),
                                  SizedBox(
                                    width: w1,
                                    child: _captureSlot(w, t, animating),
                                  ),
                                  SizedBox(width: g1),
                                  SizedBox(
                                    width: w2,
                                    child: _auxSlot(active, w, t, animating),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // --- slots ----------------------------------------------------------------

  Widget _navSlot(MorphNavItem active, double w, double t, bool animating) {
    return _CrossSlot(
      t: t,
      animating: animating,
      prev: _prev,
      curr: _mode,
      contentFor: (m) => switch (m) {
        _Mode.rest => (_navIsland(), w - 120, Alignment.centerLeft),
        _Mode.fn => (_tabDot(active), 60.0, Alignment.center),
        _Mode.add => (const SizedBox.shrink(), 0.0, Alignment.center),
      },
    );
  }

  Widget _captureSlot(double w, double t, bool animating) {
    return _CrossSlot(
      t: t,
      animating: animating,
      prev: _prev,
      curr: _mode,
      // The prompt's Siri glow blooms ~30px past the pill; give it room.
      clipMargin: 34,
      contentFor: (m) => switch (m) {
        _Mode.rest => (
          _AddCircle(onTap: _toAdd, size: 46),
          46.0,
          Alignment.center,
        ),
        _Mode.add => (_prompt(), w - 96, Alignment.centerLeft),
        _Mode.fn => (_AddCircle(onTap: _toAdd), 60.0, Alignment.center),
      },
    );
  }

  Widget _auxSlot(MorphNavItem active, double w, double t, bool animating) {
    return _CrossSlot(
      t: t,
      animating: animating,
      prev: _prev,
      curr: _mode,
      contentFor: (m) => switch (m) {
        _Mode.rest => (
          _iconTap(Icons.more_horiz_rounded, 'More', context.muted, _toFn),
          52.0,
          Alignment.center,
        ),
        _Mode.add => (_tabDot(active), 60.0, Alignment.center),
        _Mode.fn => (_functionsIsland(), w - 168, Alignment.centerLeft),
      },
    );
  }

  // --- content --------------------------------------------------------------

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

  Widget _prompt() {
    return _SiriStroke(
      t: _stroke,
      child: _IslandShell(
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
            if (widget.onScan != null)
              IconButton(
                onPressed: widget.onScan,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.photo_camera_rounded,
                  size: 21,
                  color: context.muted,
                ),
                tooltip: 'Scan a receipt',
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
      ),
    );
  }

  Widget _functionsIsland() {
    return _IslandShell(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _fnAction(Icons.chevron_left_rounded, 'Back', onTap: _toRest),
          if (widget.onBriefing != null)
            _fnAction(
              Icons.auto_awesome_rounded,
              'Your briefing',
              color: context.scheme.primary,
              onTap: () {
                widget.onBriefing!();
                _toRest();
              },
            ),
        ],
      ),
    );
  }

  Widget _fnAction(
    IconData icon,
    String label, {
    VoidCallback? onTap,
    Color? color,
  }) {
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
                ? (color ?? context.scheme.onSurface)
                : context.scheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  Widget _iconTap(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: 34,
          height: 60,
          child: Center(child: Icon(icon, size: 22, color: color)),
        ),
      ),
    );
  }

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

  // --- quick-action pills (above the prompt) --------------------------------

  /// Rises into view above the prompt as you enter capture; collapses away
  /// otherwise. [f] is how "present" the add state is (0..1).
  /// A larger rounded backdrop behind the whole chatbox — the quick-action
  /// pills and the prompt bar — in our green. It fades in with the add-mode
  /// presence [f] (nothing at rest, so the resting bar is untouched) and pads
  /// the content in as it grows, so the bar and pills sit inside one panel.
  Widget _chatboxBackdrop(double f, Widget child) {
    if (f <= 0) return child;
    final dark = context.isDark;
    // A light, airy panel defined by a crisp brand-green outline — matching the
    // reference chatbox, where the green lives in the border, not a saturated
    // fill, so the white pills and prompt bar read cleanly inside it.
    final top = dark ? const Color(0xFF1B2E23) : const Color(0xFFF1F8F4);
    final bottom = dark ? const Color(0xFF13221B) : const Color(0xFFDDEFE6);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            top.withValues(alpha: f),
            bottom.withValues(alpha: f),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        // A crisp green stroke frames the panel. A DecoratedBox paints its border
        // over the box edges without insetting the child, so it doesn't shrink
        // the width the bar lays out into — no overflow, unlike a Container.
        border: Border.all(
          color: AppTheme.brandGreen.withValues(alpha: 0.60 * f),
          width: 1.6,
        ),
        // A whisper of a drop shadow lifts the panel; the edge itself stays crisp.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05 * f),
            blurRadius: 10 * f,
            offset: Offset(0, 5 * f),
          ),
        ],
      ),
      child: Padding(padding: EdgeInsets.all(14 * f), child: child),
    );
  }

  Widget _pillsBlock(double f) {
    return ClipRect(
      child: Align(
        alignment: Alignment.bottomLeft,
        heightFactor: f,
        child: IgnorePointer(
          ignoring: f < 0.5,
          child: Opacity(
            opacity: f,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _pillsRow(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pillsRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill(Icons.south_west_rounded, 'Income', context.good, 'Received '),
        const SizedBox(width: 8),
        _pill(
          Icons.swap_horiz_rounded,
          'Transfer',
          const Color(0xFF7C6BF5),
          'Transfer ',
        ),
        const SizedBox(width: 8),
        _pill(
          Icons.people_alt_rounded,
          'Loan',
          context.scheme.primary,
          'Lent ',
        ),
      ],
    );
  }

  Widget _pill(IconData icon, String label, Color accent, String starter) {
    final dark = context.isDark;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: () => _prime(starter),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: dark
                ? const Color(0xFF232322).withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.hairline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.28 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One slot that cross-fades between the previous and current mode's content —
/// each rendered at its own natural width and clipped, so the piece stays crisp
/// while the slot's width animates.
class _CrossSlot extends StatelessWidget {
  const _CrossSlot({
    required this.t,
    required this.animating,
    required this.prev,
    required this.curr,
    required this.contentFor,
    this.clipMargin = 0,
  });

  final double t;
  final bool animating;
  final _Mode prev;
  final _Mode curr;
  final (Widget, double, Alignment) Function(_Mode) contentFor;

  /// Extra room around the slot's clip, so a glow can bloom past the edge
  /// instead of being boxed into the rectangle.
  final double clipMargin;

  Widget _layer(_Mode mode, double opacity) {
    if (opacity <= 0.001) return const SizedBox.shrink();
    final (child, width, align) = contentFor(mode);
    if (width <= 0) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: opacity < 0.5,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: ClipRect(
            clipper: clipMargin > 0 ? _BloomClip(clipMargin) : null,
            child: OverflowBox(
              minWidth: width,
              maxWidth: width,
              minHeight: 60,
              maxHeight: 60,
              alignment: align,
              child: SizedBox(width: width, height: 60, child: child),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (animating && prev != curr) _layer(prev, 1 - t),
        _layer(curr, animating ? t : 1.0),
      ],
    );
  }
}

/// Clips a slot but leaves [m] px of room on every side, so a glow can bloom
/// past the edge rather than ending in a hard rectangle.
class _BloomClip extends CustomClipper<Rect> {
  const _BloomClip(this.m);

  final double m;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-m, -m, size.width + m, size.height + m);

  @override
  bool shouldReclip(_BloomClip old) => old.m != m;
}

/// Shared frosted-glass shell for a stadium-shaped island or segment.
class _IslandShell extends StatelessWidget {
  const _IslandShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: child,
      ),
    );
  }
}

/// The raw frosted stadium — fills its box; used on its own as the grouped pill
/// and wrapped by [_IslandShell] for content.
class _GlassSurface extends StatelessWidget {
  const _GlassSurface({this.child});

  final Widget? child;

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
              horizontal: selected ? 11 : 8,
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

/// A Siri-style stroke: a warm-to-cool sweep gradient blooming behind the
/// prompt with a crisp bright edge in front.
class _SiriStroke extends StatelessWidget {
  const _SiriStroke({required this.t, required this.child});

  final Animation<double> t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, inner) => CustomPaint(
        painter: _StrokePainter(t.value, foreground: false),
        foregroundPainter: _StrokePainter(t.value, foreground: true),
        child: inner,
      ),
      child: child,
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.t, {required this.foreground});

  final double t;
  final bool foreground;

  // Brand green, flowing light → teal → light as it sweeps round the prompt.
  static const _colors = [
    Color(0xFF97E29E),
    Color(0xFF5FD09E),
    Color(0xFF3CA98B),
    Color(0xFF5FD09E),
    Color(0xFF97E29E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.height / 2);
    final shader = SweepGradient(
      colors: _colors,
      stops: const [0.0, 0.3, 0.55, 0.82, 1.0],
      transform: GradientRotation(t * 2 * math.pi),
    ).createShader(rect.inflate(6));

    if (foreground) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1), radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..shader = shader,
      );
      return;
    }

    void glow(double width, double blur, double inflate) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(inflate), radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = shader
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }

    // A tight, subtle sheen — no broad bloom — so the prompt reads clean-edged
    // like the reference, letting the crisp foreground stroke carry the accent.
    glow(5, 5, 1);
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.t != t || old.foreground != foreground;
}

/// The Apple-Intelligence-style screen-edge glow — a soft gradient that hugs
/// the screen's rounded-rectangle perimeter, bleeding inward, blooming then
/// fading as capture opens, its colours sweeping gently round. It removes
/// itself when the animation finishes.
class _SiriRipple extends StatefulWidget {
  const _SiriRipple({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_SiriRipple> createState() => _SiriRippleState();
}

class _SiriRippleState extends State<_SiriRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1200),
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onDone();
        });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) =>
              CustomPaint(painter: _RipplePainter(_c.value)),
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.t);

  final double t;

  // Two greens — light into teal — looped so the sweep has no seam.
  static const _edge = [
    Color(0xFF97E29E),
    Color(0xFF3CA98B),
    Color(0xFF97E29E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Rise then fall in intensity across the animation.
    final env = math.sin(math.pi * t.clamp(0.0, 1.0));
    if (env <= 0.01) return;

    // Fade the whole glow by the envelope via a layer alpha.
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Color.fromRGBO(0, 0, 0, env.clamp(0.0, 1.0)),
    );

    // Hug the screen's rounded corners; the wide blur spills inward.
    final rect = (Offset.zero & size).deflate(2);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(54));
    final shader = SweepGradient(
      colors: _edge,
      transform: GradientRotation(0.15 + t * math.pi),
    ).createShader(rect);

    void glow(double width, double blur) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = shader
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }

    glow(30, 28); // broad soft inner glow
    glow(14, 12); // mid halo
    glow(6, 4); // soft definition — no hard line
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.t != t;
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
