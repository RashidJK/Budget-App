import 'package:flutter/material.dart';

/// A short deck of cards shown stacked, with the ones behind peeking a little
/// above the front card. Swipe **up** on the front card (or tap a peeking one)
/// to bring the next card forward; swipe down to go back.
///
/// The front card is fully interactive — taps on its buttons pass straight
/// through; only a deliberate vertical fling changes the card.
class CardStack extends StatefulWidget {
  const CardStack({
    super.key,
    required this.cards,
    required this.height,
    this.peek = 12,
    this.initialIndex = 0,
  });

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

  void _advance(int direction) {
    final n = widget.cards.length;
    if (n < 2) return;
    setState(() => _front = (_front + direction) % n);
    if (_front < 0) _front += n;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.cards.length;
    final maxDepth = n - 1;
    // The topmost peek sits `maxDepth * peek` above the front card, so reserve
    // that much headroom.
    final reserved = maxDepth * widget.peek;

    // Order back-to-front so the front card paints last (on top).
    final entries = <_DeckEntry>[];
    for (var i = 0; i < n; i++) {
      final depth = (i - _front) % n;
      entries.add(_DeckEntry(index: i, depth: depth < 0 ? depth + n : depth));
    }
    entries.sort((a, b) => b.depth.compareTo(a.depth));

    return SizedBox(
      height: widget.height + reserved,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final entry in entries)
            AnimatedPositioned(
              key: ValueKey(entry.index),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              top: (maxDepth - entry.depth) * widget.peek,
              left: 0,
              right: 0,
              height: widget.height,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                scale: 1 - entry.depth * 0.04,
                alignment: Alignment.topCenter,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 320),
                  // Cards more than two deep fade out so a long deck stays tidy.
                  opacity: entry.depth <= 2 ? 1 : 0,
                  child: entry.depth == 0
                      // Front card: swipe to change, buttons still tappable.
                      ? GestureDetector(
                          behavior: HitTestBehavior.deferToChild,
                          onVerticalDragEnd: (details) {
                            final v = details.primaryVelocity ?? 0;
                            if (v < -200) {
                              _advance(1); // fling up → next
                            } else if (v > 200) {
                              _advance(-1); // fling down → previous
                            }
                          },
                          child: widget.cards[entry.index],
                        )
                      // A peeking card: tap it to pull it forward.
                      : GestureDetector(
                          onTap: () => _advance(1),
                          child: widget.cards[entry.index],
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
