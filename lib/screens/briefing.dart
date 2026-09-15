import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/format.dart';
import '../state/app_state.dart';

/// A blue "briefing" island — a friendly, at-a-glance summary of where your
/// money stands. Drops down from the very top edge of the screen (bleeding
/// behind the status bar), opened from the bar.
Future<void> showBriefing(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Briefing',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 360),
    pageBuilder: (_, _, _) => const _BriefingCard(),
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
    // Bleed up behind the status bar rather than floating below it, so the
    // island reads as dropping in from the very top edge of the screen.
    final topInset = MediaQuery.paddingOf(context).top;

    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.72);
    Widget num(String s) => Text(
      s,
      style: const TextStyle(fontWeight: FontWeight.w800),
      textScaler: TextScaler.noScaling,
    );

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        // Content clears the notch, but the blue fills right up to y=0.
        padding: EdgeInsets.fromLTRB(22, topInset + 20, 22, 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5B9BFF), Color(0xFF2F6BEE), Color(0xFF1E4FD8)],
          ),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E4FD8).withValues(alpha: 0.42),
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
                  Text(' across $accounts account${accounts == 1 ? '' : 's'}.'),
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
