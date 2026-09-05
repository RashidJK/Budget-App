import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../models/phosphor.dart';
import '../../services/format.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/app_background.dart';
import '../../widgets/badge_icon.dart';
import '../../widgets/morph_nav_bar.dart';
import '../../widgets/section_header.dart';
import '../quick_capture.dart';
import 'accounts_screen.dart';

/// One account, opened up: its balance, its own ledger and its cash-flow.
///
/// This is where the [MorphNavBar] earns its name — the same glass bar the home
/// shell wears, but with a different set of destinations
/// (Overview · Transactions · [+] · Insights · More). Pushing into an account
/// *morphs* the bar to the account's own world while the centre "+" stays put,
/// so capture is never more than one tap away.
class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final String accountId;

  static Future<void> open(BuildContext context, String accountId) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountDetailScreen(accountId: accountId),
      ),
    );
  }

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  int _tab = 0;

  void _select(int index) => setState(() => _tab = index);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final account = state.accountById(widget.accountId);

    // The account was deleted (possibly on another device) while open — there's
    // nothing left to show, so step back out.
    if (account == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(backgroundColor: Colors.transparent);
    }

    final balance = state.accountBalance(account.id);
    final movements = state.accountMovements(account.id);
    final flow = state.accountFlow(account.id, DateTime.now());

    final tabs = [
      _OverviewTab(
        account: account,
        balance: balance,
        flow: flow,
        movements: movements,
        onSeeAll: () => _select(1),
      ),
      _TransactionsTab(movements: movements),
      _InsightsTab(accountId: account.id, state: state),
      _MoreTab(account: account, balance: balance),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            BadgeIcon(
              icon: account.icon,
              accent: account.of(context),
              size: BadgeSize.sm,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    account.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    account.type.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: AppBackground(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey(_tab),
            child: tabs[_tab],
          ),
        ),
      ),
      bottomNavigationBar: MorphNavBar(
        activeIndex: _tab,
        onSelect: _select,
        onCapture: (text) => captureFromText(context, text),
        items: const [
          MorphNavItem(
            icon: PhosphorR.squaresFour,
            activeIcon: PhosphorF.squaresFour,
            label: 'Overview',
          ),
          MorphNavItem(
            icon: PhosphorR.receipt,
            activeIcon: PhosphorF.receipt,
            label: 'Activity',
          ),
          MorphNavItem(
            icon: PhosphorR.chartPie,
            activeIcon: PhosphorF.chartPie,
            label: 'Insights',
          ),
          MorphNavItem(
            icon: PhosphorR.dotsThreeOutline,
            activeIcon: PhosphorR.dotsThreeOutline,
            label: 'More',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.account,
    required this.balance,
    required this.flow,
    required this.movements,
    required this.onSeeAll,
  });

  final Account account;
  final double balance;
  final AccountFlow flow;
  final List<AccountMovement> movements;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = movements.take(5).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        _BalanceHeader(account: account, balance: balance),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _FlowTile(
                label: 'In this month',
                amount: flow.inflow,
                icon: PhosphorR.arrowDownLeft,
                color: context.good,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FlowTile(
                label: 'Out this month',
                amount: flow.outflow,
                icon: PhosphorR.receipt,
                color: context.warn,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SectionHeader(
          title: 'Recent activity',
          actionLabel: recent.isEmpty ? null : 'See all',
          onAction: recent.isEmpty ? null : onSeeAll,
        ),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          _EmptyLedger(theme: theme)
        else
          Container(
            decoration: context.cardDecoration(),
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: context.hairline, indent: 64),
                  _MovementTile(movement: recent[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.account, required this.balance});

  final Account account;
  final double balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: heroCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Balance',
            style: theme.textTheme.bodyMedium?.copyWith(color: context.muted),
          ),
          const SizedBox(height: 6),
          Text(
            Money.format(balance),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowTile extends StatelessWidget {
  const _FlowTile({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String label;
  final double amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 10),
          Text(
            Money.compact(amount),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transactions
// ---------------------------------------------------------------------------

class _TransactionsTab extends StatelessWidget {
  const _TransactionsTab({required this.movements});

  final List<AccountMovement> movements;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (movements.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [_EmptyLedger(theme: theme)],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        const SectionHeader(title: 'All activity'),
        const SizedBox(height: 12),
        Container(
          decoration: context.cardDecoration(),
          child: Column(
            children: [
              for (var i = 0; i < movements.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: context.hairline, indent: 64),
                _MovementTile(movement: movements[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final AccountMovement movement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = movement.isInflow ? context.good : context.warn;
    final sign = movement.isInflow ? '+' : '−';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          BadgeIcon(
            icon: movement.icon,
            accent: color,
            size: BadgeSize.sm,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${movement.subtitle} · ${Dates.relative(movement.date)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$sign${Money.format(movement.delta.abs())}',
            style: theme.textTheme.titleSmall?.copyWith(
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

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: context.cardDecoration(),
      child: Column(
        children: [
          Icon(PhosphorR.receipt, size: 32, color: context.muted),
          const SizedBox(height: 12),
          Text(
            'Nothing here yet',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Spend, receive or transfer from this account and it shows up here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Insights
// ---------------------------------------------------------------------------

class _InsightsTab extends StatelessWidget {
  const _InsightsTab({required this.accountId, required this.state});

  final String accountId;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = [
      for (var offset = 5; offset >= 0; offset--)
        DateTime(now.year, now.month - offset),
    ];
    final flows = [
      for (final month in months) (month, state.accountFlow(accountId, month)),
    ];
    final peak = flows.fold<double>(
      1,
      (max, entry) => [
        max,
        entry.$2.inflow,
        entry.$2.outflow,
      ].reduce((a, b) => a > b ? a : b),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        const SectionHeader(title: 'Money in vs out', meta: 'Last 6 months'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          decoration: context.cardDecoration(),
          child: Column(
            children: [
              for (final entry in flows) ...[
                _FlowBars(
                  label: Dates.month(entry.$1),
                  flow: entry.$2,
                  peak: peak,
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Legend(color: context.good, label: 'In'),
            const SizedBox(width: 16),
            _Legend(color: context.warn, label: 'Out'),
          ],
        ),
      ],
    );
  }
}

class _FlowBars extends StatelessWidget {
  const _FlowBars({required this.label, required this.flow, required this.peak});

  final String label;
  final AccountFlow flow;
  final double peak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.muted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: [
                  _Bar(value: flow.inflow, peak: peak, color: context.good),
                  const SizedBox(height: 5),
                  _Bar(value: flow.outflow, peak: peak, color: context.warn),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.peak, required this.color});

  final double value;
  final double peak;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = (value / peak).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        // A hairline stub even at zero, so an empty month still reads as a row.
        final width = (constraints.maxWidth * fraction).clamp(3.0, double.infinity);
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            height: 8,
            width: width,
            decoration: BoxDecoration(
              color: color.withValues(alpha: value == 0 ? 0.25 : 1),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.muted,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// More
// ---------------------------------------------------------------------------

class _MoreTab extends StatelessWidget {
  const _MoreTab({required this.account, required this.balance});

  final Account account;
  final double balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        const SectionHeader(title: 'Account'),
        const SizedBox(height: 12),
        Container(
          decoration: context.cardDecoration(),
          child: Column(
            children: [
              _DetailRow(label: 'Type', value: account.type.label),
              Divider(height: 1, color: context.hairline, indent: 16),
              _DetailRow(
                label: 'Opening balance',
                value: Money.format(account.openingBalance),
              ),
              Divider(height: 1, color: context.hairline, indent: 16),
              _DetailRow(
                label: 'Current balance',
                value: Money.format(balance),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.tonalIcon(
          onPressed: () => AccountsScreen.edit(context, account),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit account'),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () => AccountsScreen.open(context),
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
          label: const Text('All accounts'),
        ),
        const SizedBox(height: 24),
        Text(
          'Balances are derived: opening balance plus everything in, minus '
          'everything out. Edit a movement and this updates with it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: context.muted,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: context.muted),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
