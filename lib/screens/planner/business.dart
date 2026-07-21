import 'package:flutter/material.dart';

import '../../models/palette.dart';
import '../../models/scenario.dart';
import '../../planner/engine.dart';
import '../../services/format.dart';
import '../../theme.dart';
import '../../widgets/inputs.dart';
import '../../widgets/stat.dart';
import 'planner_scaffold.dart';

/// One operating-cost line.
class _CostLine {
  _CostLine({required this.label, required this.amount})
    : labelController = TextEditingController(text: label),
      amountController = TextEditingController(
        text: amount > 0 ? Money.number(amount) : '',
      );

  factory _CostLine.fromJson(Map<String, dynamic> json) => _CostLine(
    label: json['label'] as String? ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
  );

  String label;
  double amount;

  final TextEditingController labelController;
  final TextEditingController amountController;

  Map<String, dynamic> toJson() => {'label': label, 'amount': amount};

  void dispose() {
    labelController.dispose();
    amountController.dispose();
  }
}

/// "What will it cost me to run this business every month?"
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key, this.scenario});

  final Scenario? scenario;

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  /// The categories the spec lists, offered as one-tap starting points.
  static const _presets = [
    'Office Rent',
    'Internet',
    'Employees',
    'Fuel',
    'Marketing',
    'Software',
    'Hosting',
    'AI APIs',
    'Electricity',
  ];

  late List<_CostLine> _lines;
  late double _margin;

  @override
  void initState() {
    super.initState();
    final saved = widget.scenario?.rows('lines') ?? const [];

    _lines = saved.isEmpty
        ? [
            _CostLine(label: 'Office Rent', amount: 450000),
            _CostLine(label: 'Internet', amount: 120000),
            _CostLine(label: 'Employees', amount: 900000),
          ]
        : saved.map(_CostLine.fromJson).toList();

    _margin = widget.scenario?.number('margin', 0.30) ?? 0.30;
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  BusinessEstimate get _estimate => estimateBusiness(
    monthlyCosts: _lines.map((line) => line.amount),
    targetMargin: _margin,
  );

  void _add(String label) {
    setState(() {
      _lines = [..._lines, _CostLine(label: label, amount: 0)];
    });
  }

  void _remove(int index) {
    setState(() {
      final removed = _lines[index];
      _lines = [..._lines]..removeAt(index);
      WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
    });
  }

  /// Presets not already on the list, so the chip row shrinks as it is used.
  List<String> get _availablePresets {
    final used = _lines.map((line) => line.label.trim().toLowerCase()).toSet();
    return _presets
        .where((preset) => !used.contains(preset.toLowerCase()))
        .toList();
  }

  Map<String, dynamic> _collect() {
    final estimate = _estimate;

    return {
      'lines': _lines.map((line) => line.toJson()).toList(),
      'margin': _margin,
      '_summaryYearly': estimate.yearlyCost,
      '_summaryLabel':
          '${Money.format(estimate.monthlyCost)} a month · '
          '${Money.percent(_margin)} target margin',
    };
  }

  @override
  Widget build(BuildContext context) {
    final estimate = _estimate;
    final accent = Palette.color(4, Theme.of(context).brightness);
    final presets = _availablePresets;

    return PlannerPage(
      title: 'Business Costs',
      subtitle: 'What it takes to keep the lights on',
      kind: ScenarioKind.business,
      collect: _collect,
      loadedScenarioId: widget.scenario?.id,
      children: [
        StatGrid(
          tiles: [
            StatTile(
              label: 'Monthly cost',
              value: estimate.monthlyCost,
              accent: accent,
              emphasis: true,
            ),
            StatTile(
              label: 'Yearly cost',
              value: estimate.yearlyCost,
              accent: accent,
              emphasis: true,
            ),
          ],
        ),
        plannerGap,
        SectionCard(
          title: 'Operating costs (${Money.symbol} per month)',
          child: Column(
            children: [
              for (var index = 0; index < _lines.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CostRow(
                    key: ValueKey(_lines[index]),
                    line: _lines[index],
                    onChanged: () => setState(() {}),
                    onRemove: () => _remove(index),
                  ),
                ),
              const SizedBox(height: 6),
              if (presets.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in presets)
                        ActionChip(
                          label: Text(preset),
                          avatar: const Icon(Icons.add_rounded, size: 16),
                          onPressed: () => _add(preset),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: context.hairline),
                          ),
                        ),
                      ActionChip(
                        label: const Text('Something else'),
                        avatar: const Icon(Icons.add_rounded, size: 16),
                        onPressed: () => _add(''),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: context.hairline),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        plannerGap,
        SectionCard(
          title: 'Revenue target',
          child: Column(
            children: [
              _MarginSlider(
                margin: _margin,
                onChanged: (value) => setState(() => _margin = value),
              ),
              const SizedBox(height: 8),
              ValueRow(
                label: 'Minimum monthly revenue',
                value: Money.format(estimate.recommendedMonthlyRevenue),
                accent: accent,
                bold: true,
              ),
              ValueRow(
                label: 'Minimum yearly revenue',
                value: Money.format(estimate.recommendedYearlyRevenue),
                accent: accent,
              ),
              ValueRow(
                label: 'Profit at that revenue',
                value: Money.format(estimate.monthlyProfit),
                accent: accent,
              ),
              ValueRow(
                label: 'Revenue needed per day',
                value: Money.format(estimate.dailyRevenueTarget),
                accent: accent,
              ),
            ],
          ),
        ),
        plannerGap,
        InsightCard(message: _insight(estimate)),
      ],
    );
  }

  String _insight(BusinessEstimate estimate) {
    if (estimate.monthlyCost <= 0) {
      return 'Add your operating costs to see what revenue the business needs '
          'to clear them.';
    }

    return 'Running this costs ${Money.format(estimate.monthlyCost)} a month, '
        'or ${Money.spoken(estimate.yearlyCost)} a year. To keep a '
        '${Money.percent(estimate.targetMargin)} margin you need to bring in '
        'at least ${Money.format(estimate.recommendedMonthlyRevenue)} monthly '
        '— about ${Money.format(estimate.dailyRevenueTarget)} every day.';
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow({
    super.key,
    required this.line,
    required this.onChanged,
    required this.onRemove,
  });

  final _CostLine line;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 5,
          child: TextField(
            controller: line.labelController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Cost name',
              isDense: true,
            ),
            onChanged: (value) {
              line.label = value;
              onChanged();
            },
          ),
        ),
        const SizedBox(width: 10),
        // Wide enough for a seven-figure amount. The currency symbol is left
        // off deliberately — repeated down every row it stole the space the
        // digits needed and clipped them.
        Expanded(
          flex: 5,
          child: TextField(
            controller: line.amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            decoration: const InputDecoration(hintText: '0', isDense: true),
            onChanged: (value) {
              line.amount = double.tryParse(value) ?? 0;
              onChanged();
            },
          ),
        ),
        IconButton(
          onPressed: onRemove,
          tooltip: 'Remove',
          icon: Icon(Icons.close_rounded, size: 18, color: context.muted),
        ),
      ],
    );
  }
}

class _MarginSlider extends StatelessWidget {
  const _MarginSlider({required this.margin, required this.onChanged});

  final double margin;
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
              'Target profit margin',
              style: theme.textTheme.labelMedium?.copyWith(
                color: context.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              Money.percent(margin),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: margin.clamp(0.0, 0.9),
          max: 0.9,
          divisions: 18,
          label: Money.percent(margin),
          onChanged: onChanged,
        ),
        Text(
          'Revenue is worked out as cost ÷ (1 − margin), so a 30% margin means '
          'costs are 70% of what you take in.',
          style: theme.textTheme.bodySmall?.copyWith(color: context.muted),
        ),
      ],
    );
  }
}
