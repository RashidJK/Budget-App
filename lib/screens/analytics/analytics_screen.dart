import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/format.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/inputs.dart';
import '../../widgets/stat.dart';

/// Where the money actually went — the "understand, don't just record" half of
/// the product. Monthly trend, category breakdown, and the handful of stats
/// that answer "why was this month different".
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = DateTime.now();
    final months = state.monthlyTotals();
    final categories = state.categoryTotals(now);
    final biggest = state.biggestExpenseThisMonth;
    final txnCount = state.expensesInMonth(now).length;

    final average = months.where((m) => m.total > 0).toList();
    final averageMonthly = average.isEmpty
        ? 0.0
        : average.fold<double>(0, (sum, m) => sum + m.total) / average.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          if (state.profiles.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  state.activeProfile?.name ?? 'All profiles',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: state.expenses.isEmpty
          ? const EmptyState(
              icon: Icons.insights_rounded,
              title: 'Nothing to analyse yet',
              message:
                  'Once you have recorded a few expenses, your trends and '
                  'breakdown show up here.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                SectionCard(
                  title: 'Monthly trend',
                  trailing: Text(
                    'Avg ${Money.compact(averageMonthly)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.muted,
                    ),
                  ),
                  child: MonthlyTrendChart(months: months),
                ),
                const SizedBox(height: 16),
                _StatRow(
                  daily: state.dailyAverageThisMonth,
                  transactions: txnCount,
                ),
                const SizedBox(height: 16),
                if (biggest != null) ...[
                  _BiggestExpenseCard(
                    title: biggest.title,
                    amount: biggest.amount,
                    categoryName: state.categoryById(biggest.categoryId).name,
                    color: state.categoryById(biggest.categoryId).of(context),
                    icon: state.categoryById(biggest.categoryId).icon,
                    date: biggest.date,
                  ),
                  const SizedBox(height: 16),
                ],
                if (categories.isNotEmpty)
                  SectionCard(
                    title: 'This month by category',
                    child: CategoryBreakdown(totals: categories, maxRows: 8),
                  ),
              ],
            ),
    );
  }
}

/// Daily average and transaction count, side by side.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.daily, required this.transactions});

  final double daily;
  final int transactions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatTile(label: 'Average / day', value: daily),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CountTile(
            label: 'Transactions',
            value: transactions,
          ),
        ),
      ],
    );
  }
}

/// A plain integer stat, reusing the [StatTile] look without money formatting.
class _CountTile extends StatelessWidget {
  const _CountTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: context.scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: context.muted,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BiggestExpenseCard extends StatelessWidget {
  const _BiggestExpenseCard({
    required this.title,
    required this.amount,
    required this.categoryName,
    required this.color,
    required this.icon,
    required this.date,
  });

  final String title;
  final double amount;
  final String categoryName;
  final Color color;
  final IconData icon;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: context.isDark ? 0.24 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Biggest this month',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: context.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$categoryName · ${Dates.short(date)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            Money.format(amount),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
