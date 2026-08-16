import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/category.dart';
import '../../state/app_state.dart';
import '../../models/scenario.dart';
import '../../planner/engine.dart';
import '../../services/format.dart';
import '../../widgets/inputs.dart';
import '../../widgets/stat.dart';
import 'planner_scaffold.dart';

/// "If I spend TSh 5,000 every day on lunch, what does that cost me?"
class DailyHabitScreen extends StatefulWidget {
  const DailyHabitScreen({super.key, this.scenario});

  /// Pre-fills the tool from a saved scenario.
  final Scenario? scenario;

  @override
  State<DailyHabitScreen> createState() => _DailyHabitScreenState();
}

class _DailyHabitScreenState extends State<DailyHabitScreen> {
  late final TextEditingController _amount;

  late String _categoryId;
  late Frequency _frequency;
  late double _customDays;
  late double _parsedAmount;

  @override
  void initState() {
    super.initState();
    final scenario = widget.scenario;

    _parsedAmount = scenario?.number('amount') ?? 5000;
    _amount = TextEditingController(text: Money.number(_parsedAmount));
    _categoryId = scenario?.text('categoryId', 'eating_out') ?? 'eating_out';
    _frequency = _frequencyFrom(scenario);
    _customDays = scenario?.number('customDays', 15) ?? 15;
  }

  Frequency _frequencyFrom(Scenario? scenario) {
    final stored = scenario?.text('frequency');
    return Frequency.fromName(stored);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  CostBreakdown get _breakdown => breakdownFor(
    amount: _parsedAmount,
    frequency: _frequency,
    customDaysPerMonth: _customDays,
  );

  Map<String, dynamic> _collect() {
    final breakdown = _breakdown;
    final category = context.read<AppState>().categoryById(_categoryId);

    return {
      'amount': _parsedAmount,
      'categoryId': _categoryId,
      'frequency': _frequency.name,
      'customDays': _customDays,
      // Cached so the saved-scenario list can show a figure without
      // re-running the calculator for every row.
      '_summaryYearly': breakdown.yearly,
      '_summaryLabel':
          '${category.name} · ${Money.format(_parsedAmount)} '
          '${frequencyPhrase(_frequency, _customDays)}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = _breakdown;
    final category = context.read<AppState>().categoryById(_categoryId);
    final accent = category.of(context);

    return PlannerPage(
      title: 'Daily Habit',
      subtitle: 'What a repeating spend really costs',
      kind: ScenarioKind.dailyHabit,
      collect: _collect,
      loadedScenarioId: widget.scenario?.id,
      children: [
        SectionCard(
          child: Column(
            children: [
              CategoryPicker(
                selectedId: _categoryId,
                onChanged: (id) => setState(() => _categoryId = id),
              ),
              plannerFieldGap,
              NumberField(
                controller: _amount,
                label: 'Amount per time',
                prefix: Money.symbol,
                onChanged: (value) => setState(() => _parsedAmount = value),
              ),
              plannerFieldGap,
              FrequencyPicker(
                value: _frequency,
                onChanged: (value) => setState(() => _frequency = value),
                customDays: _customDays,
                onCustomDaysChanged: (value) =>
                    setState(() => _customDays = value),
              ),
            ],
          ),
        ),
        plannerGap,
        StatGrid(
          tiles: [
            StatTile(label: 'Daily', value: breakdown.daily, accent: accent),
            StatTile(label: 'Weekly', value: breakdown.weekly, accent: accent),
            StatTile(
              label: 'Monthly',
              value: breakdown.monthly,
              accent: accent,
            ),
            StatTile(label: 'Yearly', value: breakdown.yearly, accent: accent),
          ],
        ),
        plannerGap,
        InsightCard(message: _insight(category, breakdown)),
      ],
    );
  }

  /// Turns the numbers into the sentence the spec asks for.
  ///
  /// The yearly figure is the one that changes minds, so it leads — and it is
  /// spoken ("1.8 million") rather than written out in full, which is easier
  /// to hold in your head.
  String _insight(ExpenseCategory category, CostBreakdown breakdown) {
    if (_parsedAmount <= 0) {
      return 'Enter an amount to see what this habit adds up to.';
    }

    final habit = category.name.toLowerCase();
    final phrase = frequencyPhrase(_frequency, _customDays);

    return 'If you keep spending ${Money.format(_parsedAmount)} on $habit '
        '$phrase, that is about ${Money.spoken(breakdown.yearly)} a year — '
        'roughly ${Money.format(breakdown.monthly)} every month.';
  }
}
