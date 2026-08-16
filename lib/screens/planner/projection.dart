import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../models/scenario.dart';
import '../../planner/engine.dart';
import '../../services/format.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/inputs.dart';
import '../../widgets/stat.dart';
import 'planner_scaffold.dart';

/// "What does this habit cost me over ten years?"
class ProjectionScreen extends StatefulWidget {
  const ProjectionScreen({super.key, this.scenario});

  final Scenario? scenario;

  @override
  State<ProjectionScreen> createState() => _ProjectionScreenState();
}

class _ProjectionScreenState extends State<ProjectionScreen> {
  late final TextEditingController _amount;

  late String _categoryId;
  late Frequency _frequency;
  late double _customDays;
  late double _parsedAmount;
  late double _inflation;

  @override
  void initState() {
    super.initState();
    final scenario = widget.scenario;

    _parsedAmount = scenario?.number('amount') ?? 5000;
    _amount = TextEditingController(text: Money.number(_parsedAmount));
    _categoryId = scenario?.text('categoryId', 'eating_out') ?? 'eating_out';
    _customDays = scenario?.number('customDays', 15) ?? 15;
    _inflation = scenario?.number('inflation') ?? 0;

    final stored = scenario?.text('frequency');
    _frequency = Frequency.fromName(stored);
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
    final horizons = project(breakdown: _breakdown, annualIncrease: _inflation);

    return {
      'amount': _parsedAmount,
      'categoryId': _categoryId,
      'frequency': _frequency.name,
      'customDays': _customDays,
      'inflation': _inflation,
      '_summaryYearly': _breakdown.yearly,
      '_summaryLabel':
          '${Money.compact(horizons.last.cumulative)} over 10 years',
    };
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = _breakdown;
    final category = context.read<AppState>().categoryById(_categoryId);
    final accent = category.of(context);

    final horizons = project(breakdown: breakdown, annualIncrease: _inflation);
    final series = projectSeries(
      breakdown: breakdown,
      annualIncrease: _inflation,
    );

    return PlannerPage(
      title: 'Long-Term Projection',
      subtitle: 'Where a habit lands in ten years',
      kind: ScenarioKind.projection,
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
        SectionCard(
          title: 'Cumulative spending',
          child: Column(
            children: [
              ProjectionChart(points: series, color: accent),
              const SizedBox(height: 8),
              _InflationSlider(
                rate: _inflation,
                onChanged: (value) => setState(() => _inflation = value),
              ),
            ],
          ),
        ),
        plannerGap,
        StatGrid(
          tiles: [
            for (final point in horizons)
              StatTile(
                label:
                    '${point.years.round()} '
                    '${point.years == 1 ? 'year' : 'years'}',
                value: point.cumulative,
                accent: accent,
                compact: true,
              ),
          ],
        ),
        plannerGap,
        InsightCard(message: _insight(horizons), icon: Icons.timeline_rounded),
      ],
    );
  }

  String _insight(List<ProjectionPoint> horizons) {
    if (_parsedAmount <= 0) {
      return 'Enter an amount to project it forward.';
    }

    final fiveYears = horizons.firstWhere(
      (point) => point.years == 5,
      orElse: () => horizons.last,
    );
    final tenYears = horizons.last;
    final habit = context
        .read<AppState>()
        .categoryById(_categoryId)
        .name
        .toLowerCase();

    final inflationNote = _inflation > 0
        ? ' That assumes prices rise ${Money.percent(_inflation)} a year.'
        : '';

    return 'Spending ${Money.format(_parsedAmount)} on $habit '
        '${frequencyPhrase(_frequency, _customDays)} adds up to about '
        '${Money.spoken(fiveYears.cumulative)} over five years, and '
        '${Money.spoken(tenYears.cumulative)} over ten.$inflationNote';
  }
}

class _InflationSlider extends StatelessWidget {
  const _InflationSlider({required this.rate, required this.onChanged});

  final double rate;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Yearly price rise',
              style: theme.textTheme.labelMedium?.copyWith(
                color: context.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              rate == 0 ? 'Off' : Money.percent(rate),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: rate.clamp(0.0, 0.20),
          max: 0.20,
          divisions: 20,
          label: rate == 0 ? 'Off' : Money.percent(rate),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
