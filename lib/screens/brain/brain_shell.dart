import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/brain_item.dart';
import '../../state/brain_state.dart';
import '../../theme.dart';
import 'brain_command_bar.dart';
import 'brain_detail_sheet.dart';

/// The Second Brain — a capture-first inbox for notes, tasks, journal entries
/// and links. One feed interleaves every kind, newest first; the chips filter
/// it; the ✨ command bar at the bottom captures and routes a new thought.
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

  bool _searching = false;
  final _searchCtrl = TextEditingController();

  String get _query => _searchCtrl.text.trim().toLowerCase();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _header(BuildContext context) {
    if (_searching) {
      final dark = context.isDark;
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search your brain…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: dark ? const Color(0xFF201F2B) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(23),
                  borderSide: BorderSide(color: context.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(23),
                  borderSide: BorderSide(color: context.hairline),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() {
              _searching = false;
              _searchCtrl.clear();
            }),
          ),
        ],
      );
    }
    return Row(
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
        const Expanded(
          child: Text(
            'Second Brain',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.search_rounded),
          color: context.muted,
          onPressed: () => setState(() => _searching = true),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final bg = dark ? const Color(0xFF14131C) : const Color(0xFFF4F3FB);
    final brain = context.watch<BrainState>();
    final base = brain.ofKind(_filter);
    final items = _query.isEmpty
        ? base
        : base
              .where(
                (i) =>
                    i.text.toLowerCase().contains(_query) ||
                    (i.url?.toLowerCase().contains(_query) ?? false) ||
                    i.tags.any((t) => t.toLowerCase().contains(_query)),
              )
              .toList();

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SizedBox(height: 46, child: _header(context)),
            ),
            const SizedBox(height: 16),
            _FilterBar(
              selected: _filter,
              counts: {for (final k in BrainKind.values) k: brain.countOf(k)},
              onSelect: (k) => setState(() => _filter = k),
            ),
            const SizedBox(height: 8),
            if (_filter == null && _query.isEmpty) ...[
              Builder(
                builder: (context) {
                  final resurfaced = brain.resurfaced();
                  return resurfaced.isEmpty
                      ? const SizedBox.shrink()
                      : _ResurfaceStrip(items: resurfaced);
                },
              ),
            ],
            Expanded(
              child: brain.isEmpty
                  ? const _EmptyState()
                  : items.isEmpty
                  ? (_query.isNotEmpty
                        ? _NoMatches(query: _searchCtrl.text.trim())
                        : _EmptyFilter(kind: _filter!))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _BrainTile(item: items[i]),
                    ),
            ),
            const BrainCommandBar(),
          ],
        ),
      ),
    );
  }
}

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
              color: brainKindColor(k),
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
      child: GestureDetector(
        onTap: () => showBrainDetail(context, item),
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
      ),
    );
  }

  Widget _leading(BuildContext context, BrainState brain) {
    final color = brainKindColor(item.kind);
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
      child: Icon(brainKindIcon(item.kind), size: 17, color: color),
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
    final color = overdue ? context.warn : brainKindColor(BrainKind.task);
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
              'Type a thought below — a link, "todo …", "journal: …"\nor anything else — and it files itself.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.muted, fontSize: 14, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 34, color: context.muted),
            const SizedBox(height: 10),
            Text(
              'No matches for "$query"',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.muted, fontSize: 15),
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
          Icon(brainKindIcon(kind), size: 34, color: context.muted),
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

// --- resurface strip --------------------------------------------------------

class _ResurfaceStrip extends StatelessWidget {
  const _ResurfaceStrip({required this.items});

  final List<BrainItem> items;

  @override
  Widget build(BuildContext context) {
    final brain = context.read<BrainState>();
    final accent = BrainShell.accent;
    final dark = context.isDark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: dark ? 0.16 : 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: accent),
              const SizedBox(width: 7),
              Text(
                'Worth another look',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.hairline),
            _ResurfaceRow(item: items[i], brain: brain),
          ],
        ],
      ),
    );
  }
}

class _ResurfaceRow extends StatelessWidget {
  const _ResurfaceRow({required this.item, required this.brain});

  final BrainItem item;
  final BrainState brain;

  @override
  Widget build(BuildContext context) {
    final color = brainKindColor(item.kind);
    return InkWell(
      onTap: () => showBrainDetail(context, item),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(brainKindIcon(item.kind), size: 15, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.text.isEmpty ? '(empty)' : item.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: context.scheme.onSurface),
              ),
            ),
            const SizedBox(width: 4),
            _mini(context, Icons.push_pin_outlined, 'Keep', () {
              HapticFeedback.selectionClick();
              brain.togglePinned(item.id);
            }),
            _mini(context, Icons.close_rounded, 'Dismiss',
                () => brain.dismissResurface(item.id)),
          ],
        ),
      ),
    );
  }

  Widget _mini(
    BuildContext context,
    IconData icon,
    String tip,
    VoidCallback onTap,
  ) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      iconSize: 18,
      color: context.muted,
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon),
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
