import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/format.dart';
import '../state/app_state.dart';

/// A floating blue "briefing" island — a friendly, at-a-glance summary of where
/// your money stands, opened from the nav bar.
Future<void> showBriefing(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (_) => const _BriefingCard(),
  );
}

class _BriefingCard extends StatelessWidget {
  const _BriefingCard();

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final name = state.activeProfile?.name;
    final spentToday = state.spentToday;
    final spentMonth = state.spentThisMonth;
    final incomeMonth = state.incomeThisMonth;
    final balance = state.totalBalance;
    final accounts = state.accounts.length;

    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.72);
    Widget num(String s) => Text(
      s,
      style: const TextStyle(fontWeight: FontWeight.w800),
      textScaler: TextScaler.noScaling,
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 6,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3B82F6), Color(0xFF2458E6)],
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2458E6).withValues(alpha: 0.4),
              blurRadius: 30,
              offset: const Offset(0, 14),
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
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  name == null ? _greeting() : '${_greeting()}, $name',
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
                children: [
                  const Text('You spent '),
                  num(Money.compact(spentToday)),
                  const Text(' today, '),
                  num(Money.compact(spentMonth)),
                  const Text(' this month'),
                  if (incomeMonth > 0) ...[
                    const Text(' — and earned '),
                    num(Money.compact(incomeMonth)),
                  ],
                  const Text('. You hold '),
                  num(Money.compact(balance)),
                  Text(
                    ' across $accounts account${accounts == 1 ? '' : 's'}.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.16)),
            const SizedBox(height: 14),
            Row(
              children: [
                _Stat(label: 'Today', value: Money.compact(spentToday)),
                _Stat(label: 'This month', value: Money.compact(spentMonth)),
                _Stat(label: 'Balance', value: Money.compact(balance)),
              ],
            ),
          ],
        ),
      ),
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
          ),
        ],
      ),
    );
  }
}
