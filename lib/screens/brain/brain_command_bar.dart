import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/brain_item.dart';
import '../../state/brain_state.dart';
import '../../theme.dart';
import 'shift/cards/shift_cards.dart';
import 'shift/parse/cards.dart';
import 'shift/shift_classifier.dart';
import 'shift/shift_decide.dart';
import 'shift/shift_intent.dart';
import 'shift/shift_registry.dart';
import 'shift/shift_signals.dart';

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

/// The second brain's capture bar — a Shapeshift-style morphing input. As you
/// type, an offline classifier guesses what you mean and the bar grows a live
/// preview card (an event, a checklist, a split, a colour…). Enter saves it to
/// the right place; the sparkle opens a palette to force any card type.
class BrainCommandBar extends StatefulWidget {
  const BrainCommandBar({super.key, this.focusNode, this.previewBelow = false});

  /// Optional external focus node so the shell can focus capture from a `/`
  /// or `n` shortcut. When null the bar owns its own.
  final FocusNode? focusNode;

  /// Render the live preview under the input (web/desktop inline composer)
  /// rather than above it (the phone bottom island).
  final bool previewBelow;

  @override
  State<BrainCommandBar> createState() => _BrainCommandBarState();
}

class _BrainCommandBarState extends State<BrainCommandBar> {
  final _controller = TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  late final bool _ownsFocus = widget.focusNode == null;

  DecideMemory _mem = initialMemory;
  GatedSignals _gated = const GatedSignals();

  static final _tagRe = RegExp(r'(?:^|\s)#([\w-]+)');
  static final _hexRe = RegExp(
    r'^[0-9a-f]{3}$|^[0-9a-f]{6}$',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _focus.addListener(() => setState(() {}));
    _focus.onKeyEvent = _onKey;
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_ownsFocus) {
      _focus.dispose();
    } else {
      _focus.onKeyEvent = null;
    }
    super.dispose();
  }

  /// Keyboard shortcuts while the capture field is focused.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_controller.text.isNotEmpty) {
        _controller.clear();
        _mem = initialMemory;
        _gated = const GatedSignals();
        setState(() {});
      } else {
        _focus.unfocus();
      }
      return KeyEventResult.handled;
    }
    final ui = _mem.ui;
    // ← / → pick between the two "did you mean" pills.
    if (ui is ChooseState) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _force(ui.a);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _force(ui.b);
        return KeyEventResult.handled;
      }
    }
    // Tab keeps a faint ghost preview without locking it.
    if (ui is GhostState && key == LogicalKeyboardKey.tab) {
      setState(() => _mem = promote(_mem));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _force(ShiftIntent intent) {
    final (cleaned, _) = _split(_controller.text);
    setState(() => _mem = force(intent, cleaned));
  }

  // The inline top composer is always expanded; the bottom island collapses
  // to a compact pill until focused.
  bool get _open =>
      widget.previewBelow || _focus.hasFocus || _controller.text.isNotEmpty;

  /// Pull #tags out (but never a #hex colour), returning the cleaned text.
  (String, List<String>) _split(String raw) {
    final tags = <String>{};
    for (final m in _tagRe.allMatches(raw)) {
      final g = m.group(1)!;
      if (!_hexRe.hasMatch(g)) tags.add(g.toLowerCase());
    }
    if (tags.isEmpty) return (raw.trim(), const []);
    final cleaned = raw
        .replaceAllMapped(
          _tagRe,
          (m) => _hexRe.hasMatch(m.group(1)!) ? m.group(0)! : ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return (cleaned, tags.toList());
  }

  void _onChanged() {
    if (_controller.text == '/') {
      _controller.clear();
      _openPalette();
      return;
    }
    final (cleaned, _) = _split(_controller.text);
    final result = classify(cleaned);
    _mem = decide(_mem, result, cleaned);
    final active = activeIntent(_mem.ui);
    _gated = active != null
        ? gateSignals(_gated, result.signals, shiftUsedSignals(active))
        : const GatedSignals();
    setState(() {});
  }

  ShiftIntent _submitIntent(String cleaned) {
    final a = activeIntent(_mem.ui);
    if (a != null) return a;
    final ui = _mem.ui;
    if (ui is ChooseState) return ui.a;
    final top = classify(cleaned).intent.value;
    return top.isCard ? top : ShiftIntent.note;
  }

  Future<void> _submit() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    HapticFeedback.lightImpact();

    final (cleaned, tags) = _split(raw);
    final intent = _submitIntent(cleaned);
    final data = shiftParse(intent, cleaned, colorMood: _gated.colorMood);
    final (kind, text, url, due) = _toCapture(intent, data, cleaned);

    final brain = context.read<BrainState>();
    final item = await brain.capture(
      kind,
      text,
      url: url,
      dueDate: due,
      tags: tags,
    );
    if (kind == BrainKind.link) {
      // Fire-and-forget: fetch the link's title/cover for the feed card.
      brain.enrichLink(item.id);
    }

    _controller.clear();
    _mem = initialMemory;
    _gated = const GatedSignals();
    _focus.unfocus();
    setState(() {});
  }

  /// Map a resolved card to a stored Brain item. Dates become task due dates;
  /// links stay links; the computed cards (split, calc, colour…) land as a note
  /// with their one-line summary so the feed reads cleanly.
  (BrainKind, String, String?, DateTime?) _toCapture(
    ShiftIntent intent,
    dynamic data,
    String cleaned,
  ) {
    switch (intent) {
      case ShiftIntent.link:
        final d = data as LinkData;
        return (
          BrainKind.link,
          d.note.isNotEmpty ? d.note : (d.domain ?? cleaned),
          d.url ?? cleaned,
          null,
        );
      case ShiftIntent.event:
        final d = data as EventData;
        return (
          BrainKind.task,
          d.title.isEmpty ? 'Event' : d.title,
          null,
          d.date,
        );
      case ShiftIntent.reminder:
        final d = data as ReminderData;
        return (
          BrainKind.task,
          d.task.isEmpty ? 'Reminder' : d.task,
          null,
          d.when,
        );
      case ShiftIntent.countdown:
        final d = data as CountdownData;
        return (
          BrainKind.task,
          d.title.isEmpty ? 'Countdown' : d.title,
          null,
          d.date,
        );
      case ShiftIntent.travel:
        final d = data as TravelData;
        return (
          BrainKind.task,
          d.destination != null ? 'Trip to ${d.destination}' : 'Trip',
          null,
          d.start,
        );
      case ShiftIntent.todo:
        final d = data as TodoData;
        return (
          BrainKind.task,
          d.items.isEmpty ? cleaned : d.items.join(', '),
          null,
          null,
        );
      case ShiftIntent.habit:
        final d = data as HabitData;
        return (
          BrainKind.task,
          [
            d.title,
            d.label,
          ].where((e) => e != null && e.isNotEmpty).join(' · '),
          null,
          null,
        );
      case ShiftIntent.note:
      case ShiftIntent.none:
        // Preserve the journal prefix the old parser understood.
        final j = RegExp(
          r'^(?:journal|diary|log)\s*:\s*|^dear diary[,:]?\s*',
          caseSensitive: false,
        ).firstMatch(cleaned);
        if (j != null) {
          return (BrainKind.journal, cleaned.substring(j.end).trim(), null, null);
        }
        return (BrainKind.note, cleaned, null, null);
      default:
        return (BrainKind.note, shiftSummary(intent, data), null, null);
    }
  }

  void _openPalette() {
    _focus.unfocus();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.card,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(
                'Make a card',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.scheme.onSurface,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final i in ShiftIntent.cards)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: i.accent.withValues(alpha: 0.16),
                        child: Icon(i.icon, size: 18, color: i.accent),
                      ),
                      title: Text(
                        i.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        i.example,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.pop(sheet);
                        final (cleaned, _) = _split(_controller.text);
                        setState(() => _mem = force(i, cleaned));
                        _focus.requestFocus();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildPreview() {
    if (!_open) return null;
    final (cleaned, _) = _split(_controller.text);
    final ui = _mem.ui;
    final now = DateTime.now();

    Widget card(ShiftIntent intent, {required bool interactive}) {
      final data = shiftParse(
        intent,
        cleaned,
        ref: now,
        colorMood: _gated.colorMood,
      );
      return buildShiftCard(
        context,
        intent,
        data,
        _gated,
        interactive: interactive,
        now: now,
      );
    }

    switch (ui) {
      case CommittedState(:final intent):
        return KeyedSubtree(
          key: ValueKey('c_${intent.name}'),
          child: card(intent, interactive: true),
        );
      case GhostState(:final intent):
        return KeyedSubtree(
          key: ValueKey('g_${intent.name}'),
          child: Opacity(
            opacity: 0.62,
            child: card(intent, interactive: false),
          ),
        );
      case ChooseState(:final a, :final b):
        return KeyedSubtree(
          key: ValueKey('choose_${a.name}_${b.name}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(opacity: 0.62, child: card(a, interactive: false)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Did you mean',
                    style: TextStyle(fontSize: 12.5, color: context.muted),
                  ),
                  const SizedBox(width: 8),
                  _ChoosePill(a, onTap: () => _force(a)),
                  const SizedBox(width: 6),
                  _ChoosePill(b, onTap: () => _force(b)),
                ],
              ),
            ],
          ),
        );
      case InputState():
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final active = activeIntent(_mem.ui);
    final accent = active?.accent ?? context.scheme.primary;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final preview = _buildPreview();
    final hasText = _controller.text.trim().isNotEmpty;
    final below = widget.previewBelow;

    final previewArea = AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
      child: preview == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: EdgeInsets.only(
                top: below ? 10 : 0,
                bottom: below ? 0 : 10,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween(begin: 0.96, end: 1.0).animate(anim),
                        child: child,
                      ),
                    ),
                    child: preview,
                  ),
                ),
              ),
            ),
    );

    final inputRow = Row(
      children: [
        // The sparkle reflects the detected card, and opens the palette to
        // force any type by hand.
        GestureDetector(
          onTap: _openPalette,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              active?.icon ?? Icons.auto_awesome,
              size: 20,
              color: _open ? accent : context.muted,
            ),
          ),
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
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'Capture anything…',
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: _submit,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: hasText ? accent : context.hairline,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        color: hasText ? Colors.white : context.muted,
                      ),
                    ),
                  ),
                )
              : const SizedBox(height: 44),
        ),
      ],
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        _open ? 14 : 44,
        6,
        _open ? 14 : 44,
        below ? 6 : (safeBottom > 0 ? safeBottom : 12),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF201F2B) : Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: _open ? accent.withValues(alpha: 0.6) : context.hairline,
            width: _open ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              // Flatter when inline on top (reads like a page); the floating
              // bottom island keeps its lift.
              color: Colors.black.withValues(
                alpha: dark ? (below ? 0.22 : 0.34) : (below ? 0.05 : 0.08),
              ),
              blurRadius: below ? 14 : 22,
              offset: Offset(0, below ? 6 : 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: below ? [inputRow, previewArea] : [previewArea, inputRow],
        ),
      ),
    );
  }
}

class _ChoosePill extends StatelessWidget {
  const _ChoosePill(this.intent, {required this.onTap});
  final ShiftIntent intent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: intent.accent.withValues(alpha: context.isDark ? 0.28 : 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: intent.accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(intent.icon, size: 13, color: intent.accent),
            const SizedBox(width: 5),
            Text(
              intent.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: intent.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
