import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/brain_item.dart';
import '../../state/brain_state.dart';
import '../../theme.dart';

/// The Second Brain — a capture-first inbox for notes, tasks, journal entries
/// and links. One feed interleaves every kind, newest first; the chips filter
/// it; the bar at the bottom captures a new thought.
class BrainShell extends StatefulWidget {
  const BrainShell({super.key});

  /// The brain's identity colour — a violet, distinct from the budget green.
  static const accent = Color(0xFF6D5DF6);

  @override
  State<BrainShell> createState() => _BrainShellState();
}

class _BrainShellState extends State<BrainShell> {
  // null = "All".
  BrainKind? _filter;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final bg = dark ? const Color(0xFF14131C) : const Color(0xFFF4F3FB);
    final brain = context.watch<BrainState>();
    final items = brain.ofKind(_filter);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: BrainShell.accent,
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
            ),
            const SizedBox(height: 16),
            _FilterBar(
              selected: _filter,
              counts: {
                for (final k in BrainKind.values) k: brain.countOf(k),
              },
              onSelect: (k) => setState(() => _filter = k),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: brain.isEmpty
                  ? const _EmptyState()
                  : items.isEmpty
                  ? _EmptyFilter(kind: _filter!)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _BrainTile(item: items[i]),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _CaptureBar(
        onTap: () => _openCompose(context, _filter ?? BrainKind.note),
      ),
    );
  }
}

// --- kind visuals -----------------------------------------------------------

IconData _iconFor(BrainKind k) => switch (k) {
  BrainKind.note => Icons.sticky_note_2_outlined,
  BrainKind.task => Icons.check_circle_outline,
  BrainKind.journal => Icons.menu_book_outlined,
  BrainKind.link => Icons.link_rounded,
};

Color _colorFor(BrainKind k) => switch (k) {
  BrainKind.note => BrainShell.accent,
  BrainKind.task => const Color(0xFF2AA783),
  BrainKind.journal => const Color(0xFFCC8A2E),
  BrainKind.link => const Color(0xFF3B82D6),
};

// --- filter chips -----------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final BrainKind? selected;
  final Map<BrainKind, int> counts;
  final ValueChanged<BrainKind?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _chip(context, label: 'All', active: selected == null, onTap: () => onSelect(null)),
          for (final k in BrainKind.values) ...[
            const SizedBox(width: 8),
            _chip(
              context,
              label: '${k.label}s',
              count: counts[k] ?? 0,
              color: _colorFor(k),
              active: selected == k,
              onTap: () => onSelect(k),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool active,
    required VoidCallback onTap,
    int? count,
    Color? color,
  }) {
    final dark = context.isDark;
    final tint = color ?? BrainShell.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? tint.withValues(alpha: dark ? 0.30 : 0.14)
              : (dark ? const Color(0xFF232232) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? tint.withValues(alpha: 0.55) : context.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? tint : context.scheme.onSurface,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? tint : context.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- one item ---------------------------------------------------------------

class _BrainTile extends StatelessWidget {
  const _BrainTile({required this.item});

  final BrainItem item;

  @override
  Widget build(BuildContext context) {
    final brain = context.read<BrainState>();
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: context.warn.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(Icons.delete_outline_rounded, color: context.warn),
      ),
      onDismissed: (_) {
        brain.remove(item.id);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${item.kind.label} deleted'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => brain.restore(item.id),
              ),
            ),
          );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF201F2B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _leading(context, brain),
            const SizedBox(width: 12),
            Expanded(child: _body(context)),
            if (item.pinned)
              Icon(Icons.push_pin_rounded, size: 15, color: context.muted),
          ],
        ),
      ),
    );
  }

  Widget _leading(BuildContext context, BrainState brain) {
    final color = _colorFor(item.kind);
    if (item.kind == BrainKind.task) {
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          brain.toggleDone(item.id);
        },
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: item.done ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: item.done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : null,
        ),
      );
    }
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(_iconFor(item.kind), size: 17, color: color),
    );
  }

  Widget _body(BuildContext context) {
    final muted = context.muted;
    final subtitle = switch (item.kind) {
      BrainKind.link => item.url,
      BrainKind.journal => _dayLabel(item.createdAt),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.text.isEmpty ? '(empty)' : item.text,
          style: TextStyle(
            fontSize: 15,
            height: 1.3,
            color: context.scheme.onSurface,
            decoration: item.done ? TextDecoration.lineThrough : null,
            decorationColor: muted,
          ),
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: muted),
          ),
        ],
        if (item.kind == BrainKind.task && item.dueDate != null) ...[
          const SizedBox(height: 6),
          _DueChip(due: item.dueDate!),
        ],
      ],
    );
  }
}

class _DueChip extends StatelessWidget {
  const _DueChip({required this.due});

  final DateTime due;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final overdue = due.isBefore(DateTime(now.year, now.month, now.day));
    final color = overdue ? context.warn : _colorFor(BrainKind.task);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_rounded, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            _dayLabel(due),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// --- capture bar + compose --------------------------------------------------

class _CaptureBar extends StatelessWidget {
  const _CaptureBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          width: MediaQuery.of(context).size.width - 40,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: BrainShell.accent,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: BrainShell.accent.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: const [
              Icon(Icons.add_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'Capture a thought…',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Spacer(),
              Icon(Icons.auto_awesome, color: Colors.white70, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openCompose(BuildContext context, BrainKind initial) async {
  HapticFeedback.lightImpact();
  final brain = context.read<BrainState>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider<BrainState>.value(
      value: brain,
      child: _ComposeSheet(initial: initial),
    ),
  );
}

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet({required this.initial});

  final BrainKind initial;

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  late BrainKind _kind = widget.initial;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _hint => switch (_kind) {
    BrainKind.note => 'Jot a note…',
    BrainKind.task => 'What needs doing?',
    BrainKind.journal => "What's on your mind today?",
    BrainKind.link => 'Paste a link…',
  };

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final brain = context.read<BrainState>();
    await brain.capture(
      _kind,
      text,
      url: _kind == BrainKind.link ? text : null,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1B1A24) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: context.hairline,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final k in BrainKind.values)
                  _KindPick(
                    kind: k,
                    selected: _kind == k,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _kind = k);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              minLines: 1,
              maxLines: 5,
              textCapitalization: _kind == BrainKind.link
                  ? TextCapitalization.none
                  : TextCapitalization.sentences,
              keyboardType: _kind == BrainKind.link
                  ? TextInputType.url
                  : TextInputType.multiline,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: _hint,
                filled: true,
                fillColor: dark ? const Color(0xFF232232) : const Color(0xFFF3F2FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _colorFor(_kind),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text('Add ${_kind.label.toLowerCase()}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindPick extends StatelessWidget {
  const _KindPick({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final BrainKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(kind);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.6) : context.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(kind), size: 16, color: selected ? color : context.muted),
            const SizedBox(width: 6),
            Text(
              kind.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? color : context.scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- empty states -----------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 42,
              color: BrainShell.accent.withValues(alpha: 0.85),
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
              'Capture a note, task, journal entry or link\nwith the bar below.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.muted, fontSize: 14, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFilter extends StatelessWidget {
  const _EmptyFilter({required this.kind});

  final BrainKind kind;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(kind), size: 34, color: context.muted),
          const SizedBox(height: 10),
          Text(
            'No ${kind.label.toLowerCase()}s yet',
            style: TextStyle(color: context.muted, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = that.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}
