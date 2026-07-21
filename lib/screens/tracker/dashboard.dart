import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/palette.dart';
import '../../services/format.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/stat.dart';
import '../manage/manage_screen.dart';
import '../planner/planner_home.dart';
import 'add_expense.dart';
import 'expense_list.dart';

/// The tracker's overview.
///
/// Built around a dark "hero" balance card with quick actions, then goal-style
/// budget cards — a spend-focused take on the savings-app layout the design
/// brief pointed at. Where that reference shows progress toward a savings
/// target, this shows progress toward a monthly budget: the honest analogue
/// for money going out rather than in.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.onSeeAnalytics, this.onSeePlanner});

  /// Jump to the Analytics tab, wired by the nav shell.
  final VoidCallback? onSeeAnalytics;

  /// Jump to the Planner tab.
  final VoidCallback? onSeePlanner;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final budgets = state.budgetProgress();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            _TopBar(),
            const SizedBox(height: 16),
            _HeroCard(
              spent: state.spentThisMonth,
              previous: state.spentLastMonth,
              onAdd: () => AddExpenseSheet.show(context),
              onHistory: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ExpenseListScreen(),
                ),
              ),
              onAnalytics: onSeeAnalytics,
              onPlanner: onSeePlanner,
            ),
            // Horizontal snapshot cards — a quick sideways-scrolling read of
            // recent spending, shown only once there is data to summarise.
            if (state.spentThisMonth > 0) ...[
              const SizedBox(height: 20),
              _SnapshotRow(
                thisWeek: state.spentInLastDays(7),
                dailyAverage: state.dailyAverageThisMonth,
                topCategory: state.topCategoryThisMonth,
              ),
            ],
            const SizedBox(height: 24),
            if (state.profiles.length > 1) ...[
              const _ProfileStrip(),
              const SizedBox(height: 20),
            ],
            if (budgets.isNotEmpty)
              _BudgetSection(budgets: budgets, daysLeft: state.daysLeftThisMonth)
            else
              _BudgetEmpty(
                hasExpenses: state.spentThisMonth > 0,
                onManage: () =>
                    ManageScreen.open(context),
              ),
            const SizedBox(height: 24),
            _PlannerSection(onSeeAll: onSeePlanner),
          ],
        ),
      ),
    );
  }
}

/// A horizontal row of planner tool shortcuts — the "plan ahead" counterpart
/// to the current-spending content above it. Each card opens its tool; "See
/// all" jumps to the Planner tab.
class _PlannerSection extends StatelessWidget {
  const _PlannerSection({this.onSeeAll});

  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tools = PlannerTool.all;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Plan ahead',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (onSeeAll != null)
              GestureDetector(
                onTap: onSeeAll,
                child: Text(
                  'See all',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: tools.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _PlannerCard(
              tool: tools[index],
              // Each card takes a distinct validated hue, cycling the palette.
              accent: Palette.color(
                index % Palette.length,
                theme.brightness,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlannerCard extends StatelessWidget {
  const _PlannerCard({required this.tool, required this.accent});

  final PlannerTool tool;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => openPlannerTool(context, tool),
      child: Container(
        width: 158,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: context.isDark ? const Color(0xFF232322) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: context.isDark ? 0.24 : 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(tool.icon, size: 20, color: accent),
            ),
            const SizedBox(height: 12),
            Text(
              tool.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Row(
              children: [
                Text(
                  'Open',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, size: 14, color: accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Greeting + manage button, in place of a conventional app bar so the hero
/// card can sit right below it.
class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _greeting(),
              style: theme.textTheme.bodyMedium?.copyWith(color: context.muted),
            ),
            Text(
              'Your money',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          onPressed: () => ManageScreen.open(context),
          tooltip: 'Categories, budgets & profiles',
          style: IconButton.styleFrom(
            backgroundColor: context.isDark
                ? const Color(0xFF232322)
                : Colors.white,
            side: BorderSide(color: context.hairline),
          ),
          icon: const Icon(Icons.tune_rounded, size: 20),
        ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

/// The dark headline card: month-to-date spend, trend, and quick actions.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.spent,
    required this.previous,
    required this.onAdd,
    required this.onHistory,
    this.onAnalytics,
    this.onPlanner,
  });

  final double spent;
  final double previous;
  final VoidCallback onAdd;
  final VoidCallback onHistory;
  final VoidCallback? onAnalytics;
  final VoidCallback? onPlanner;

  @override
  Widget build(BuildContext context) {
    final difference = spent - previous;
    final hasComparison = previous > 0;
    final up = difference > 0;
    // Fraction of last month's spend, the "+112%" style chip in the reference.
    final pct = previous > 0 ? (difference.abs() / previous) : 0.0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        // A near-black card in both themes — the hero is meant to anchor the
        // screen, so it keeps its dark identity rather than flipping.
        color: const Color(0xFF17181C),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Spent this month',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (hasComparison)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: (up ? AppTheme.warnDark : AppTheme.goodDark)
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        up
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 13,
                        color: up ? AppTheme.warnDark : AppTheme.goodDark,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        Money.percent(pct),
                        style: TextStyle(
                          color: up ? AppTheme.warnDark : AppTheme.goodDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedMoney(
            value: spent,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasComparison
                ? '${up ? 'Up' : 'Down'} ${Money.format(difference.abs())} '
                      'from last month'
                : 'Nothing to compare yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _HeroAction(
                icon: Icons.add_rounded,
                label: 'Add',
                onTap: onAdd,
              ),
              _HeroAction(
                icon: Icons.pie_chart_outline_rounded,
                label: 'Analytics',
                onTap: onAnalytics,
              ),
              _HeroAction(
                icon: Icons.calculate_outlined,
                label: 'Planner',
                onTap: onPlanner,
              ),
              _HeroAction(
                icon: Icons.receipt_long_outlined,
                label: 'History',
                onTap: onHistory,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One circular quick action inside the hero card.
class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A sideways-scrolling row of quick-read snapshot cards.
///
/// Three 150px cards overflow a phone's width, so the last one peeks off the
/// right edge — the cue that the row scrolls. It sits inside the parent list's
/// horizontal padding, so no extra padding of its own.
class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({
    required this.thisWeek,
    required this.dailyAverage,
    required this.topCategory,
  });

  final double thisWeek;
  final double dailyAverage;
  final CategoryTotal? topCategory;

  @override
  Widget build(BuildContext context) {
    final top = topCategory;

    return SizedBox(
      height: 118,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          _SnapshotCard(
            icon: Icons.calendar_view_week_rounded,
            label: 'This week',
            value: Money.compact(thisWeek),
            accent: context.scheme.primary,
          ),
          const SizedBox(width: 12),
          _SnapshotCard(
            icon: Icons.trending_up_rounded,
            label: 'Daily average',
            value: Money.compact(dailyAverage),
            accent: const Color(0xFF1BAF7A),
          ),
          if (top != null) ...[
            const SizedBox(width: 12),
            _SnapshotCard(
              icon: top.category.icon,
              label: 'Top: ${top.category.name}',
              value: Money.compact(top.total),
              accent: top.category.of(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF232322) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: context.isDark ? 0.24 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Profile switcher — rescopes the whole screen.
class _ProfileStrip extends StatelessWidget {
  const _ProfileStrip();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.activeProfileId;

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          _ProfileChip(
            label: 'All',
            icon: Icons.all_inclusive_rounded,
            color: context.scheme.primary,
            selected: active == null,
            onTap: () => state.setActiveProfile(null),
          ),
          for (final profile in state.profiles) ...[
            const SizedBox(width: 8),
            _ProfileChip(
              label: profile.name,
              icon: profile.icon,
              color: profile.of(context),
              selected: active == profile.id,
              onTap: () => state.setActiveProfile(profile.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: context.isDark ? 0.28 : 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : context.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "goals" list: one card per budgeted category, progress toward its
/// monthly limit.
class _BudgetSection extends StatelessWidget {
  const _BudgetSection({required this.budgets, required this.daysLeft});

  final List<BudgetProgress> budgets;
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Your budgets',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '$daysLeft days to go',
              style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final budget in budgets)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _BudgetCard(progress: budget, daysLeft: daysLeft),
          ),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.progress, required this.daysLeft});

  final BudgetProgress progress;
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = progress.category;
    final color = category.of(context);

    // The bar goes amber as it nears the limit and red once over, so a glance
    // reads status without parsing numbers.
    final barColor = progress.isOver
        ? context.warn
        : progress.fraction >= 0.85
        ? const Color(0xFFEDA100)
        : color;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF232322) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: context.isDark ? 0.24 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(category.icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  category.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: context.muted,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Money.format(progress.spent),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '  / ${Money.format(progress.budget)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.muted,
                ),
              ),
              const Spacer(),
              Text(
                Money.percent(progress.fraction),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress.barFraction),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 9,
                backgroundColor: context.hairline,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              progress.isOver
                  ? 'Over by ${Money.format(progress.spent - progress.budget)}'
                  : '${Money.format(progress.remaining)} left',
              style: theme.textTheme.bodySmall?.copyWith(
                color: progress.isOver ? context.warn : context.muted,
                fontWeight: progress.isOver ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when no category has a budget yet — the empty state for the goals
/// list, pointing at where to set one.
class _BudgetEmpty extends StatelessWidget {
  const _BudgetEmpty({required this.hasExpenses, required this.onManage});

  final bool hasExpenses;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF232322) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.flag_outlined,
              color: context.scheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Set a budget',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasExpenses
                ? 'Give a category a monthly limit and it shows up here as a '
                      'goal, with a bar that fills as you spend.'
                : 'Add a monthly limit to any category and track it here, like '
                      'a savings goal in reverse.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onManage,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Set up a budget'),
          ),
        ],
      ),
    );
  }
}
