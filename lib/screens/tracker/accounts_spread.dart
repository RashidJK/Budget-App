import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../services/format.dart';
import '../../state/app_state.dart';
import '../manage/account_detail_screen.dart';
import '../manage/accounts_screen.dart';

/// The "wallet spread" — every account fanned out as a large, scrollable card,
/// revealed by pinching the dashboard's stacked deck. Each card wears the
/// account's own colour with its balance on a glass pill and its name writ
/// large, echoing a stack of physical cards laid out flat.
Future<void> showAccountsSpread(BuildContext context) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => const _AccountsSpread(),
      transitionsBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        // Grows out of the deck: a gentle scale-up with a fade.
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class _AccountsSpread extends StatelessWidget {
  const _AccountsSpread();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final balances = state.accountBalances; // largest balance first
    final media = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0C1210),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, media.padding.top + 14, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Accounts',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Money.format(state.totalBalance),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: 'Close',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                  ),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: balances.isEmpty
                ? const _EmptySpread()
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      6,
                      16,
                      24 + media.padding.bottom,
                    ),
                    itemCount: balances.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, i) =>
                        _SpreadCard(balance: balances[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SpreadCard extends StatelessWidget {
  const _SpreadCard({required this.balance});

  final AccountBalance balance;

  @override
  Widget build(BuildContext context) {
    final account = balance.account;
    final color = account.of(context);

    return GestureDetector(
      onTap: () => AccountDetailScreen.open(context, account.id),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 232,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The account's own colour, deepening across the card.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, _darken(color, 0.32)],
                  ),
                ),
              ),
              // A bottom scrim so the big white name always reads.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x59000000)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _GlassPill(
                          child: Text(
                            Money.compact(balance.balance),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        const Spacer(),
                        _MoreButton(account: account),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                        letterSpacing: -0.5,
                      ),
                    ),
                    // Skip the type when it just repeats the name (e.g. "Cash").
                    if (account.type.label != account.name) ...[
                      const SizedBox(height: 2),
                      Text(
                        account.type.label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ⋯ menu on a spread card.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: PopupMenuButton<int>(
          tooltip: 'Options',
          color: const Color(0xFF1C221E),
          icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.20),
          ),
          onSelected: (v) {
            switch (v) {
              case 0:
                AccountDetailScreen.open(context, account.id);
              case 1:
                AccountsScreen.open(context);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 0, child: Text('Open account')),
            PopupMenuItem(value: 1, child: Text('Manage accounts')),
          ],
        ),
      ),
    );
  }
}

/// A frosted-glass capsule for the balance chip.
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _EmptySpread extends StatelessWidget {
  const _EmptySpread();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet_rounded,
              size: 40,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 14),
            Text(
              'No accounts yet',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => AccountsScreen.open(context),
              child: const Text('Add an account'),
            ),
          ],
        ),
      ),
    );
  }
}

Color _darken(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}
