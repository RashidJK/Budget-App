import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/expense.dart';
import '../../services/format.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

/// Filter editor for the expense list.
///
/// Edits a working copy and only returns it on Apply, so backing out leaves
/// the list exactly as it was.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial});

  final ExpenseFilter initial;

  static Future<ExpenseFilter?> show(
    BuildContext context,
    ExpenseFilter initial,
  ) {
    return showModalBottomSheet<ExpenseFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(initial: initial),
    );
  }

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late ExpenseFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _draft.from != null && _draft.to != null
          ? DateTimeRange(start: _draft.from!, end: _draft.to!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _draft = _draft.copyWith(from: picked.start, to: picked.end);
      });
    }
  }

  void _toggleCategory(String id) {
    final next = Set<String>.of(_draft.categoryIds);
    if (!next.remove(id)) next.add(id);
    setState(() => _draft = _draft.copyWith(categoryIds: next));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Filters', style: theme.textTheme.titleLarge),
                const Spacer(),
                if (_draft.activeCount > 0)
                  TextButton(
                    onPressed: () => setState(() {
                      // The text query lives in the search field, not here, so
                      // clearing filters must not wipe what the user typed.
                      _draft = ExpenseFilter(query: _draft.query);
                    }),
                    child: const Text('Clear all'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              label: 'Profile',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _draft.profileId == null,
                    showCheckmark: false,
                    onSelected: (_) => setState(
                      () => _draft = _draft.copyWith(clearProfile: true),
                    ),
                    shape: _chipShape(context),
                  ),
                  for (final profile in state.profiles)
                    ChoiceChip(
                      label: Text(profile.name),
                      avatar: Icon(
                        profile.icon,
                        size: 16,
                        color: profile.of(context),
                      ),
                      selected: _draft.profileId == profile.id,
                      showCheckmark: false,
                      onSelected: (_) => setState(
                        () => _draft = _draft.copyWith(profileId: profile.id),
                      ),
                      shape: _chipShape(context),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _Section(
              label: _draft.categoryIds.isEmpty
                  ? 'Categories'
                  : 'Categories (${_draft.categoryIds.length})',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in state.categories)
                    FilterChip(
                      label: Text(category.name),
                      avatar: Icon(
                        category.icon,
                        size: 16,
                        color: category.of(context),
                      ),
                      selected: _draft.categoryIds.contains(category.id),
                      showCheckmark: false,
                      onSelected: (_) => _toggleCategory(category.id),
                      shape: _chipShape(context),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _Section(
              label: 'Date range',
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range_rounded, size: 18),
                      label: Text(
                        _draft.from == null || _draft.to == null
                            ? 'Any date'
                            : '${Dates.short(_draft.from!)} – '
                                  '${Dates.short(_draft.to!)}',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  if (_draft.from != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => setState(
                        () => _draft = _draft.copyWith(clearDates: true),
                      ),
                      tooltip: 'Clear dates',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_draft),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  OutlinedBorder _chipShape(BuildContext context) => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    side: BorderSide(color: context.hairline),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: context.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}
