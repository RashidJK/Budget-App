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
  const HomeShell({super.key, this.onBackToSpaces});

  final VoidCallback? onBackToSpaces;

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
  bool _sidebarCollapsed = false;
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
                  onBackToSpaces: widget.onBackToSpaces,
                  collapsed: _sidebarCollapsed,
                  onToggleCollapsed: () =>
                      setState(() => _sidebarCollapsed = !_sidebarCollapsed),
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
                  onSpaces: widget.onBackToSpaces,
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
    required this.collapsed,
    required this.onToggleCollapsed,
    this.onBackToSpaces,
  });

  final List<MorphNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onCapture;
  final VoidCallback onBriefing;
  final VoidCallback? onBackToSpaces;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('desktop-sidebar'),
      width: collapsed ? 76 : 240,
      decoration: BoxDecoration(
        color: context.card,
        border: Border(right: BorderSide(color: context.hairline)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            collapsed ? 10 : 16,
            18,
            collapsed ? 10 : 16,
            16,
          ),
          child: Column(
            crossAxisAlignment: collapsed
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.stretch,
            children: [
              _SidebarHeader(
                collapsed: collapsed,
                onToggleCollapsed: onToggleCollapsed,
                foreground: scheme.onPrimary,
              ),
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _SidebarDestination(
                    item: items[i],
                    selected: selectedIndex == i,
                    collapsed: collapsed,
                    onTap: () => onSelect(i),
                  ),
                ),
              const Spacer(),
              if (onBackToSpaces != null && !collapsed) ...[
                OutlinedButton.icon(
                  key: const ValueKey('spaces-back-button'),
                  onPressed: onBackToSpaces,
                  icon: const Icon(Icons.grid_view_rounded, size: 19),
                  label: const Text('Spaces'),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size.fromHeight(44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
                const SizedBox(height: 8),
              ] else if (onBackToSpaces != null) ...[
                _SidebarIconAction(
                  key: const ValueKey('spaces-back-button'),
                  icon: Icons.grid_view_rounded,
                  label: 'Spaces',
                  onPressed: onBackToSpaces!,
                ),
                const SizedBox(height: 8),
              ],
              if (collapsed)
                _SidebarIconAction(
                  icon: Icons.add_rounded,
                  label: 'Add or capture',
                  onPressed: onCapture,
                  filled: true,
                )
              else
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
              if (collapsed)
                _SidebarIconAction(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Your briefing',
                  onPressed: onBriefing,
                )
              else
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

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.foreground,
  });

  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.account_balance_wallet_rounded,
        color: foreground,
        size: 20,
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(collapsed ? 0 : 8, 4, collapsed ? 0 : 4, 24),
      child: collapsed
          ? Column(
              children: [
                Tooltip(message: 'Budget', child: logo),
                const SizedBox(height: 8),
                IconButton(
                  key: const ValueKey('sidebar-toggle'),
                  onPressed: onToggleCollapsed,
                  tooltip: 'Expand sidebar',
                  icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                ),
              ],
            )
          : Row(
              children: [
                logo,
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Budget',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('sidebar-toggle'),
                  onPressed: onToggleCollapsed,
                  tooltip: 'Collapse sidebar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                ),
              ],
            ),
    );
  }
}

class _SidebarIconAction extends StatelessWidget {
  const _SidebarIconAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon),
      style: filled
          ? IconButton.styleFrom(
              backgroundColor: AppTheme.brandGreen,
              foregroundColor: const Color(0xFF10231A),
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            )
          : null,
    );
    return button;
  }
}

class _SidebarDestination extends StatelessWidget {
  const _SidebarDestination({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final MorphNavItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.scheme.primary : context.muted;
    final destination = Semantics(
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
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 14,
              vertical: 13,
            ),
            child: collapsed
                ? Center(
                    child: Icon(
                      selected ? item.activeIcon : item.icon,
                      color: selected ? (item.accent ?? color) : color,
                      size: 21,
                    ),
                  )
                : Row(
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
                          color: selected
                              ? context.scheme.onSurface
                              : context.muted,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
    return collapsed
        ? Tooltip(message: item.label, child: destination)
        : destination;
  }
}
