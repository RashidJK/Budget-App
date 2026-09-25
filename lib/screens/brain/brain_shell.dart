import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/brain_item.dart';
import '../../state/brain_state.dart';
import '../../theme.dart';
import 'brain_calendar.dart';
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
  BrainKind? _filter; // null = "All"
  DateTime? _dayFilter; // a chosen calendar day, null = the whole week
  bool _mosaic = false; // list vs. bento mosaic feed

  bool _searching = false;
  final _searchCtrl = TextEditingController();

  String get _query => _searchCtrl.text.trim().toLowerCase();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _onDay(BrainItem i, DateTime d) {
    bool eq(DateTime a) => a.year == d.year && a.month == d.month && a.day == d.day;
    return eq(i.createdAt) || (i.dueDate != null && eq(i.dueDate!));
  }

  void _openTag(String t) => setState(() {
    _searching = true;
    _searchCtrl.text = t;
  });

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
          width: 44,
          height: 44,
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
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hi there',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.muted,
                ),
              ),
              const Text(
                'Second Brain',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        _ButtonPair(
          mosaic: _mosaic,
          onSearch: () => setState(() => _searching = true),
          onToggle: () => setState(() => _mosaic = !_mosaic),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final bg = dark ? const Color(0xFF14131C) : const Color(0xFFF4F3FB);
    final brain = context.watch<BrainState>();

    var items = brain.ofKind(_filter);
    if (_query.isNotEmpty) {
      items = items
          .where(
            (i) =>
                i.text.toLowerCase().contains(_query) ||
                (i.url?.toLowerCase().contains(_query) ?? false) ||
                i.tags.any((t) => t.toLowerCase().contains(_query)),
          )
          .toList();
    }
    if (_dayFilter != null) {
      items = items.where((i) => _onDay(i, _dayFilter!)).toList();
    }

    final showResurface =
        _filter == null && _query.isEmpty && _dayFilter == null;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopIsland(
              child: Column(
                children: [
                  _header(context),
                  const SizedBox(height: 12),
                  BrainCalendar(
                    selected: _dayFilter,
                    onSelect: (d) => setState(() => _dayFilter = d),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FilterBar(
              selected: _filter,
              counts: {for (final k in BrainKind.values) k: brain.countOf(k)},
              onSelect: (k) => setState(() => _filter = k),
            ),
            const SizedBox(height: 8),
            if (showResurface)
              Builder(
                builder: (context) {
                  final r = brain.resurfaced();
                  return r.isEmpty
                      ? const SizedBox.shrink()
                      : _ResurfaceStrip(items: r);
                },
              ),
            Expanded(child: _feed(context, brain, items)),
            const BrainCommandBar(),
          ],
        ),
      ),
    );
  }

  Widget _feed(BuildContext context, BrainState brain, List<BrainItem> items) {
    if (brain.isEmpty) return const _EmptyState();
    if (items.isEmpty) {
      if (_query.isNotEmpty) return _NoMatches(query: _searchCtrl.text.trim());
      if (_dayFilter != null) return _EmptyDay(date: _dayFilter!);
      return _EmptyFilter(kind: _filter!);
    }
    if (_mosaic) return _MosaicFeed(items: items, onTag: _openTag);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: items.length,
      itemBuilder: (context, i) => _BrainTile(item: items[i], onTag: _openTag),
    );
  }
}

// --- top island + button pair -----------------------------------------------

class _TopIsland extends StatelessWidget {
  const _TopIsland({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF201F2B) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.30 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The paired dark buttons in the header island — search and list/mosaic view.
class _ButtonPair extends StatelessWidget {
  const _ButtonPair({
    required this.mosaic,
    required this.onSearch,
    required this.onToggle,
  });

  final bool mosaic;
  final VoidCallback onSearch;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final pill = context.isDark ? const Color(0xFF35333F) : const Color(0xFF1C1B24);
    return Container(
      decoration: BoxDecoration(
        color: pill,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _half(Icons.search_rounded, onSearch),
          Container(width: 1, height: 20, color: Colors.white.withValues(alpha: 0.16)),
          _half(mosaic ? Icons.view_agenda_outlined : Icons.grid_view_rounded, onToggle),
        ],
      ),
    );
  }

  Widget _half(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// --- mosaic (bento) feed ----------------------------------------------------

class _MosaicFeed extends StatelessWidget {
  const _MosaicFeed({required this.items, required this.onTag});

  final List<BrainItem> items;
  final ValueChanged<String> onTag;

  // A rough height estimate so the greedy two-column split balances.
  double _estimate(BrainItem i) {
    var h = 74.0;
    h += (i.text.length / 16).ceil() * 20;
    if (i.kind == BrainKind.link && (i.url?.isNotEmpty ?? false)) h += 20;
    if (i.kind == BrainKind.journal) h += 18;
    if (i.kind == BrainKind.task && i.dueDate != null) h += 26;
    if (i.tags.isNotEmpty) h += 26;
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final left = <Widget>[];
    final right = <Widget>[];
    var lh = 0.0;
    var rh = 0.0;
    for (final item in items) {
      final card = Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _MosaicCard(item: item, onTag: onTag),
      );
      if (lh <= rh) {
        left.add(card);
        lh += _estimate(item);
      } else {
        right.add(card);
        rh += _estimate(item);
      }
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: left)),
          const SizedBox(width: 12),
          Expanded(child: Column(children: right)),
        ],
      ),
    );
  }
}

class _MosaicCard extends StatelessWidget {
  const _MosaicCard({required this.item, required this.onTag});

  final BrainItem item;
  final ValueChanged<String> onTag;

  @override
  Widget build(BuildContext context) {
    final color = brainKindColor(item.kind);
    final dark = context.isDark;
    return GestureDetector(
      onTap: () => showBrainDetail(context, item),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.20 : 0.11),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (item.kind == BrainKind.task)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.read<BrainState>().toggleDone(item.id);
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: item.done ? color : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 2),
                      ),
                      child: item.done
                          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                          : null,
                    ),
                  )
                else
                  Icon(brainKindIcon(item.kind), size: 18, color: color),
                const Spacer(),
                if (item.pinned)
                  Icon(Icons.push_pin_rounded, size: 13, color: color),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.text.isEmpty ? '(empty)' : item.text,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: context.scheme.onSurface,
                decoration: item.done ? TextDecoration.lineThrough : null,
                decorationColor: context.muted,
              ),
            ),
            if (item.kind == BrainKind.link && (item.url?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 6),
              Text(
                item.url!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: context.muted),
              ),
            ],
            if (item.kind == BrainKind.journal) ...[
              const SizedBox(height: 6),
              Text(
                _dayLabel(item.createdAt),
                style: TextStyle(fontSize: 12, color: context.muted),
              ),
            ],
            if (item.kind == BrainKind.task && item.dueDate != null) ...[
              const SizedBox(height: 8),
              _DueChip(due: item.dueDate!),
            ],
            if (item.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final t in item.tags)
                    _TagChip(tag: t, onTap: () => onTag(t)),
                ],
              ),
            ],
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
  const _BrainTile({required this.item, this.onTag});

  final BrainItem item;
  final ValueChanged<String>? onTag;

  @override
  Widget build(BuildContext context) {
    final brain = context.read<BrainState>();
    final isTask = item.kind == BrainKind.task;
    final keepColor = isTask ? brainKindColor(BrainKind.task) : BrainShell.accent;
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.horizontal,
      // Swipe right: complete a task, or pin anything else.
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: keepColor.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          isTask ? Icons.check_circle_rounded : Icons.push_pin_rounded,
          color: keepColor,
        ),
      ),
      // Swipe left: delete.
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: context.warn.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(Icons.delete_outline_rounded, color: context.warn),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          HapticFeedback.selectionClick();
          isTask ? brain.toggleDone(item.id) : brain.togglePinned(item.id);
          return false; // keep the row; the swipe was an action, not a delete
        }
        return true;
      },
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
        if (item.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final t in item.tags)
                _TagChip(tag: t, onTap: onTag == null ? null : () => onTag!(t)),
            ],
          ),
        ],
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag, this.onTap});

  final String tag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = BrainShell.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: context.isDark ? 0.22 : 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '#$tag',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
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

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available_rounded, size: 34, color: context.muted),
          const SizedBox(height: 10),
          Text(
            'Nothing on ${_dayLabel(date)}',
            style: TextStyle(color: context.muted, fontSize: 15),
          ),
        ],
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
