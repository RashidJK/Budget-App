import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../command/command_bar.dart';
import '../models/phosphor.dart';
import 'briefing.dart';
import '../widgets/morph_nav_bar.dart';
import '../theme.dart';
import 'analytics/analytics_screen.dart';
import 'planner/planner_home.dart';
import 'quick_capture.dart';
import 'tracker/add_expense.dart';
import 'tracker/dashboard.dart';
import 'tracker/expense_list.dart';

/// Root navigation.
///
/// Four destinations around a raised centre "add" button:
///
///   Home · Expenses · [ + ] · Analytics · Planner
///
/// Adding an expense is the single most frequent action, so it gets the centre
/// button rather than a tab — it opens a sheet over whatever tab you are on,
/// never navigating away. Saved planner scenarios moved into the Planner tab's
/// own header, since that is where they belong conceptually and it freed the
/// slot Analytics now fills.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _items = [
    MorphNavItem(
      icon: PhosphorR.squaresFour,
      activeIcon: PhosphorF.squaresFour,
      label: 'Home',
    ),
    MorphNavItem(
      icon: PhosphorR.receipt,
      activeIcon: PhosphorF.receipt,
      label: 'Expenses',
    ),
    MorphNavItem(
      icon: PhosphorR.chartPie,
      activeIcon: PhosphorF.chartPie,
      label: 'Analytics',
    ),
    MorphNavItem(
      icon: PhosphorR.calculator,
      activeIcon: PhosphorF.calculator,
      label: 'Planner',
    ),
  ];

  static const _desktopBreakpoint = 900.0;

  int _index = 0;
  StreamSubscription<Uri?>? _widgetClicks;

  void _select(int index) => setState(() => _index = index);

  // The briefing summarises whichever tab is showing.
  BriefingKind get _briefingKind => switch (_index) {
    1 => BriefingKind.expenses,
    2 => BriefingKind.analytics,
    3 => BriefingKind.planner,
    _ => BriefingKind.home,
  };

  @override
  void initState() {
    super.initState();
    // The Quick Add home-screen widget opens the app on a "budget://" link;
    // route it to the matching capture flow. iOS-only, so tests and other
    // platforms skip the platform channels entirely.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _listenForWidgetLaunch();
    }
  }

  Future<void> _listenForWidgetLaunch() async {
    try {
      final launch = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (launch != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _handleWidgetUri(launch),
        );
      }
    } catch (_) {
      // No widget launch / plugin unavailable — nothing to route.
    }
    _widgetClicks = HomeWidget.widgetClicked.listen((uri) {
      if (uri != null) _handleWidgetUri(uri);
    });
  }

  void _handleWidgetUri(Uri uri) {
    if (!mounted) return;
    switch (uri.host) {
      case 'add':
        AddExpenseSheet.show(context);
      case 'income':
        CommandBar.show(context, initialText: 'Received ');
      case 'transfer':
        CommandBar.show(context, initialText: 'Transfer ');
      case 'scan':
        CommandBar.show(context);
    }
  }

  @override
  void dispose() {
    _widgetClicks?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSidebar = constraints.maxWidth >= _desktopBreakpoint;
        return Scaffold(
          extendBody: !useSidebar,
          // IndexedStack preserves each tab's scroll position and the planner's
          // half-entered inputs when the user pops between tabs.
          body: Row(
            children: [
              if (useSidebar)
                _DesktopSidebar(
                  items: _items,
                  selectedIndex: _index,
                  onSelect: _select,
                  onCapture: () => CommandBar.show(context),
                  onBriefing: () => showBriefing(context, kind: _briefingKind),
                ),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [
                    DashboardScreen(onSeePlanner: () => _select(3)),
                    const ExpenseListScreen(),
                    const AnalyticsScreen(),
                    const PlannerHomeScreen(),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: useSidebar
              ? null
              : MorphNavBar(
                  activeIndex: _index,
                  onSelect: _select,
                  onCapture: (text) => captureFromText(context, text),
                  onScan: kIsWeb
                      ? null
                      : () => CommandBar.show(context, startScan: true),
                  onBriefing: () => showBriefing(context, kind: _briefingKind),
                  items: _items,
                ),
        );
      },
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.onCapture,
    required this.onBriefing,
  });

  final List<MorphNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onCapture;
  final VoidCallback onBriefing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: context.card,
        border: Border(right: BorderSide(color: context.hairline)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 28),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: scheme.onPrimary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Text(
                      'Budget',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _SidebarDestination(
                    item: items[i],
                    selected: selectedIndex == i,
                    onTap: () => onSelect(i),
                  ),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onCapture,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add or capture'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandGreen,
                  foregroundColor: const Color(0xFF10231A),
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onBriefing,
                icon: const Icon(Icons.auto_awesome_rounded, size: 19),
                label: const Text('Your briefing'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarDestination extends StatelessWidget {
  const _SidebarDestination({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final MorphNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.scheme.primary : context.muted;
    return Semantics(
      key: ValueKey('desktop-nav-${item.label.toLowerCase()}'),
      button: true,
      selected: selected,
      label: item.label,
      child: Material(
        color: selected
            ? context.scheme.primary.withValues(
                alpha: context.isDark ? 0.2 : 0.1,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(
                  selected ? item.activeIcon : item.icon,
                  color: selected ? (item.accent ?? color) : color,
                  size: 21,
                ),
                const SizedBox(width: 13),
                Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selected ? context.scheme.onSurface : context.muted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
