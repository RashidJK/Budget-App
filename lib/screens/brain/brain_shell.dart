import 'package:flutter/material.dart';

import '../../theme.dart';

/// The Second Brain — a capture-first knowledge space for notes, tasks, journal
/// entries and links.
///
/// This is the Phase-1 skeleton: a branded home with type chips and an empty
/// state, enough to read well as a Spaces card and when zoomed in. The Inbox
/// feed, the data model and command-bar capture arrive in the next phases.
class BrainShell extends StatelessWidget {
  const BrainShell({super.key});

  /// The brain's identity colour — a violet, distinct from the budget green.
  static const accent = Color(0xFF6D5DF6);

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final bg = dark ? const Color(0xFF14131C) : const Color(0xFFF4F3FB);
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bubble_chart_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Second Brain',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _TypeChip('Notes', Icons.sticky_note_2_outlined, selected: true),
                  _TypeChip('Tasks', Icons.check_circle_outline),
                  _TypeChip('Journal', Icons.menu_book_outlined),
                  _TypeChip('Links', Icons.link_rounded),
                ],
              ),
              const Spacer(),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 42,
                      color: accent.withValues(alpha: 0.85),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Your second brain is empty',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: context.scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Capture is coming next — pinch back out any time\nto hop back to Budget.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.muted, fontSize: 14, height: 1.35),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip(this.label, this.icon, {this.selected = false});

  final String label;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final fill = selected
        ? BrainShell.accent.withValues(alpha: dark ? 0.28 : 0.14)
        : (dark ? const Color(0xFF232232) : Colors.white);
    final fg = selected ? BrainShell.accent : context.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected
              ? BrainShell.accent.withValues(alpha: 0.5)
              : context.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? BrainShell.accent : context.scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
