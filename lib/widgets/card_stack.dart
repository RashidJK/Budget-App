import 'package:flutter/material.dart';

/// A short deck of cards shown stacked, with the ones behind peeking a little
/// above the front card. Swipe **up** on the front card (or tap a peeking one)
/// to bring the next card forward; swipe down to go back. A row of page dots
/// below the deck marks how many cards there are and which is on top — tap one
/// to jump straight to that card.
///
/// The front card is fully interactive — taps on its buttons pass straight
/// through; only a deliberate vertical fling changes the card. Pinching the
/// deck in (two fingers) fires [onPinch], used to fan it out into a spread.
class CardStack extends StatefulWidget {
  const CardStack({
    super.key,
    required this.cards,
    required this.height,
    this.peek = 12,
    this.initialIndex = 0,
    this.notchFront = false,
    this.onPinch,
  });

  /// Cut a concave "wallet pocket" notch into the top of the front card, so the
  /// card behind shows through it — the layered-wallet look.
  final bool notchFront;

  /// Fired when the deck is pinched in (two fingers together) — used to fan the
  /// stack out into a full spread. Single-finger swipes still page the deck.
  final VoidCallback? onPinch;

  /// Front-first: the first entry starts on top.
  final List<Widget> cards;

  /// Which card is on top to begin with.
  final int initialIndex;

  /// The fixed height of the front card. The deck reserves a little extra above
  /// it for the peeking cards.
  final double height;

  /// How far each card behind pokes out above the one in front of it.
  final double peek;

  @override
  State<CardStack> createState() => _CardStackState();
}

class _CardStackState extends State<CardStack> {
  late int _front = widget.initialIndex;

  // The front card uses one scale recognizer for both the single-finger paging
  // fling and the two-finger pinch, so they never fight in the gesture arena.
  // This latches true once a pinch has opened the spread, so the gesture's end
  // doesn't then also page the deck.
  bool _pinched = false;

  void _advance(int direction) {
    final n = widget.cards.length;
    if (n < 2) return;
    setState(() => _front = (_front + direction) % n);
    if (_front < 0) _front += n;
  }

  /// Bring card [index] to the front — used by the page dots.
  void _jumpTo(int index) {
    if (index == _front) return;
    setState(() => _front = index);
  }

  Widget _buildCard(_DeckEntry entry) {
    Widget card = widget.cards[entry.index];

    // The front card wears the wallet-pocket notch, so the card behind shows
    // through the dip. Its own shadow is clipped, so the shape draws one.
    if (widget.notchFront && entry.depth == 0) {
      const notch = WalletNotchBorder();
      card = DecoratedBox(
        decoration: const ShapeDecoration(
          shape: notch,
          shadows: [
            BoxShadow(
              color: Color(0x3B000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: notch),
          child: card,
        ),
      );
    }

    if (entry.depth == 0) {
      // Front card: one scale recognizer handles both a single-finger paging
      // fling and a two-finger pinch; buttons still tap straight through.
      return GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onScaleStart: (_) => _pinched = false,
        onScaleUpdate: (d) {
          // Fire once as soon as a two-finger pinch-in crosses the threshold.
          if (d.pointerCount >= 2 &&
              !_pinched &&
              d.scale < 0.82 &&
              widget.onPinch != null) {
            _pinched = true;
            widget.onPinch!();
          }
        },
        onScaleEnd: (d) {
          if (_pinched) return; // the pinch already opened the spread
          final v = d.velocity.pixelsPerSecond.dy;
          if (v < -200) {
            _advance(1); // fling up → next
          } else if (v > 200) {
            _advance(-1); // fling down → previous
          }
        },
        child: card,
      );
    }
    // A peeking card: tap it to pull it forward.
    return GestureDetector(onTap: () => _advance(1), child: card);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.cards.length;
    final maxDepth = n - 1;
    // Only the first two cards behind peek; deeper ones sit at the same spot and
    // fade, so the deck's headroom stays fixed however many cards it holds.
    const maxVisible = 2;
    final visible = maxDepth < maxVisible ? maxDepth : maxVisible;
    final reserved = visible * widget.peek;

    // Order back-to-front so the front card paints last (on top).
    final entries = <_DeckEntry>[];
    for (var i = 0; i < n; i++) {
      final depth = (i - _front) % n;
      entries.add(_DeckEntry(index: i, depth: depth < 0 ? depth + n : depth));
    }
    entries.sort((a, b) => b.depth.compareTo(a.depth));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height + reserved,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final entry in entries)
                AnimatedPositioned(
                  key: ValueKey(entry.index),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  top:
                      reserved -
                      (entry.depth < maxVisible ? entry.depth : maxVisible) *
                          widget.peek,
                  left: 0,
                  right: 0,
                  height: widget.height,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    scale:
                        1 -
                        (entry.depth < maxVisible ? entry.depth : maxVisible) *
                            0.04,
                    alignment: Alignment.topCenter,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 320),
                      // Cards more than two deep fade so a long deck stays tidy.
                      opacity: entry.depth <= 2 ? 1 : 0,
                      child: _buildCard(entry),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Page dots: one per card, the current one drawn out into a pill. They
        // signal the deck is a stack and jump straight to a card when tapped.
        if (n > 1) _dots(context, n),
      ],
    );
  }

  Widget _dots(BuildContext context, int n) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < n; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _jumpTo(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: i == _front ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _front
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeckEntry {
  const _DeckEntry({required this.index, required this.depth});

  final int index;
  final int depth;
}

/// A rounded card outline with a shallow concave notch scooped out of the top
/// centre — the "pocket" a stacked wallet card sits in.
class WalletNotchBorder extends ShapeBorder {
  const WalletNotchBorder({
    this.radius = 26,
    this.notchWidth = 122,
    this.notchDepth = 16,
  });

  final double radius;
  final double notchWidth;
  final double notchDepth;

  Path _shape(Rect rect) {
    final r = radius;
    final cx = rect.center.dx;
    final nw = notchWidth;
    final nd = notchDepth;
    return Path()
      ..moveTo(rect.left + r, rect.top)
      ..lineTo(cx - nw / 2, rect.top)
      // concave dip: control below the top edge pulls the curve down by ~nd.
      ..quadraticBezierTo(cx, rect.top + nd * 2, cx + nw / 2, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + r), radius: Radius.circular(r))
      ..lineTo(rect.right, rect.bottom - r)
      ..arcToPoint(
        Offset(rect.right - r, rect.bottom),
        radius: Radius.circular(r),
      )
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(
        Offset(rect.left, rect.bottom - r),
        radius: Radius.circular(r),
      )
      ..lineTo(rect.left, rect.top + r)
      ..arcToPoint(Offset(rect.left + r, rect.top), radius: Radius.circular(r))
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _shape(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _shape(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => WalletNotchBorder(
    radius: radius * t,
    notchWidth: notchWidth * t,
    notchDepth: notchDepth * t,
  );
}
