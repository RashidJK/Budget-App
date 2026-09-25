import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/brain_item.dart';
import '../../state/brain_state.dart';
import '../../theme.dart';
import 'brain_parser.dart';

/// Per-kind accent, shared with the inbox tiles.
Color brainKindColor(BrainKind k) => switch (k) {
  BrainKind.note => const Color(0xFF6D5DF6),
  BrainKind.task => const Color(0xFF2AA783),
  BrainKind.journal => const Color(0xFFCC8A2E),
  BrainKind.link => const Color(0xFF3B82D6),
};

IconData brainKindIcon(BrainKind k) => switch (k) {
  BrainKind.note => Icons.sticky_note_2_outlined,
  BrainKind.task => Icons.check_circle_outline,
  BrainKind.journal => Icons.menu_book_outlined,
  BrainKind.link => Icons.link_rounded,
};

/// The second brain's capture bar: type a thought and it routes to the right
/// kind. It guesses the kind live from what you type (a link, "todo …", etc.)
/// and highlights that pill; tap a pill to force a kind instead.
class BrainCommandBar extends StatefulWidget {
  const BrainCommandBar({super.key});

  @override
  State<BrainCommandBar> createState() => _BrainCommandBarState();
}

class _BrainCommandBarState extends State<BrainCommandBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// A kind the user tapped, which overrides the live guess until they clear.
  BrainKind? _forced;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_controller.text.isEmpty && _forced != null) _forced = null;
    setState(() {});
  }

  bool get _open => _focus.hasFocus || _controller.text.isNotEmpty;

  BrainKind get _activeKind {
    if (_forced != null) return _forced!;
    final text = _controller.text.trim();
    return text.isEmpty ? BrainKind.note : BrainParser.detect(text);
  }

  String get _hint => switch (_activeKind) {
    BrainKind.note => 'Capture a thought…',
    BrainKind.task => 'Add a task…  (try "tomorrow")',
    BrainKind.journal => "What's on your mind?",
    BrainKind.link => 'Save a link…',
  };

  Future<void> _submit() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    HapticFeedback.lightImpact();

    final parsed = BrainParser.parse(raw);
    // A forced pill wins over the guess, but the parser still supplies the URL
    // and due date it pulled out.
    final kind = _forced ?? parsed.kind;
    await context.read<BrainState>().capture(
      kind,
      parsed.text,
      url: kind == BrainKind.link ? (parsed.url ?? parsed.text) : null,
      dueDate: kind == BrainKind.task ? parsed.dueDate : null,
      tags: parsed.tags,
    );

    _controller.clear();
    _forced = null;
    _focus.unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final color = brainKindColor(_activeKind);
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 6, 14, (safeBottom > 0 ? safeBottom : 12)),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF201F2B) : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: context.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.34 : 0.08),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        for (final k in BrainKind.values) ...[
                          _KindPill(
                            kind: k,
                            active: _activeKind == k,
                            guessed: _forced == null && _activeKind == k,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _forced = k);
                            },
                          ),
                          if (k != BrainKind.values.last)
                            const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF201F2B) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _open ? color.withValues(alpha: 0.6) : context.hairline,
                      width: _open ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Icon(
                        _open ? brainKindIcon(_activeKind) : Icons.auto_awesome,
                        size: 18,
                        color: _open ? color : context.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: _hint,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _submit,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _controller.text.trim().isEmpty
                        ? context.hairline
                        : color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    color: _controller.text.trim().isEmpty
                        ? context.muted
                        : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({
    required this.kind,
    required this.active,
    required this.guessed,
    required this.onTap,
  });

  final BrainKind kind;
  final bool active;

  /// Active because the parser guessed it (not because the user tapped it) —
  /// shown with a subtle sparkle so the auto-detection is legible.
  final bool guessed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = brainKindColor(kind);
    final dark = context.isDark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: dark ? 0.30 : 0.14)
              : (dark ? const Color(0xFF201F2B) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.6) : context.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              guessed ? Icons.auto_awesome : brainKindIcon(kind),
              size: 13,
              color: active ? color : context.muted,
            ),
            const SizedBox(width: 5),
            Text(
              kind.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: active ? color : context.scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
