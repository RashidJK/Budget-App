import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/scenario.dart';
import '../../services/format.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/inputs.dart';
import '../planner/planner_home.dart';

/// Saved planning scenarios — "My Monthly Budget", "Fuel for Work",
/// "Opening a Coffee Shop".
class ScenarioListScreen extends StatelessWidget {
  const ScenarioListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scenarios = state.scenarios;

    return Scaffold(
      appBar: AppBar(title: const Text('Saved scenarios')),
      body: scenarios.isEmpty
          ? const EmptyState(
              icon: Icons.bookmark_rounded,
              title: 'No saved scenarios',
              message:
                  'Work something out in the Planner, then tap Save to keep '
                  'it here. Saved scenarios can be reopened, edited, '
                  'duplicated or deleted.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: scenarios.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ScenarioCard(scenario: scenarios[index]),
              ),
            ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({required this.scenario});

  final Scenario scenario;

  void _open(BuildContext context) {
    openPlannerTool(
      context,
      PlannerTool.forKind(scenario.kind),
      scenario: scenario,
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: scenario.name);
    final state = context.read<AppState>();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename scenario'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      await state.updateScenario(scenario.id, name: trimmed);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final state = context.read<AppState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${scenario.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await state.deleteScenario(scenario.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tool = PlannerTool.forKind(scenario.kind);
    final accent = context.scheme.primary;

    return Card(
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(tool.icon, size: 19, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      scenario.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _ScenarioMenu(
                    onOpen: () => _open(context),
                    onRename: () => _rename(context),
                    onDuplicate: () =>
                        context.read<AppState>().duplicateScenario(scenario.id),
                    onDelete: () => _confirmDelete(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                scenario.summaryLabel.isEmpty
                    ? scenario.kind.label
                    : scenario.summaryLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scenario.kind == ScenarioKind.savings
                              ? 'Yearly saving'
                              : 'Yearly total',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: context.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          Money.format(scenario.summaryYearly),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Edited ${Dates.relative(scenario.updatedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScenarioMenu extends StatelessWidget {
  const _ScenarioMenu({
    required this.onOpen,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz_rounded, color: context.muted),
      onSelected: (action) {
        switch (action) {
          case 'open':
            onOpen();
          case 'rename':
            onRename();
          case 'duplicate':
            onDuplicate();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'open', child: Text('Open & edit')),
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}
