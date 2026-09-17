import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../models/phosphor.dart';
import 'package:provider/provider.dart';

import '../../command/command_bar.dart';
import '../../models/account.dart';
import '../../models/palette.dart';
import '../../models/person.dart';
import '../../services/format.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/badge_icon.dart';
import '../../widgets/card_stack.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat.dart';
import '../manage/account_detail_screen.dart';
import '../manage/accounts_screen.dart';
import '../manage/manage_screen.dart';
import '../planner/planner_home.dart';
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

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  // 0 = collapsed (just the Total figure), 1 = expanded (the stacked cards).
  // The blue band grows from the height of the single figure to the full deck,
  // and the white sheet below rides down with it.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  static const double _collapsedBand = 60;
  static const double _expandedBand = 334; // deck 250 + peek 52 + dots ~32

  double get _range => _expandedBand - _collapsedBand;

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_reveal.value < 0.5) {
      _reveal.animateTo(1, curve: Curves.easeOutCubic);
    } else {
      _reveal.animateBack(0, curve: Curves.easeOutCubic);
    }
  }

  // Dragging the handle down grows the band (reveal); up shrinks it.
  void _onDragUpdate(DragUpdateDetails d) {
    _reveal.value = (_reveal.value + (d.primaryDelta ?? 0) / _range).clamp(
      0.0,
      1.0,
    );
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v > 320) {
      _reveal.animateTo(1, curve: Curves.easeOutCubic);
    } else if (v < -320) {
      _reveal.animateBack(0, curve: Curves.easeOutCubic);
    } else if (_reveal.value >= 0.5) {
      _reveal.animateTo(1, curve: Curves.easeOutCubic);
    } else {
      _reveal.animateBack(0, curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final blue = context.isDark
        ? const Color(0xFF20418C)
        : const Color(0xFF2F62E0);
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: blue,
      body: AnimatedBuilder(
        animation: _reveal,
        builder: (context, _) {
          final t = _reveal.value;
          final bandHeight = _collapsedBand + _range * t;
          return Column(
            children: [
              // ---- Blue hero: greeting, the Total, and the morphing band ----
              Padding(
                padding: EdgeInsets.fromLTRB(20, topInset + 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TopBar(),
                    const SizedBox(height: 18),
                    Text(
                      'Total',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // The morph: the single Total figure fades out as the stacked
                    // cards fade in, and the band grows to make room for them.
                    ClipRect(
                      child: SizedBox(
                        height: bandHeight,
                        width: double.infinity,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Opacity(
                              opacity: (1 - t * 1.8).clamp(0.0, 1.0),
                              child: Text(
                                Money.format(state.totalBalance),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 44,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: _expandedBand,
                              child: Opacity(
                                opacity: (t * 1.8 - 0.8).clamp(0.0, 1.0),
                                child: IgnorePointer(
                                  ignoring: t < 0.98,
                                  child: _deck(context, state),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ---- White sheet: handle to reveal/hide, content scrolls ----
              Expanded(
                child: _HeroSheet(
                  onToggle: _toggle,
                  onDragUpdate: _onDragUpdate,
                  onDragEnd: _onDragEnd,
                  child: _content(context, state),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The stacked deck revealed on expand: total-balance card, then one card per
  /// account, with the month-to-date flow card leading.
  Widget _deck(BuildContext context, AppState state) {
    return CardStack(
      height: 250,
      peek: 26,
      notchFront: true,
      cards: [
        _HeroCard(
          spent: state.spentThisMonth,
          spentPrevious: state.spentLastMonth,
          income: state.incomeThisMonth,
          incomePrevious: state.incomeLastMonth,
          onAdd: () => CommandBar.show(context),
          onIncome: () => CommandBar.show(context, initialText: 'Received '),
          onTransfer: () => CommandBar.show(context, initialText: 'Transfer '),
          onHistory: () => _openHistory(context),
        ),
        _BalanceCard(
          total: state.totalBalance,
          accounts: state.accountBalances,
          onAdd: () => CommandBar.show(context),
          onIncome: () => CommandBar.show(context, initialText: 'Received '),
          onTransfer: () => CommandBar.show(context, initialText: 'Transfer '),
          onHistory: () => _openHistory(context),
          onManageAccounts: () => AccountsScreen.open(context),
          onOpenAccount: (id) => AccountDetailScreen.open(context, id),
        ),
        // One card per account, largest balance first.
        for (final ab in state.accountBalances)
          _AccountCard(
            balance: ab,
            flow: state.accountFlow(ab.account.id, DateTime.now()),
            onOpen: () => AccountDetailScreen.open(context, ab.account.id),
          ),
      ],
    );
  }

  /// The scrollable body inside the white sheet.
  Widget _content(BuildContext context, AppState state) {
    final budgets = state.budgetProgress();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      children: [
        // Horizontal snapshot cards — a quick sideways-scrolling read of recent
        // spending, shown only once there is data to summarise.
        if (state.spentThisMonth > 0) ...[
          const SectionHeader(title: 'This month'),
          const SizedBox(height: 14),
          _SnapshotRow(snapshots: _snapshotsFor(context, state)),
          const SizedBox(height: 28),
        ],
        if (budgets.isNotEmpty)
          _BudgetSection(budgets: budgets, daysLeft: state.daysLeftThisMonth)
        else
          _BudgetEmpty(
            hasExpenses: state.spentThisMonth > 0,
            onManage: () => ManageScreen.open(context),
          ),
        if (state.scopedExpenses.isNotEmpty ||
            state.scopedActivities.isNotEmpty) ...[
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
    );
  }
}

/// The white sheet under the hero. A grabber at the top reveals or hides the
/// stacked cards — tap to toggle, drag to scrub — while the body scrolls.
class _HeroSheet extends StatelessWidget {
  const _HeroSheet({
    required this.child,
    required this.onToggle,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Widget child;
  final VoidCallback onToggle;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final surface = context.isDark
        ? const Color(0xFF15161A)
        : const Color(0xFFEFEFEA);
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            key: const ValueKey('hero-handle'),
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            onVerticalDragUpdate: onDragUpdate,
            onVerticalDragEnd: onDragEnd,
            child: SizedBox(
              height: 32,
              width: double.infinity,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        width: 13,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.scheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The five most recent entries — expenses and activities interleaved by
/// recency — as a compact peek. "See all" opens the full history; the rows are
/// dense (no swipe) so this stays a glance, not a place to manage from.
class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.onSeeAll});

  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Merge the two ledgers into one recency-sorted feed, newest first.
    final entries = <({DateTime date, Widget row})>[
      for (final e in state.scopedExpenses)
        (date: e.date, row: ExpenseRow(expense: e, dense: true)),
      for (final a in state.scopedActivities)
        (date: a.date, row: ActivityRow(activity: a, dense: true)),
    ]..sort((x, y) => y.date.compareTo(x.date));
    final recent = entries.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Recent', onAction: onSeeAll),
        const SizedBox(height: 14),
        Card(
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
        // Just the greeting now — the headline is the Total figure below it.
        Expanded(
          child: Text(
            _greeting(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hasProfiles) ...[const _ProfilePill(), const SizedBox(width: 8)],
        // Avatar-style entry to categories, budgets & profiles.
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

/// Which figure the hero card is showing.
enum _HeroMetric {
  spent('Spent'),
  income('Income'),
  net('Net');

  const _HeroMetric(this.label);
  final String label;
}

/// The dark headline card: a month-to-date figure the user can toggle between
/// Spent, Income and Net, its month-on-month trend, and the quick actions.
class _HeroCard extends StatefulWidget {
  const _HeroCard({
    required this.spent,
    required this.spentPrevious,
    required this.income,
    required this.incomePrevious,
    required this.onAdd,
    required this.onIncome,
    required this.onTransfer,
    required this.onHistory,
  });

  final double spent;
  final double spentPrevious;
  final double income;
  final double incomePrevious;
  final VoidCallback onAdd;
  final VoidCallback onIncome;
  final VoidCallback onTransfer;
  final VoidCallback onHistory;

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  _HeroMetric _metric = _HeroMetric.spent;

  double get _value => switch (_metric) {
    _HeroMetric.spent => widget.spent,
    _HeroMetric.income => widget.income,
    _HeroMetric.net => widget.income - widget.spent,
  };

  double get _previous => switch (_metric) {
    _HeroMetric.spent => widget.spentPrevious,
    _HeroMetric.income => widget.incomePrevious,
    _HeroMetric.net => widget.incomePrevious - widget.spentPrevious,
  };

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final previous = _previous;
    final difference = value - previous;
    final hasComparison = previous.abs() > 0;
    final up = difference > 0;
    // For spending, a rise is bad; for income and net, a rise is good — so the
    // trend chip's colour flips with the metric.
    final good = _metric == _HeroMetric.spent ? !up : up;
    final trendColor = good ? AppTheme.goodDark : AppTheme.warnDark;
    final pct = previous.abs() > 0 ? (difference.abs() / previous.abs()) : 0.0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: heroCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MetricToggle(
                selected: _metric,
                onChanged: (m) {
                  HapticFeedback.selectionClick();
                  setState(() => _metric = m);
                },
              ),
              const Spacer(),
              if (hasComparison)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        up
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 13,
                        color: trendColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        Money.percent(pct),
                        style: TextStyle(
                          color: trendColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Scale a large figure down rather than letting it ellipsize — this
          // is the app's headline number, so a partial one would mislead.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(
              value: value,
              // The single heaviest token in the app — the one headline figure.
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(color: Colors.white),
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
          const Spacer(),
          _HeroActionRow(
            onAdd: widget.onAdd,
            onIncome: widget.onIncome,
            onTransfer: widget.onTransfer,
            onHistory: widget.onHistory,
          ),
        ],
      ),
    );
  }
}

/// The dark card's shared surface — gradient, top rim-light, layered shadow and
/// brand under-glow — used by every card in the hero deck so they read as one
/// stack.
/// The balance card in the hero deck — how much money there is and where it
/// sits, across every account.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.total,
    required this.accounts,
    required this.onAdd,
    required this.onIncome,
    required this.onTransfer,
    required this.onHistory,
    required this.onManageAccounts,
    required this.onOpenAccount,
  });

  final double total;
  final List<AccountBalance> accounts;
  final VoidCallback onAdd;
  final VoidCallback onIncome;
  final VoidCallback onTransfer;
  final VoidCallback onHistory;
  final VoidCallback onManageAccounts;
  final ValueChanged<String> onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: heroCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Total balance',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onManageAccounts,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Text(
                      'Accounts',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(
              value: total,
              style: theme.textTheme.displayLarge?.copyWith(
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: accounts.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == accounts.length) {
                  return _AccountChip.add(onTap: onManageAccounts);
                }
                return _AccountChip(
                  balance: accounts[index],
                  onTap: () => onOpenAccount(accounts[index].account.id),
                );
              },
            ),
          ),
          const Spacer(),
          _HeroActionRow(
            onAdd: onAdd,
            onIncome: onIncome,
            onTransfer: onTransfer,
            onHistory: onHistory,
          ),
        ],
      ),
    );
  }
}

/// One account as its own card in the hero deck — name, live balance, and this
/// month's money in vs out. Tap to open the account.
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.balance,
    required this.flow,
    required this.onOpen,
  });

  final AccountBalance balance;
  final AccountFlow flow;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = balance.account;
    final accent = account.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: heroCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BadgeIcon(icon: account.icon, accent: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        account.type.label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ],
            ),
            const Spacer(),
            Text(
              'Balance',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                Money.format(balance.balance),
                style: theme.textTheme.displayLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                _flowBit(context, 'In', flow.inflow, context.good),
                const SizedBox(width: 20),
                _flowBit(context, 'Out', flow.outflow, context.warn),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _flowBit(BuildContext context, String label, double amount, Color c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          label == 'In' ? Icons.south_west_rounded : Icons.north_east_rounded,
          size: 15,
          color: c,
        ),
        const SizedBox(width: 5),
        Text(
          Money.compact(amount),
          style: TextStyle(
            color: c,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// A translucent wallet chip on the dark balance card.
class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.balance, this.onTap}) : isAdd = false;
  const _AccountChip.add({required this.onTap}) : balance = null, isAdd = true;

  final AccountBalance? balance;
  final bool isAdd;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: [
          Icon(
            isAdd ? Icons.add_rounded : balance!.account.icon,
            size: 14,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 6),
          Text(
            isAdd ? 'Account' : balance!.account.name,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!isAdd) ...[
            const SizedBox(width: 6),
            Text(
              Money.compact(balance!.balance),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return child;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}

/// The four circular quick actions shared across the hero deck's cards.
class _HeroActionRow extends StatelessWidget {
  const _HeroActionRow({
    required this.onAdd,
    required this.onIncome,
    required this.onTransfer,
    required this.onHistory,
  });

  final VoidCallback onAdd;
  final VoidCallback onIncome;
  final VoidCallback onTransfer;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HeroAction(icon: PhosphorR.plus, label: 'Add', onTap: onAdd),
        _HeroAction(
          icon: PhosphorR.arrowDownLeft,
          label: 'Income',
          onTap: onIncome,
        ),
        _HeroAction(
          icon: PhosphorR.arrowsLeftRight,
          label: 'Transfer',
          onTap: onTransfer,
        ),
        _HeroAction(
          icon: PhosphorR.clockCounterClockwise,
          label: 'History',
          onTap: onHistory,
        ),
      ],
    );
  }
}

/// The Spent / Income / Net pill switcher at the top of the hero card.
class _MetricToggle extends StatelessWidget {
  const _MetricToggle({required this.selected, required this.onChanged});

  final _HeroMetric selected;
  final ValueChanged<_HeroMetric> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final metric in _HeroMetric.values)
            GestureDetector(
              key: ValueKey('metric-${metric.name}'),
              onTap: () => onChanged(metric),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: metric == selected
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  metric.label,
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: metric == selected ? 0.95 : 0.5,
                    ),
                    fontSize: 12.5,
                    fontWeight: metric == selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
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
    final tap = onTap;
    return Expanded(
      // Transparent Material so the ink splash is visible on the dark hero.
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: tap == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  tap();
                },
          radius: 44,
          splashColor: Colors.white.withValues(alpha: 0.18),
          highlightColor: Colors.white.withValues(alpha: 0.06),
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
      ),
    );
  }
}

/// One card's worth of the snapshot row — a single at-a-glance figure.
class _Snapshot {
  const _Snapshot({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
}

/// The snapshot cards shown under the hero, left to right.
///
/// The first block is always present once there's any spend; the rest appear
/// only when they have something to say (a top category, income logged, a
/// prior month to compare against), so the row never shows an empty or
/// meaningless card.
List<_Snapshot> _snapshotsFor(BuildContext context, AppState state) {
  // A tight glance — four figures, not a wall of stats. The rest (top category,
  // biggest, counts) live in the Analytics tab. Every badge tint is drawn from
  // the validated palette or a semantic token, so nothing escapes the
  // contrast-checked system.
  final brightness = Theme.of(context).brightness;

  return [
    _Snapshot(
      icon: PhosphorR.calendarBlank,
      label: 'Today',
      value: Money.compact(state.spentToday),
      accent: context.scheme.primary,
    ),
    _Snapshot(
      icon: PhosphorR.calendarDots,
      label: 'This week',
      value: Money.compact(state.spentInLastDays(7)),
      accent: Palette.color(6, brightness), // violet
    ),
    _Snapshot(
      icon: PhosphorR.trendUp,
      label: 'Daily average',
      // A daily average is neutral — green stays reserved for good/positive.
      value: Money.compact(state.dailyAverageThisMonth),
      accent: Palette.color(4, brightness), // teal
    ),
    _Snapshot(
      icon: PhosphorR.chartLineUp,
      label: 'Projected',
      value: Money.compact(state.projectedThisMonth),
      accent: context.caution,
    ),
  ];
}

/// A sideways-scrolling row of quick-read snapshot cards.
///
/// The cards overflow a phone's width on purpose, so the last one peeks off the
/// right edge — the cue that the row scrolls. It sits inside the parent list's
/// horizontal padding, so no extra padding of its own.
class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({required this.snapshots});

  final List<_Snapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 126,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: snapshots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final snapshot = snapshots[index];
          return _SnapshotCard(
            icon: snapshot.icon,
            label: snapshot.label,
            value: snapshot.value,
            accent: snapshot.accent,
          );
        },
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
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          BadgeIcon(icon: icon, accent: accent, size: BadgeSize.sm),
          const SizedBox(height: 10),
          // The figure leads; the word is the caption beneath it.
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
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
        ? context.caution
        : color;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              BadgeIcon(icon: category.icon, accent: color),
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
              Icon(Icons.chevron_right_rounded, size: 20, color: context.muted),
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
                  fontFeatures: const [FontFeature.tabularFigures()],
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
            // Half the bar height, so the caps are true pills.
            borderRadius: BorderRadius.circular(5),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress.barFraction),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 10,
                // A faint tinted rail previews the fill's hue, instead of an
                // empty grey gutter.
                backgroundColor: barColor.withValues(
                  alpha: context.isDark ? 0.16 : 0.10,
                ),
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
      decoration: context.cardDecoration(),
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
