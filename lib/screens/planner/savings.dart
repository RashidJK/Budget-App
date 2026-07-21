import 'package:flutter/material.dart';

import '../../models/scenario.dart';
import '../../planner/engine.dart';
import '../../services/format.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/inputs.dart';
import '../../widgets/stat.dart';
import 'planner_scaffold.dart';

/// One side of the comparison.
class _Side {
  _Side({
    required this.label,
    required this.amount,
    required this.frequency,
    required this.customDays,
  }) : labelController = TextEditingController(text: label),
       amountController = TextEditingController(text: Money.number(amount));

  String label;
  double amount;
  Frequency frequency;
  double customDays;

  final TextEditingController labelController;
  final TextEditingController amountController;

  CostBreakdown get breakdown => breakdownFor(
    amount: amount,
    frequency: frequency,
    customDaysPerMonth: customDays,
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'amount': amount,
    'frequency': frequency.name,
    'customDays': customDays,
  };

  static _Side fromJson(
    Map<String, dynamic> json, {
    required String fallbackLabel,
    required double fallbackAmount,
  }) {
    final storedFrequency = json['frequency'] as String?;
    return _Side(
      label: json['label'] as String? ?? fallbackLabel,
      amount: (json['amount'] as num?)?.toDouble() ?? fallbackAmount,
      frequency: Frequency.values.firstWhere(
        (frequency) => frequency.name == storedFrequency,
        orElse: () => Frequency.everyDay,
      ),
      customDays: (json['customDays'] as num?)?.toDouble() ?? 15,
    );
  }

  void dispose() {
    labelController.dispose();
    amountController.dispose();
  }
}

/// "If I reduce this expense, how much will I save?"
class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key, this.scenario});

  final Scenario? scenario;

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  late _Side _current;
  late _Side _alternative;

  @override
  void initState() {
    super.initState();
    final scenario = widget.scenario;

    final currentJson = scenario?.data['current'];
    final alternativeJson = scenario?.data['alternative'];

    _current = currentJson is Map
        ? _Side.fromJson(
            Map<String, dynamic>.from(currentJson),
            fallbackLabel: 'Eat out every day',
            fallbackAmount: 5000,
          )
        : _Side(
            label: 'Eat out every day',
            amount: 5000,
            frequency: Frequency.everyDay,
            customDays: 15,
          );

    _alternative = alternativeJson is Map
        ? _Side.fromJson(
            Map<String, dynamic>.from(alternativeJson),
            fallbackLabel: 'Meal prep',
            fallbackAmount: 2500,
          )
        : _Side(
            label: 'Meal prep',
            amount: 2500,
            frequency: Frequency.everyDay,
            customDays: 15,
          );
  }

  @override
  void dispose() {
    _current.dispose();
    _alternative.dispose();
    super.dispose();
  }

  SavingsComparison get _comparison => SavingsComparison(
    current: _current.breakdown,
    alternative: _alternative.breakdown,
  );

  Map<String, dynamic> _collect() {
    final comparison = _comparison;

    return {
      'current': _current.toJson(),
      'alternative': _alternative.toJson(),
      '_summaryYearly': comparison.yearlySaving,
      '_summaryLabel':
          '${_current.label} → ${_alternative.label} · '
          '${Money.percent(comparison.percentSaved)} saved',
    };
  }

  @override
  Widget build(BuildContext context) {
    final comparison = _comparison;
    final worse = comparison.isWorse;

    return PlannerPage(
      title: 'Savings',
      subtitle: 'Compare a habit against the alternative',
      kind: ScenarioKind.savings,
      collect: _collect,
      loadedScenarioId: widget.scenario?.id,
      children: [
        _SideEditor(
          side: _current,
          heading: 'Current',
          accent: context.warn,
          onChanged: () => setState(() {}),
        ),
        plannerGap,
        _SideEditor(
          side: _alternative,
          heading: 'Alternative',
          accent: context.good,
          onChanged: () => setState(() {}),
        ),
        plannerGap,
        SectionCard(
          title: 'Monthly cost',
          child: ComparisonBars(
            currentLabel: _label(_current, 'Current'),
            currentValue: comparison.current.monthly,
            alternativeLabel: _label(_alternative, 'Alternative'),
            alternativeValue: comparison.alternative.monthly,
          ),
        ),
        plannerGap,
        StatGrid(
          tiles: [
            StatTile(
              label: worse ? 'Monthly extra' : 'Monthly saving',
              value: comparison.monthlySaving.abs(),
              accent: worse ? context.warn : context.good,
              emphasis: true,
            ),
            StatTile(
              label: worse ? 'Yearly extra' : 'Yearly saving',
              value: comparison.yearlySaving.abs(),
              accent: worse ? context.warn : context.good,
              emphasis: true,
            ),
          ],
        ),
        plannerGap,
        SectionCard(
          title: worse ? 'What it would cost you' : 'What you would keep',
          child: Column(
            children: [
              ValueRow(
                label: 'Percentage ${worse ? 'more' : 'saved'}',
                value: Money.percent(comparison.percentSaved.abs()),
                bold: true,
              ),
              ValueRow(
                label: 'Over 3 years',
                value: Money.format(comparison.savingOver(3).abs()),
              ),
              ValueRow(
                label: 'Over 5 years',
                value: Money.format(comparison.savingOver(5).abs()),
              ),
              ValueRow(
                label: 'Over 10 years',
                value: Money.format(comparison.savingOver(10).abs()),
              ),
            ],
          ),
        ),
        plannerGap,
        InsightCard(
          message: _insight(comparison),
          tone: worse ? InsightTone.warning : InsightTone.good,
          icon: worse ? Icons.warning_amber_rounded : Icons.savings_outlined,
        ),
      ],
    );
  }

  String _label(_Side side, String fallback) =>
      side.label.trim().isEmpty ? fallback : side.label.trim();

  String _insight(SavingsComparison comparison) {
    if (comparison.current.yearly <= 0 && comparison.alternative.yearly <= 0) {
      return 'Fill in both sides to see what switching would save you.';
    }

    if (comparison.isWorse) {
      return '"${_label(_alternative, 'The alternative')}" actually costs '
          '${Money.format(comparison.yearlySaving.abs())} more per year than '
          'what you do now. Worth a second look.';
    }

    if (comparison.yearlySaving == 0) {
      return 'Both options cost the same. Change one of the amounts to see '
          'the difference.';
    }

    return 'Switching to "${_label(_alternative, 'the alternative')}" saves '
        '${Money.format(comparison.monthlySaving)} a month — '
        '${Money.spoken(comparison.yearlySaving)} a year, or '
        '${Money.percent(comparison.percentSaved)} of what you spend now. '
        'Over five years that is '
        '${Money.spoken(comparison.savingOver(5))}.';
  }
}

class _SideEditor extends StatelessWidget {
  const _SideEditor({
    required this.side,
    required this.heading,
    required this.accent,
    required this.onChanged,
  });

  final _Side side;
  final String heading;
  final Color accent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                heading.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: context.muted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LabelledField(
            controller: side.labelController,
            label: 'What is it?',
            hint: heading == 'Current' ? 'Eat out every day' : 'Meal prep',
            onChanged: (value) {
              side.label = value;
              onChanged();
            },
          ),
          plannerFieldGap,
          NumberField(
            controller: side.amountController,
            label: 'Amount per time',
            prefix: Money.symbol,
            onChanged: (value) {
              side.amount = value;
              onChanged();
            },
          ),
          plannerFieldGap,
          FrequencyPicker(
            value: side.frequency,
            onChanged: (value) {
              side.frequency = value;
              onChanged();
            },
            customDays: side.customDays,
            onCustomDaysChanged: (value) {
              side.customDays = value;
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}
