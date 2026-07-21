import 'package:flutter/material.dart';

import '../../models/palette.dart';
import '../../models/scenario.dart';
import '../../planner/engine.dart';
import '../../services/format.dart';
import '../../widgets/inputs.dart';
import '../../widgets/stat.dart';
import 'planner_scaffold.dart';

/// "If I drive 60 km every day, what does fuel cost me?"
class FuelScreen extends StatefulWidget {
  const FuelScreen({super.key, this.scenario});

  final Scenario? scenario;

  @override
  State<FuelScreen> createState() => _FuelScreenState();
}

class _FuelScreenState extends State<FuelScreen> {
  late final TextEditingController _distance;
  late final TextEditingController _efficiency;
  late final TextEditingController _price;

  late double _parsedDistance;
  late double _parsedEfficiency;
  late double _parsedPrice;
  late Frequency _frequency;
  late double _customDays;

  @override
  void initState() {
    super.initState();
    final scenario = widget.scenario;

    _parsedDistance = scenario?.number('distance') ?? 60;
    _parsedEfficiency = scenario?.number('efficiency') ?? 12;
    _parsedPrice = scenario?.number('price') ?? 3200;
    _customDays = scenario?.number('customDays', 20) ?? 20;

    final stored = scenario?.text('frequency');
    _frequency = Frequency.values.firstWhere(
      (frequency) => frequency.name == stored,
      orElse: () => Frequency.everyDay,
    );

    _distance = TextEditingController(text: Money.number(_parsedDistance));
    _efficiency = TextEditingController(text: Money.number(_parsedEfficiency));
    _price = TextEditingController(text: Money.number(_parsedPrice));
  }

  @override
  void dispose() {
    _distance.dispose();
    _efficiency.dispose();
    _price.dispose();
    super.dispose();
  }

  FuelEstimate get _estimate => estimateFuel(
    distancePerDay: _parsedDistance,
    efficiency: _parsedEfficiency,
    pricePerLitre: _parsedPrice,
    frequency: _frequency,
    customDaysPerMonth: _customDays,
  );

  Map<String, dynamic> _collect() {
    final estimate = _estimate;

    return {
      'distance': _parsedDistance,
      'efficiency': _parsedEfficiency,
      'price': _parsedPrice,
      'frequency': _frequency.name,
      'customDays': _customDays,
      '_summaryYearly': estimate.cost.yearly,
      '_summaryLabel':
          '${Money.number(_parsedDistance)} km '
          '${frequencyPhrase(_frequency, _customDays)} · '
          '${Money.number(_parsedEfficiency)} km/L',
    };
  }

  @override
  Widget build(BuildContext context) {
    final estimate = _estimate;
    final accent = Palette.color(3, Theme.of(context).brightness);

    return PlannerPage(
      title: 'Fuel',
      subtitle: 'What driving costs to run',
      kind: ScenarioKind.fuel,
      collect: _collect,
      loadedScenarioId: widget.scenario?.id,
      children: [
        SectionCard(
          child: Column(
            children: [
              NumberField(
                controller: _distance,
                label: 'Distance driven',
                suffix: 'km / day',
                onChanged: (value) => setState(() => _parsedDistance = value),
              ),
              plannerFieldGap,
              NumberField(
                controller: _efficiency,
                label: 'Fuel efficiency',
                suffix: 'km / L',
                onChanged: (value) => setState(() => _parsedEfficiency = value),
              ),
              plannerFieldGap,
              NumberField(
                controller: _price,
                label: 'Fuel price',
                prefix: Money.symbol,
                suffix: '/ L',
                onChanged: (value) => setState(() => _parsedPrice = value),
              ),
              plannerFieldGap,
              // Driving is rarely a seven-day habit — a commute stops at the
              // weekend, and charging all 365 days would overstate it badly.
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
          title: 'Fuel used',
          child: Column(
            children: [
              ValueRow(
                label: 'Average per day',
                value: Money.litres(estimate.litresPerDay),
                accent: accent,
              ),
              ValueRow(
                label: 'Per month',
                value: Money.litres(estimate.litresPerMonth),
                accent: accent,
              ),
              ValueRow(
                label: 'Per year',
                value: Money.litres(estimate.litresPerYear),
                accent: accent,
                bold: true,
              ),
            ],
          ),
        ),
        plannerGap,
        StatGrid(
          tiles: [
            StatTile(
              label: 'Monthly',
              value: estimate.cost.monthly,
              accent: accent,
              emphasis: true,
            ),
            StatTile(
              label: 'Yearly',
              value: estimate.cost.yearly,
              accent: accent,
              emphasis: true,
            ),
          ],
        ),
        plannerGap,
        InsightCard(message: _insight(estimate)),
      ],
    );
  }

  String _insight(FuelEstimate estimate) {
    if (estimate.cost.yearly <= 0) {
      return 'Fill in distance, efficiency and fuel price to see what your '
          'driving costs.';
    }

    return 'Driving ${Money.number(_parsedDistance)} km '
        '${frequencyPhrase(_frequency, _customDays)} burns about '
        '${Money.litres(estimate.litresPerMonth)} a month — around '
        '${Money.format(estimate.cost.monthly)} monthly, or '
        '${Money.spoken(estimate.cost.yearly)} a year.';
  }
}
