import 'package:flutter/material.dart';
import '../../models/phosphor.dart';
import 'package:provider/provider.dart';

import '../../models/palette.dart';
import '../../models/person.dart';
import '../../services/format.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/badge_icon.dart';
import '../../widgets/frosted_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/week_calendar.dart';
import '../manage/manage_screen.dart';
import '../planner/planner_home.dart';
import 'accounts_spread.dart';
import 'expense_list.dart';

/// Opens the full history list.
void _openHistory(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ExpenseListScreen()));
}

/// The tracker's overview.
///
/// Built around a dark "hero" balance card with quick actions, then goal-style
/// budget cards — a spend-focused take on the savings-app layout the design
/// brief pointed at. Where that reference shows progress toward a savings
/// target, this shows progress toward a monthly budget: the honest analogue
/// for money going out rather than in.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onSeePlanner});

  /// Jump to the Planner tab, wired by the nav shell.
  final VoidCallback? onSeePlanner;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // A chosen calendar day, or null for the full overview.
  DateTime? _dayFilter;

  // The budget's identity green, for the island accents.
  static const _accent = Color(0xFF2E9E6B);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dark = context.isDark;
    final bg = dark ? const Color(0xFF12211A) : const Color(0xFFEFF4F0);
    final budgets = state.budgetProgress();
    final hasHistory =
        state.scopedExpenses.isNotEmpty || state.scopedActivities.isNotEmpty;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DashIsland(
              child: Column(
                children: [
                  _TopBar(),
                  const SizedBox(height: 12),
                  WeekCalendar(
                    selected: _dayFilter,
                    accent: _accent,
                    onSelect: (d) => setState(() => _dayFilter = d),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                children: [
                  _TotalCard(
                    total: state.totalBalance,
                    onTap: () => showAccountsSpread(context),
                  ),
                  const SizedBox(height: 22),
                  if (_dayFilter != null)
                    _RecentSection(
                      day: _dayFilter,
                      onSeeAll: () => _openHistory(context),
                    )
                  else ...[
                    if (state.spentThisMonth > 0) ...[
                      const SectionHeader(title: 'This month'),
                      const SizedBox(height: 14),
                      _MonthSummaryCard(state: state),
                      const SizedBox(height: 28),
                    ],
                    if (budgets.isNotEmpty)
                      _BudgetSection(
                        budgets: budgets,
                        daysLeft: state.daysLeftThisMonth,
                      )
                    else
                      _BudgetEmpty(
                        hasExpenses: state.spentThisMonth > 0,
                        onManage: () => ManageScreen.open(context),
                      ),
                    if (hasHistory) ...[
                      const SizedBox(height: 28),
                      _RecentSection(onSeeAll: () => _openHistory(context)),
                    ],
                    if (state.outstandingBalances.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _BalancesSection(balances: state.outstandingBalances),
                    ],
                    const SizedBox(height: 28),
                    _PlannerSection(onSeeAll: widget.onSeePlanner),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rounded header island: the top bar and the week calendar, on a raised
/// card — the budget's take on the Second Brain's island header.
class _DashIsland extends StatelessWidget {
  const _DashIsland({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1B2A22) : Colors.white,
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

/// The headline balance, as a green card. Tapping it fans out the accounts —
/// the deck's spread, now reachable from a single card.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total, required this.onTap});

  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2E9E6B), Color(0xFF1E7A50)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2E9E6B).withValues(alpha: 0.32),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Total balance',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.grid_view_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                Money.format(total),
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap to see your accounts',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The five most recent entries — expenses and activities interleaved by
/// recency — as a compact peek. "See all" opens the full history; the rows are
/// dense (no swipe) so this stays a glance, not a place to manage from.
class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.onSeeAll, this.day});

  final VoidCallback onSeeAll;

  /// When set, show only that day's entries (and all of them, not just five).
  final DateTime? day;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Merge the two ledgers into one recency-sorted feed, newest first.
    var entries = <({DateTime date, Widget row})>[
      for (final e in state.scopedExpenses)
        (date: e.date, row: ExpenseRow(expense: e, dense: true)),
      for (final a in state.scopedActivities)
        (date: a.date, row: ActivityRow(activity: a, dense: true)),
    ]..sort((x, y) => y.date.compareTo(x.date));
    if (day != null) {
      entries = entries.where((e) => _sameDay(e.date, day!)).toList();
    }
    final recent = day != null ? entries : entries.take(5).toList();

    if (day != null && recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_available_rounded,
                size: 34,
                color: context.muted,
              ),
              const SizedBox(height: 10),
              Text(
                'Nothing on this day',
                style: TextStyle(color: context.muted, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: day != null ? 'That day' : 'Recent',
          onAction: onSeeAll,
        ),
        const SizedBox(height: 14),
        FrostedCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0) Divider(indent: 52, color: context.hairline),
                  recent[i].row,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Outstanding loan balances — receivables and liabilities (spec §34).
///
/// Loans aren't spending or earning, so they don't belong in the budget or
/// spending figures; they get their own home here, framed as "owed to you" and
/// "you owe" rather than folded into any total.
class _BalancesSection extends StatelessWidget {
  const _BalancesSection({required this.balances});

  final List<LoanBalance> balances;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Money owed'),
        const SizedBox(height: 14),
        for (final balance in balances)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _BalanceRow(balance: balance),
          ),
      ],
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.balance});

  final LoanBalance balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final theyOwe = balance.theyOweUser;
    final color = theyOwe ? context.good : context.warn;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration(),
      child: Row(
        children: [
          BadgeIcon(
            icon: theyOwe
                ? Icons.call_received_rounded
                : Icons.call_made_rounded,
            accent: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  balance.person.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  theyOwe ? 'Owes you' : 'You owe',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            Money.format(balance.magnitude),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
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
        SectionHeader(title: 'Plan ahead', onAction: onSeeAll),
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
              accent: Palette.color(index % Palette.length, theme.brightness),
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

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: context.cardShadow,
      ),
      child: Material(
        color: context.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => openPlannerTool(context, tool),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 158,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BadgeIcon(icon: tool.icon, accent: accent),
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
    // Only surface the profile switcher once there is more than one wallet to
    // switch between — otherwise "All" is the only choice.
    final hasProfiles = context.select<AppState, bool>(
      (s) => s.profiles.length > 1,
    );

    return Row(
      children: [
        // Avatar-style entry to categories, budgets & profiles — leads the row.
        IconButton(
          onPressed: () => ManageScreen.open(context),
          tooltip: 'Categories, budgets & profiles',
          style: IconButton.styleFrom(
            backgroundColor: context.isDark
                ? const Color(0xFF232322)
                : Colors.white,
            shape: const CircleBorder(),
            side: BorderSide(color: context.hairline),
          ),
          icon: const Icon(Icons.person_rounded, size: 20),
        ),
        const SizedBox(width: 12),
        // The greeting — the headline is the Total figure below it.
        Expanded(
          child: Text(
            _greeting(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: context.scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hasProfiles) const _ProfilePill(),
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

/// The month at a glance: the spend headline with its trend versus last month,
/// how far it is toward the projected total, and the four sub-stats as a strip.
class _MonthSummaryCard extends StatelessWidget {
  const _MonthSummaryCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spent = state.spentThisMonth;
    final lastMonth = state.spentLastMonth;
    final projected = state.projectedThisMonth;
    final primary = context.scheme.primary;

    final hasComparison = lastMonth > 0;
    final up = spent > lastMonth;
    final pct = hasComparison
        ? ((spent - lastMonth).abs() / lastMonth * 100).round()
        : 0;
    // For spending, a fall is the good direction.
    final trendColor = up ? context.warn : context.good;

    final fraction = projected > 0 ? (spent / projected).clamp(0.0, 1.0) : 0.0;

    return FrostedCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spent this month',
            style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  Money.format(spent),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasComparison) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        up
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 13,
                        color: trendColor,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$pct% vs last',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: trendColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: primary.withValues(
                alpha: context.isDark ? 0.16 : 0.10,
              ),
              valueColor: AlwaysStoppedAnimation(primary),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'of ${Money.compact(projected)} projected by month-end',
            style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: context.hairline),
          const SizedBox(height: 14),
          Row(
            children: [
              _MonthStat(
                label: 'Today',
                value: Money.compact(state.spentToday),
              ),
              _MonthStat(
                label: 'This week',
                value: Money.compact(state.spentInLastDays(7)),
              ),
              _MonthStat(
                label: 'Avg/day',
                value: Money.compact(state.dailyAverageThisMonth),
              ),
              _MonthStat(label: 'Projected', value: Money.compact(projected)),
            ],
          ),
        ],
      ),
    );
  }
}

/// One figure-over-label cell in the month summary's stat strip.
class _MonthStat extends StatelessWidget {
  const _MonthStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
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
/// The profile switcher — a compact pill in the header showing the active
/// wallet, tapped to drop a menu of All + every profile. It sits on the blue
/// wash, so it's styled in translucent white to read against it.
class _ProfilePill extends StatelessWidget {
  const _ProfilePill();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.activeProfile;
    final label = active?.name ?? 'All';
    final icon = active?.icon ?? Icons.all_inclusive_rounded;
    final theme = Theme.of(context);

    return PopupMenuButton<String?>(
      tooltip: 'Switch profile',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: context.isDark ? const Color(0xFF232322) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.hairline),
      ),
      onSelected: state.setActiveProfile,
      itemBuilder: (context) => [
        _menuItem(
          context,
          id: null,
          label: 'All',
          icon: Icons.all_inclusive_rounded,
          color: context.scheme.primary,
          selected: state.activeProfileId == null,
        ),
        for (final profile in state.profiles)
          _menuItem(
            context,
            id: profile.id,
            label: profile.name,
            icon: profile.icon,
            color: profile.of(context),
            selected: state.activeProfileId == profile.id,
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String?> _menuItem(
    BuildContext context, {
    required String? id,
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
  }) {
    return PopupMenuItem<String?>(
      value: id,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: context.scheme.onSurface,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (selected) ...[
            const Spacer(),
            Icon(Icons.check_rounded, size: 18, color: color),
          ],
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Your budgets',
          meta: switch (daysLeft) {
            0 => 'Last day',
            1 => '1 day to go',
            _ => '$daysLeft days to go',
          },
        ),
        const SizedBox(height: 14),
        FrostedCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < budgets.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, indent: 48, color: context.hairline),
                _BudgetRow(progress: budgets[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One budget as a compact row: icon, name and figure across the top, a thin
/// progress bar with its percent underneath. Slimmer than a full card, so a
/// handful stack in one grouped card.
class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = progress.category;
    final color = category.of(context);

    // Amber as it nears the limit, red once over — status at a glance.
    final barColor = progress.isOver
        ? context.warn
        : progress.fraction >= 0.85
        ? context.caution
        : color;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          BadgeIcon(icon: category.icon, accent: color, size: BadgeSize.sm),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
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
                    const SizedBox(width: 8),
                    Text(
                      Money.compact(progress.spent),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      ' / ${Money.compact(progress.budget)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress.barFraction,
                          minHeight: 7,
                          backgroundColor: barColor.withValues(
                            alpha: context.isDark ? 0.16 : 0.10,
                          ),
                          valueColor: AlwaysStoppedAnimation(barColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 40,
                      child: Text(
                        Money.percent(progress.fraction),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: barColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, size: 18, color: context.muted),
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

    return FrostedCard(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BadgeIcon(
            icon: Icons.flag_rounded,
            accent: context.scheme.primary,
            size: BadgeSize.lg,
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
            icon: const Icon(PhosphorR.plus, size: 18),
            label: const Text('Set up a budget'),
          ),
        ],
      ),
    );
  }
}
