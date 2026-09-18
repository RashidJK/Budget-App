import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/format.dart';
import '../state/app_state.dart';

/// Which area the briefing summarises. The nav bar's ✨ opens the briefing for
/// wherever you are, so each area gets a summary that is actually about it —
/// Home talks money on hand, Expenses talks this month's spending, Analytics
/// talks trend, Planner talks what's ahead, and an account talks its own flow.
enum BriefingKind { home, expenses, analytics, planner, account }

/// A blue "briefing" island — a friendly, at-a-glance summary tailored to
/// [kind]. Drops down from the very top edge of the screen (bleeding behind the
/// status bar), opened from the bar. Pass [accountId] with [BriefingKind.account].
Future<void> showBriefing(
  BuildContext context, {
  BriefingKind kind = BriefingKind.home,
  String? accountId,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Briefing',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 360),
    pageBuilder: (_, _, _) => _BriefingCard(kind: kind, accountId: accountId),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -0.18),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// A bold inline figure inside the briefing sentence. It inherits colour and
/// size from the surrounding [DefaultTextStyle] and only overrides the weight.
Text _bold(String s) => Text(
  s,
  style: const TextStyle(fontWeight: FontWeight.w800),
  textScaler: TextScaler.noScaling,
);

Text _plain(String s) => Text(s);

/// The resolved content for one area's briefing.
class _BriefingContent {
  const _BriefingContent({
    required this.icon,
    required this.title,
    required this.sentence,
    required this.stats,
  });

  final IconData icon;
  final String title;

  /// Inline pieces of the summary sentence, laid out in a [Wrap].
  final List<Widget> sentence;

  /// Up to three footer figures.
  final List<_Stat> stats;
}

class _BriefingCard extends StatelessWidget {
  const _BriefingCard({required this.kind, this.accountId});

  final BriefingKind kind;
  final String? accountId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final content = _contentFor(context, state);
    // Bleed up behind the status bar rather than floating below it, so the
    // island reads as dropping in from the very top edge of the screen.
    final topInset = MediaQuery.paddingOf(context).top;

    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.72);

    // showGeneralDialog doesn't put a Material above the card, so text would
    // otherwise fall back to the default underlined style — this supplies one.
    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          // Content clears the notch, but the blue fills right up to y=0.
          padding: EdgeInsets.fromLTRB(22, topInset + 20, 22, 22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2F62E0), Color(0xFF1E45C0), Color(0xFF122E86)],
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF122E86).withValues(alpha: 0.45),
                blurRadius: 34,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(content.icon, color: white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    content.title,
                    style: TextStyle(
                      color: soft,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DefaultTextStyle(
                style: const TextStyle(
                  color: white,
                  fontSize: 19,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: content.sentence,
                ),
              ),
              if (content.stats.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
                const SizedBox(height: 14),
                Row(children: content.stats),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _BriefingContent _contentFor(BuildContext context, AppState state) {
    switch (kind) {
      case BriefingKind.home:
        return _home(state);
      case BriefingKind.expenses:
        return _expenses(state);
      case BriefingKind.analytics:
        return _analytics(state);
      case BriefingKind.planner:
        return _planner(state);
      case BriefingKind.account:
        return _account(state);
    }
  }

  // ---- Home: money on hand -------------------------------------------------
  _BriefingContent _home(AppState state) {
    final name = state.activeProfile?.name;
    final spentToday = state.spentToday;
    final spentMonth = state.spentThisMonth;
    final incomeMonth = state.incomeThisMonth;
    final balance = state.totalBalance;
    final accounts = state.accounts.length;

    return _BriefingContent(
      icon: Icons.auto_awesome_rounded,
      title: name == null ? _greeting() : '${_greeting()}, $name',
      sentence: [
        _plain('You spent '),
        _bold(Money.compact(spentToday)),
        _plain(' today, '),
        _bold(Money.compact(spentMonth)),
        _plain(' this month'),
        if (incomeMonth > 0) ...[
          _plain(' — and earned '),
          _bold(Money.compact(incomeMonth)),
        ],
        _plain('. You hold '),
        _bold(Money.compact(balance)),
        _plain(' across $accounts account${accounts == 1 ? '' : 's'}.'),
      ],
      stats: [
        _Stat(label: 'Today', value: Money.compact(spentToday)),
        _Stat(label: 'This month', value: Money.compact(spentMonth)),
        _Stat(label: 'Balance', value: Money.compact(balance)),
      ],
    );
  }

  // ---- Expenses: this month's spending -------------------------------------
  _BriefingContent _expenses(AppState state) {
    final count = state.expenseCountThisMonth;
    final total = state.spentThisMonth;
    final top = state.topCategoryThisMonth;
    final biggest = state.biggestExpenseThisMonth;

    final sentence = <Widget>[];
    if (count == 0) {
      sentence.add(
        _plain(
          'No expenses logged this month yet — add one and it lands here.',
        ),
      );
    } else {
      sentence.addAll([
        _plain("You've logged "),
        _bold('$count'),
        _plain(count == 1 ? ' expense totalling ' : ' expenses totalling '),
        _bold(Money.compact(total)),
        _plain('.'),
      ]);
      if (top != null) {
        sentence.addAll([
          _plain(' '),
          _bold(top.category.name),
          _plain(' leads at '),
          _bold(Money.compact(top.total)),
          _plain('.'),
        ]);
      }
      if (biggest != null) {
        sentence.addAll([
          _plain(' Your biggest was '),
          _bold(biggest.title),
          _plain(' at '),
          _bold(Money.compact(biggest.amount)),
          _plain('.'),
        ]);
      }
    }

    return _BriefingContent(
      icon: Icons.receipt_long_rounded,
      title: 'This month',
      sentence: sentence,
      stats: [
        _Stat(label: 'Entries', value: '$count'),
        _Stat(
          label: top == null ? 'Top' : 'Top: ${top.category.name}',
          value: top == null ? '—' : Money.compact(top.total),
        ),
        _Stat(
          label: 'Biggest',
          value: biggest == null ? '—' : Money.compact(biggest.amount),
        ),
      ],
    );
  }

  // ---- Analytics: trend ----------------------------------------------------
  _BriefingContent _analytics(AppState state) {
    final thisMonth = state.spentThisMonth;
    final lastMonth = state.spentLastMonth;
    final projected = state.projectedThisMonth;
    final dailyAvg = state.dailyAverageThisMonth;

    final sentence = <Widget>[];
    if (lastMonth <= 0) {
      sentence.addAll([
        _plain("You've spent "),
        _bold(Money.compact(thisMonth)),
        _plain(' so far — about '),
        _bold(Money.compact(projected)),
        _plain(' projected by month-end at '),
        _bold('${Money.compact(dailyAvg)}/day'),
        _plain('.'),
      ]);
    } else {
      final diff = thisMonth - lastMonth;
      final pct = (diff.abs() / lastMonth * 100).round();
      final up = diff > 0;
      sentence.addAll([
        _plain("You're spending "),
        _bold('$pct% ${up ? 'more' : 'less'}'),
        _plain(' than last month ('),
        _bold(Money.compact(lastMonth)),
        _plain("). At this pace you'll reach about "),
        _bold(Money.compact(projected)),
        _plain(' by month-end.'),
      ]);
    }

    return _BriefingContent(
      icon: Icons.trending_up_rounded,
      title: 'Your trend',
      sentence: sentence,
      stats: [
        _Stat(label: 'This month', value: Money.compact(thisMonth)),
        _Stat(label: 'Last month', value: Money.compact(lastMonth)),
        _Stat(label: 'Projected', value: Money.compact(projected)),
      ],
    );
  }

  // ---- Planner: what's ahead -----------------------------------------------
  _BriefingContent _planner(AppState state) {
    final projected = state.projectedThisMonth;
    final daysLeft = state.daysLeftThisMonth;
    final spentMonth = state.spentThisMonth;
    final owed = state.outstandingBalances;
    final owedToYou = owed
        .where((b) => b.theyOweUser)
        .fold<double>(0, (s, b) => s + b.magnitude);
    final youOwe = owed
        .where((b) => !b.theyOweUser)
        .fold<double>(0, (s, b) => s + b.magnitude);
    final overBudgets = state
        .budgetProgress()
        .where((b) => b.fraction > 1)
        .length;

    final sentence = <Widget>[];
    if (daysLeft <= 0) {
      sentence.add(
        _plain("It's the last day of the month — you're on track for about "),
      );
    } else {
      sentence.addAll([
        _plain('With '),
        _bold('$daysLeft ${daysLeft == 1 ? 'day' : 'days'}'),
        _plain(" left this month, you're on track for about "),
      ]);
    }
    sentence.addAll([_bold(Money.compact(projected)), _plain(' spent.')]);
    if (overBudgets > 0) {
      sentence.addAll([
        _plain(' '),
        _bold('$overBudgets ${overBudgets == 1 ? 'budget is' : 'budgets are'}'),
        _plain(' over cap.'),
      ]);
    }
    if (owedToYou > 0) {
      sentence.addAll([
        _plain(' '),
        _bold(Money.compact(owedToYou)),
        _plain(' is owed to you.'),
      ]);
    }
    if (youOwe > 0) {
      sentence.addAll([
        _plain(' You owe '),
        _bold(Money.compact(youOwe)),
        _plain('.'),
      ]);
    }

    return _BriefingContent(
      icon: Icons.event_available_rounded,
      title: 'Looking ahead',
      sentence: sentence,
      stats: [
        _Stat(label: 'Days left', value: '$daysLeft'),
        _Stat(label: 'This month', value: Money.compact(spentMonth)),
        _Stat(label: 'Projected', value: Money.compact(projected)),
      ],
    );
  }

  // ---- Account: one account's own flow -------------------------------------
  _BriefingContent _account(AppState state) {
    final id = accountId;
    // No id, or the account vanished (deleted while open) — fall back to the
    // overview rather than showing an empty island.
    if (id == null) return _home(state);
    final matches = state.accounts.where((a) => a.id == id);
    if (matches.isEmpty) return _home(state);
    final account = matches.first;
    final balance = state.accountBalance(account.id);
    final flow = state.accountFlow(account.id, DateTime.now());

    return _BriefingContent(
      icon: account.icon,
      title: account.name,
      sentence: [
        _bold(account.name),
        _plain(' holds '),
        _bold(Money.compact(balance)),
        _plain('. This month '),
        _bold(Money.compact(flow.inflow)),
        _plain(' came in and '),
        _bold(Money.compact(flow.outflow)),
        _plain(' went out.'),
      ],
      stats: [
        _Stat(label: 'Balance', value: Money.compact(balance)),
        _Stat(label: 'In', value: Money.compact(flow.inflow)),
        _Stat(label: 'Out', value: Money.compact(flow.outflow)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.66),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
