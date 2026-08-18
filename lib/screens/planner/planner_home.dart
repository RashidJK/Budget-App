import 'package:flutter/material.dart';

import '../../models/scenario.dart';
import '../../theme.dart';
import '../../widgets/app_background.dart';
import '../scenarios/scenario_list.dart';
import 'business.dart';
import 'daily_habit.dart';
import 'fuel.dart';
import 'projection.dart';
import 'savings.dart';
import 'subscriptions.dart';

/// One entry in the planner menu.
class PlannerTool {
  const PlannerTool({
    required this.kind,
    required this.title,
    required this.description,
    required this.icon,
    required this.builder,
  });

  final ScenarioKind kind;
  final String title;
  final String description;
  final IconData icon;

  /// Builds the tool, optionally pre-filled from a saved scenario.
  final Widget Function(Scenario? scenario) builder;

  /// The six calculators, in the order the spec lists them.
  static const List<PlannerTool> all = [
    PlannerTool(
      kind: ScenarioKind.dailyHabit,
      title: 'Daily Habit Calculator',
      description: 'What a repeating spend costs per day, month and year',
      icon: Icons.local_cafe_rounded,
      builder: _dailyHabit,
    ),
    PlannerTool(
      kind: ScenarioKind.fuel,
      title: 'Fuel Calculator',
      description: 'Litres and shillings from distance and efficiency',
      icon: Icons.local_gas_station_rounded,
      builder: _fuel,
    ),
    PlannerTool(
      kind: ScenarioKind.subscriptions,
      title: 'Subscription Planner',
      description: 'Every recurring service, totalled and dated',
      icon: Icons.autorenew_rounded,
      builder: _subscriptions,
    ),
    PlannerTool(
      kind: ScenarioKind.business,
      title: 'Business Cost Planner',
      description: 'Operating costs and the revenue needed to cover them',
      icon: Icons.storefront_rounded,
      builder: _business,
    ),
    PlannerTool(
      kind: ScenarioKind.savings,
      title: 'Savings Simulator',
      description: 'Compare a habit against a cheaper alternative',
      icon: Icons.savings_rounded,
      builder: _savings,
    ),
    PlannerTool(
      kind: ScenarioKind.projection,
      title: 'Long-Term Projection',
      description: 'Where a habit lands over 1, 3, 5 and 10 years',
      icon: Icons.timeline_rounded,
      builder: _projection,
    ),
  ];

  static PlannerTool forKind(ScenarioKind kind) =>
      all.firstWhere((tool) => tool.kind == kind);

  // Torn off as top-level functions so the list above can stay `const`.
  static Widget _dailyHabit(Scenario? s) => DailyHabitScreen(scenario: s);
  static Widget _fuel(Scenario? s) => FuelScreen(scenario: s);
  static Widget _subscriptions(Scenario? s) => SubscriptionsScreen(scenario: s);
  static Widget _business(Scenario? s) => BusinessScreen(scenario: s);
  static Widget _savings(Scenario? s) => SavingsScreen(scenario: s);
  static Widget _projection(Scenario? s) => ProjectionScreen(scenario: s);
}

/// Opens a planner tool, optionally pre-filled from [scenario].
Future<void> openPlannerTool(
  BuildContext context,
  PlannerTool tool, {
  Scenario? scenario,
}) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => tool.builder(scenario)));
}

/// The planner menu.
class PlannerHomeScreen extends StatelessWidget {
  const PlannerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Planner'),
        actions: [
          // Saved scenarios live with the Planner now, reached from here rather
          // than a bottom-nav tab of their own.
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ScenarioListScreen(),
              ),
            ),
            tooltip: 'Saved scenarios',
            icon: const Icon(Icons.bookmark_outline_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AppBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'Work out what something will cost before you spend it. Nothing '
              'here touches your tracked expenses — change any number and the '
              'results update as you type.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            for (final tool in PlannerTool.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ToolCard(tool: tool),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool});

  final PlannerTool tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = context.scheme.primary;

    return Card(
      child: InkWell(
        onTap: () => openPlannerTool(context, tool),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: context.isDark ? 0.24 : 0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(tool.icon, color: accent, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tool.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      tool.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: context.muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
