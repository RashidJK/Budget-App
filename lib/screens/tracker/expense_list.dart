import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';

import '../../models/activity.dart';
import '../../models/category_fields.dart';
import '../../models/expense.dart';
import '../../services/format.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/inputs.dart';
import 'add_expense.dart';
import 'edit_activity.dart';
import 'filter_sheet.dart';
import 'metadata_sheet.dart';

/// Every recorded expense, newest first, grouped by day, with search and
/// filtering.
class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  late final TextEditingController _search;
  ExpenseFilter _filter = const ExpenseFilter();

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final result = await FilterSheet.show(context, _filter);
    if (result != null) setState(() => _filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final matches = state.search(_filter);
    // History interleaves expenses with income / transfers / loans (spec §33).
    // Filtering is expense-oriented, so activities appear only in the default
    // (unfiltered) view.
    final entries = <_Entry>[for (final e in matches) _Entry.expense(e)];
    if (!_filter.isActive) {
      entries.addAll([
        for (final a in state.scopedActivities) _Entry.activity(a),
      ]);
    }
    final groups = _groupByDay(entries);
    final total = state.totalFor(matches);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            onPressed: _openFilters,
            tooltip: 'Filters',
            icon: Badge(
              isLabelVisible: _filter.activeCount > 0,
              label: Text('${_filter.activeCount}'),
              child: const Icon(Icons.tune_rounded),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => AddExpenseSheet.show(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search titles and notes',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _filter.query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _filter = _filter.copyWith(query: ''));
                        },
                      ),
              ),
              onChanged: (value) =>
                  setState(() => _filter = _filter.copyWith(query: value)),
            ),
          ),
          // A running total for the current filter is the whole point of
          // filtering — "how much did I spend on fuel in March" is one query.
          if (_filter.isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  Text(
                    '${matches.length} '
                    '${matches.length == 1 ? 'expense' : 'expenses'}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: context.muted),
                  ),
                  const Spacer(),
                  Text(
                    Money.format(total),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: groups.isEmpty
                ? _empty(context, state)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return _DayGroup(day: group.day, entries: group.entries);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, AppState state) {
    // Distinguishes "you have nothing" from "your filter matched nothing" —
    // the second needs a way out, not an invitation to add data.
    if (_filter.isActive) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        message: 'No expenses match the current search and filters.',
        action: TextButton(
          onPressed: () {
            _search.clear();
            setState(() => _filter = const ExpenseFilter());
          },
          child: const Text('Clear search and filters'),
        ),
      );
    }

    return EmptyState(
      icon: Icons.receipt_long_rounded,
      title: 'No expenses yet',
      message: 'Everything you record will show up here, newest first.',
      action: FilledButton.tonal(
        onPressed: () => AddExpenseSheet.show(context),
        child: const Text('Add your first expense'),
      ),
    );
  }

  /// Buckets entries into calendar days, newest first, expenses and
  /// activities interleaved.
  List<_DayBucket> _groupByDay(List<_Entry> entries) {
    final buckets = <DateTime, List<_Entry>>{};

    for (final entry in entries) {
      final date = entry.date;
      final day = DateTime(date.year, date.month, date.day);
      buckets.putIfAbsent(day, () => []).add(entry);
    }

    final days = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days) _DayBucket(day: day, entries: buckets[day]!),
    ];
  }
}

/// One history line — an expense or a non-expense activity.
class _Entry {
  const _Entry.expense(this.expense) : activity = null;
  const _Entry.activity(this.activity) : expense = null;

  final Expense? expense;
  final Activity? activity;

  DateTime get date => expense?.date ?? activity!.date;
}

class _DayBucket {
  const _DayBucket({required this.day, required this.entries});

  final DateTime day;
  final List<_Entry> entries;
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({required this.day, required this.entries});

  final DateTime day;
  final List<_Entry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Day header shows net expense spend only — mixing in income would make
    // "spent today" meaningless.
    final expenseTotal = entries
        .where((e) => e.expense != null)
        .fold<double>(0, (sum, e) => sum + e.expense!.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
          child: Row(
            children: [
              Text(
                Dates.relative(day),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: context.muted,
                ),
              ),
              const Spacer(),
              if (expenseTotal > 0)
                Text(
                  Money.format(expenseTotal),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: context.muted,
                  ),
                ),
            ],
          ),
        ),
        Card(
          child: Column(
            children: [
              for (var index = 0; index < entries.length; index++) ...[
                if (index > 0)
                  Divider(indent: 66, endIndent: 16, color: context.hairline),
                if (entries[index].expense != null)
                  ExpenseRow(expense: entries[index].expense!)
                else
                  ActivityRow(activity: entries[index].activity!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A single expense line. Swipe to delete, tap to edit.
class ExpenseRow extends StatelessWidget {
  const ExpenseRow({super.key, required this.expense, this.dense = false});

  final Expense expense;

  /// Trims padding and drops the swipe action, for embedding in the
  /// dashboard's "Recent" summary.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final row = _content(context);
    if (dense) return row;

    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: context.warn.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline_rounded, color: context.warn),
      ),
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        final state = context.read<AppState>();
        final messenger = ScaffoldMessenger.of(context);

        // Receipts are kept on disk so Undo can restore the expense whole.
        state.deleteExpense(expense.id, discardAttachments: false);

        messenger.showSnackBar(
          SnackBar(
            content: Text('Deleted "${expense.title}"'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => state.restoreExpense(expense),
            ),
          ),
        );
      },
      child: row,
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.read<AppState>();
    final category = state.categoryById(expense.categoryId);
    final profile = state.profileById(expense.profileId);
    final color = category.of(context);

    // The profile is only worth naming when more than one exists.
    final showProfile = profile != null && state.profiles.length > 1;

    // The enrich-later signal: this category can carry extra detail (litres,
    // odometer, …) but none has been added yet (spec §19). Offered inline so
    // the loop closes anytime, not just right after capture.
    final canEnrich =
        !dense &&
        CategoryFields.has(expense.categoryId) &&
        !expense.hasMetadata;

    return InkWell(
      onTap: () => AddExpenseSheet.show(context, existing: expense),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 0 : 16,
          vertical: dense ? 10 : 14,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: context.isDark ? 0.24 : 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(category.icon, size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          expense.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (expense.hasAttachments) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.attach_file_rounded,
                          size: 13,
                          color: context.muted,
                        ),
                      ],
                      // A filled tune glyph marks an expense already enriched.
                      if (expense.hasMetadata) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.tune_rounded,
                          size: 13,
                          color: context.muted,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [category.name, if (showProfile) profile.name].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // A quiet, optional affordance — enrichment is never a nag.
                  if (canEnrich) ...[
                    const SizedBox(height: 5),
                    GestureDetector(
                      onTap: () => MetadataSheet.show(context, expense.id),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            size: 13,
                            color: context.muted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            CategoryFields.promptFor(category.name),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: context.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              Money.format(expense.amount),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single non-expense activity line — income, transfer, loan or repayment.
///
/// Signs and colours make the direction unmistakable (spec §33): inflows are
/// green with a leading `+`, outflows and loans out are neutral with `−`, and
/// transfers are neutral (money that only moved, not spent).
class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = _iconFor(context, activity.type);
    final amount = Money.format(activity.amount);
    final signed = activity.type.isInflow
        ? '+$amount'
        : activity.type == ActivityType.transfer
        ? amount
        : '−$amount';

    return Dismissible(
      key: ValueKey('activity-${activity.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: context.warn.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline_rounded, color: context.warn),
      ),
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        final state = context.read<AppState>();
        final messenger = ScaffoldMessenger.of(context);
        state.deleteActivity(activity.id);
        // Transfers/income routinely have no description, so name what the row
        // actually showed rather than rendering an empty 'Deleted ""'.
        final label = activity.description.isEmpty
            ? activity.type.label
            : activity.description;
        messenger.showSnackBar(
          SnackBar(
            content: Text('Deleted "$label"'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => state.restoreActivity(activity.id),
            ),
          ),
        );
      },
      child: InkWell(
        onTap: () => ActivityEditSheet.show(context, activity),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: context.isDark ? 0.24 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.description.isEmpty
                          ? activity.type.label
                          : activity.description,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                signed,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: activity.type.isInflow ? context.good : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    if (activity.type == ActivityType.transfer) {
      return '${activity.sourceAccount ?? 'From'} → '
          '${activity.destinationAccount ?? 'To'}';
    }
    return activity.type.label;
  }

  (IconData, Color) _iconFor(BuildContext context, ActivityType type) {
    switch (type) {
      case ActivityType.income:
        return (Icons.south_west_rounded, context.good);
      case ActivityType.transfer:
        return (Icons.swap_horiz_rounded, context.scheme.primary);
      case ActivityType.loanOut:
        return (Icons.call_made_rounded, context.warn);
      case ActivityType.loanIn:
        return (Icons.call_received_rounded, context.good);
      case ActivityType.loanRepayment:
        return (Icons.undo_rounded, context.muted);
      case ActivityType.receivableRepayment:
        return (Icons.redo_rounded, context.good);
      case ActivityType.expense:
        return (Icons.remove_circle_outline_rounded, context.muted);
    }
  }
}
