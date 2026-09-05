import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../command/command_bar.dart';
import '../models/phosphor.dart';
import '../widgets/morph_nav_bar.dart';
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
      // No FAB: the nav bar's "+" now raises the capture menu (Add expense,
      // Income, Transfer, Scan) from every screen, so a separate Home FAB would
      // just be a second green "+" stacked on the same corner.
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
      // The centre + is the universal command bar — capture first (spec §4).
      // The bar's destinations are supplied per screen, so it morphs as you
      // move deeper (e.g. into an account); here it's the home shell's tabs.
      bottomNavigationBar: MorphNavBar(
        activeIndex: _index,
        onSelect: _select,
        onCapture: (text) => captureFromText(context, text),
        items: const [
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
        ],
      ),
    );
  }
}
