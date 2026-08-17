import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:home_widget/home_widget.dart';

import '../command/command_bar.dart';
import '../theme.dart';
import 'analytics/analytics_screen.dart';
import 'planner/planner_home.dart';
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
  int _index = 0;
  StreamSubscription<Uri?>? _widgetClicks;

  void _select(int index) => setState(() => _index = index);

  @override
  void initState() {
    super.initState();
    // The Quick Add home-screen widget opens the app on a "budget://" link;
    // route it to the matching capture flow. iOS-only, so tests and other
    // platforms skip the platform channels entirely.
    if (Platform.isIOS) {
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
    return Scaffold(
      extendBody: true,
      // A quick-add button on the Home tab only. It lives on this shell
      // Scaffold — the one that owns the nav bar — so it floats cleanly above
      // the floating nav pill. A FAB on the nested dashboard Scaffold would
      // instead sit against the screen bottom, behind the nav.
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              onPressed: () => AddExpenseSheet.show(context),
              tooltip: 'Add expense',
              child: const Icon(Icons.add_rounded),
            )
          : null,
      // IndexedStack preserves each tab's scroll position and the planner's
      // half-entered inputs when the user pops between tabs.
      body: IndexedStack(
        index: _index,
        children: [
          DashboardScreen(onSeePlanner: () => _select(3)),
          const ExpenseListScreen(),
          const AnalyticsScreen(),
          const PlannerHomeScreen(),
        ],
      ),
      bottomNavigationBar: _BudgetNavBar(
        index: _index,
        onSelect: _select,
        // The centre + is the universal command bar — capture first (spec §4).
        onAdd: () => CommandBar.show(context),
      ),
    );
  }
}

/// Custom bottom bar with a raised centre action.
///
/// A plain [NavigationBar] can't dock a centre button, so this is hand-built:
/// two destinations, the add button, two more destinations, on a rounded
/// floating surface.
class _BudgetNavBar extends StatelessWidget {
  const _BudgetNavBar({
    required this.index,
    required this.onSelect,
    required this.onAdd,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    // Translucent fill over the blur — opaque enough that the icons stay
    // readable over any content that scrolls behind, frosted enough to read as
    // glass.
    final fill = dark
        ? const Color(0xFF232322).withValues(alpha: 0.62)
        : Colors.white.withValues(alpha: 0.7);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DecoratedBox(
          // The shadow sits behind the clipped glass.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.3 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: 66,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: dark ? 0.14 : 0.6),
                  ),
                ),
                child: Row(
                  children: [
                    _NavItem(
                      icon: Icons.grid_view_outlined,
                      activeIcon: Icons.grid_view_rounded,
                      label: 'Home',
                      selected: index == 0,
                      onTap: () => onSelect(0),
                    ),
                    _NavItem(
                      icon: Icons.receipt_long_outlined,
                      activeIcon: Icons.receipt_long_rounded,
                      label: 'Expenses',
                      selected: index == 1,
                      onTap: () => onSelect(1),
                    ),
                    _AddButton(onTap: onAdd),
                    _NavItem(
                      icon: Icons.pie_chart_outline_rounded,
                      activeIcon: Icons.pie_chart_rounded,
                      label: 'Analytics',
                      selected: index == 2,
                      onTap: () => onSelect(2),
                    ),
                    _NavItem(
                      icon: Icons.calculate_outlined,
                      activeIcon: Icons.calculate_rounded,
                      label: 'Planner',
                      selected: index == 3,
                      onTap: () => onSelect(3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.scheme.primary : context.muted;

    return Expanded(
      child: MergeSemantics(
        // Screen readers otherwise get only the label; announce the tab role
        // and which one is currently selected.
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            borderRadius: BorderRadius.circular(16),
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(selected ? activeIcon : icon, size: 23, color: color),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The raised centre add button.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: MergeSemantics(
          // The app's primary capture action is icon-only; give it a name so
          // it isn't announced as a bare "button".
          child: Semantics(
            button: true,
            label: 'Add or capture',
            child: Container(
              // Shadow sits on an outer box so the Material below can clip the
              // ripple to the rounded shape.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: context.scheme.primary.withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Material(
                color: context.scheme.primary,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onTap();
                  },
                  borderRadius: BorderRadius.circular(18),
                  splashColor: Colors.white.withValues(alpha: 0.2),
                  child: const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
