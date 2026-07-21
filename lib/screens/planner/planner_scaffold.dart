import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/scenario.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

/// Shared chrome for the six planner tools.
///
/// Every tool recalculates live and needs no save step to be useful — the spec
/// is explicit that saving is opt-in. This widget supplies the one piece they
/// all share: naming a set of inputs and keeping it up to date afterwards.
///
/// [collect] is called at save time to snapshot the current inputs. Each tool
/// returns its own keys; see [Scenario.data].
class PlannerPage extends StatefulWidget {
  const PlannerPage({
    super.key,
    required this.title,
    required this.kind,
    required this.collect,
    required this.children,
    this.subtitle,
    this.loadedScenarioId,
    this.canSave = true,
  });

  final String title;
  final String? subtitle;
  final ScenarioKind kind;

  /// Snapshots the tool's current inputs for persistence.
  final Map<String, dynamic> Function() collect;

  final List<Widget> children;

  /// Set when the tool was opened from a saved scenario, which switches the
  /// action from "Save" to "Update".
  final String? loadedScenarioId;

  final bool canSave;

  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  String? _scenarioId;

  @override
  void initState() {
    super.initState();
    _scenarioId = widget.loadedScenarioId;
  }

  bool get _isTracking => _scenarioId != null;

  Future<void> _save() async {
    final state = context.read<AppState>();

    if (_isTracking) {
      await state.updateScenario(_scenarioId!, data: widget.collect());
      _notify('Scenario updated');
      return;
    }

    final name = await _askForName();
    if (name == null || !mounted) return;

    final scenario = await state.saveScenario(
      name: name,
      kind: widget.kind,
      data: widget.collect(),
    );

    // Holding the new id turns every later tap into an update, so a user who
    // keeps tweaking doesn't end up with six near-identical scenarios.
    if (mounted) setState(() => _scenarioId = scenario.id);
    _notify('Saved "$name"');
  }

  Future<String?> _askForName() {
    final controller = TextEditingController(text: widget.title);

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this scenario'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'My Monthly Budget'),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(_clean(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_clean(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Falls back to the tool's name rather than saving an unnamed scenario the
  /// user would not recognise in the list later.
  String _clean(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? widget.title : trimmed;
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.muted,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        actions: [
          if (widget.canSave)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _save,
                icon: Icon(
                  _isTracking
                      ? Icons.check_circle_outline_rounded
                      : Icons.bookmark_add_outlined,
                  size: 19,
                ),
                label: Text(_isTracking ? 'Update' : 'Save'),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: widget.children,
      ),
    );
  }
}

/// Vertical rhythm between planner blocks, so all six tools breathe alike.
const SizedBox plannerGap = SizedBox(height: 16);
const SizedBox plannerFieldGap = SizedBox(height: 18);
