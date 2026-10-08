import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/brain/brain_shell.dart';
import '../screens/home_shell.dart';
import '../theme.dart';
import 'app_space.dart';

/// The root shell: a zoom-out "Spaces" home that holds each app as a card.
///
/// Pinch in with two fingers from inside any app to zoom out to the Spaces home;
/// tap a card — or spread two fingers back out — to zoom into it. The focused
/// app is rendered live the whole time, scaling between full-screen and its
/// card, so its card is a real moving thumbnail rather than a static snapshot.
///
/// Touch pinch is tracked with a raw [Listener] rather than a scale
/// GestureDetector, so it observes the two fingers without winning the gesture
/// arena. Browser trackpad pinch arrives as a scale signal.
class SpacesShell extends StatefulWidget {
  const SpacesShell({super.key});

  @override
  State<SpacesShell> createState() => _SpacesShellState();
}

class _SpacesShellState extends State<SpacesShell>
    with SingleTickerProviderStateMixin {
  // 0 = zoomed all the way into the focused app, 1 = the Spaces home.
  late final AnimationController _zoom;
  int _activeIndex = 0;

  late final List<AppSpace> _apps = [
    AppSpace(
      id: 'budget',
      name: 'Budget',
      tagline: 'Track your money',
      icon: Icons.account_balance_wallet_rounded,
      accent: AppTheme.brandGreen,
      builder: (_) => HomeShell(
        onBackToSpaces: () => _zoom.animateTo(1, curve: Curves.easeOutCubic),
      ),
    ),
    AppSpace(
      id: 'brain',
      name: 'Second Brain',
      tagline: 'Notes · tasks · journal',
      icon: Icons.bubble_chart_rounded,
      accent: BrainShell.accent,
      builder: (_) => BrainShell(
        onSelectApp: _enter,
        onBackToSpaces: () => _zoom.animateTo(1, curve: Curves.easeOutCubic),
      ),
    ),
  ];

  // --- pinch tracking -------------------------------------------------------
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDist;
  double _zoomAtPinchStart = 0;
  bool _pinching = false;

  @override
  void initState() {
    super.initState();
    _zoom = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    // Reflect where you are in the browser tab / app switcher: the focused app's
    // name while zoomed in, "Spaces" once the launcher is open.
    _zoom.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _setTabTitle('Spaces');
      } else if (status == AnimationStatus.dismissed) {
        _setTabTitle(_apps[_activeIndex].name);
      }
    });
    _setTabTitle(_apps[_activeIndex].name);
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _setTabTitle(String label) {
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(label: label),
    );
  }

  void _enter(int i) {
    if (i != _activeIndex) setState(() => _activeIndex = i);
    _setTabTitle(_apps[i].name);
    _zoom.animateTo(0, curve: Curves.easeOutCubic);
  }

  double _twoFingerDistance() {
    final pts = _pointers.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinchStartDist = _twoFingerDistance();
      _zoomAtPinchStart = _zoom.value;
      _pinching = true;
      _zoom.stop();
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final start = _pinchStartDist;
    if (_pinching && _pointers.length >= 2 && start != null && start > 0) {
      final ratio = _twoFingerDistance() / start;
      // Pinch in (ratio < 1) opens the launcher; spread out (ratio > 1) dives
      // back into the focused app.
      _zoom.value = (_zoomAtPinchStart + (1 - ratio)).clamp(0.0, 1.0);
    }
  }

  void _onPointerUpOrCancel(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pinching && _pointers.length < 2) {
      _pinching = false;
      _pinchStartDist = null;
      // Settle to whichever end we're closest to.
      _zoom.animateTo(
        _zoom.value > 0.4 ? 1 : 0,
        curve: Curves.easeOutCubic,
        duration: const Duration(milliseconds: 240),
      );
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScaleEvent) return;
    if (event.scale == 1) return;
    final destination = event.scale < 1 ? 1.0 : 0.0;
    _zoom.animateTo(destination, curve: Curves.easeOutCubic);
  }

  /// The resting card rectangles on the Spaces home — full-width cards stacked
  /// vertically and centred in the space below the heading.
  List<Rect> _slots(Size size) {
    const hMargin = 20.0;
    const bottomPad = 32.0;
    const gap = 18.0;
    final topInset = MediaQuery.of(context).padding.top;
    final headerH = topInset + 84; // status bar + "Spaces" heading
    final n = _apps.length;
    final cardW = size.width - 2 * hMargin;
    final avail = size.height - headerH - bottomPad;
    final cardH = ((avail - (n - 1) * gap) / n).clamp(160.0, 300.0);
    final groupH = n * cardH + (n - 1) * gap;
    final y0 = headerH + (avail - groupH) / 2;
    return [
      for (var i = 0; i < n; i++)
        Rect.fromLTWH(hMargin, y0 + i * (cardH + gap), cardW, cardH),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUpOrCancel,
        onPointerCancel: _onPointerUpOrCancel,
        onPointerSignal: _onPointerSignal,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final slots = _slots(size);
            final fullRect = Offset.zero & size;
            return AnimatedBuilder(
              animation: _zoom,
              builder: (context, _) {
                final raw = _zoom.value;
                final z = Curves.easeOutCubic.transform(raw);
                final activeFrame = Rect.lerp(
                  fullRect,
                  slots[_activeIndex],
                  z,
                )!;
                return Stack(
                  children: [
                    // Always-present backdrop, so the shrinking app never reveals
                    // a transparent gap.
                    Positioned.fill(child: _backdrop(size, z)),
                    // Inactive apps, as branded cards fixed in their slots.
                    for (var i = 0; i < _apps.length; i++)
                      if (i != _activeIndex)
                        Positioned.fromRect(
                          rect: slots[i],
                          child: IgnorePointer(
                            ignoring: raw < 0.6,
                            child: Opacity(
                              opacity: z,
                              child: _AppCard(
                                app: _apps[i],
                                onTap: () => _enter(i),
                              ),
                            ),
                          ),
                        ),
                    // The focused app — rendered live, scaling between full-screen
                    // and its card.
                    Positioned.fromRect(
                      rect: activeFrame,
                      child: _liveCard(size, activeFrame, z),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _backdrop(Size size, double z) {
    final dark = context.isDark;
    final top = dark ? const Color(0xFF15151F) : const Color(0xFF20303F);
    final bottom = dark ? const Color(0xFF0B0B10) : const Color(0xFF0E141B);
    final topInset = MediaQuery.of(context).padding.top;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ),
      ),
      child: Opacity(
        opacity: z,
        child: Padding(
          padding: EdgeInsets.only(top: topInset + 22, left: 24, right: 24),
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Spaces',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    PopupMenuButton<int>(
                      initialValue: _activeIndex,
                      tooltip: 'Switch app',
                      position: PopupMenuPosition.under,
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      onSelected: (index) {
                        if (index != _activeIndex) {
                          setState(() => _activeIndex = index);
                          _zoom.animateTo(0, curve: Curves.easeOutCubic);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _apps[_activeIndex].icon,
                              color: Colors.white,
                              size: 15,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _apps[_activeIndex].name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                      itemBuilder: (context) => [
                        for (var i = 0; i < _apps.length; i++)
                          PopupMenuItem<int>(
                            value: i,
                            child: Row(
                              children: [
                                Icon(
                                  _apps[i].icon,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _apps[i].name,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pinch to switch apps',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _liveCard(Size size, Rect frame, double z) {
    final scale = frame.width / size.width;
    // The full-size app, scaled to the frame's width and top-anchored, then
    // clipped to the frame — so the card shows the top of the live app.
    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(34 * z),
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minWidth: 0,
        maxWidth: double.infinity,
        minHeight: 0,
        maxHeight: double.infinity,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: _apps[_activeIndex].builder(context),
          ),
        ),
      ),
    );

    final zoomedOutish = z > 0.02;
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        // Once it starts shrinking, block the app's own touches and let a tap
        // dive back in; a rounded outline + shadow reads it as a card.
        if (zoomedOutish) ...[
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34 * z),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10 * z),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35 * z),
                    blurRadius: 34 * z,
                    offset: Offset(0, 14 * z),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _enter(_activeIndex),
          ),
        ],
      ],
    );
  }
}

/// A branded card for an app that isn't the focused one on the Spaces home.
class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.onTap});

  final AppSpace app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Color.lerp(app.accent, Colors.black, 0.28)!;
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [app.accent, dark],
          ),
          boxShadow: [
            BoxShadow(
              color: app.accent.withValues(alpha: 0.35),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(app.icon, color: Colors.white, size: 26),
              ),
              const Spacer(),
              Text(
                app.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                app.tagline,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
