import 'package:flutter/material.dart';

import '../../models/palette.dart';
import '../../models/scenario.dart';
import '../../planner/engine.dart';
import '../../services/format.dart';
import '../../theme.dart';
import '../../widgets/inputs.dart';
import '../../widgets/stat.dart';
import 'planner_scaffold.dart';

/// One editable subscription row.
///
/// Holds its own controllers so typing in one row never rebuilds the others.
class _SubscriptionEntry {
  _SubscriptionEntry({
    required this.name,
    required this.amount,
    required this.cycle,
    required this.startDate,
  }) : nameController = TextEditingController(text: name),
       amountController = TextEditingController(text: Money.number(amount));

  factory _SubscriptionEntry.fromJson(Map<String, dynamic> json) {
    final storedCycle = json['cycle'] as String?;
    return _SubscriptionEntry(
      name: json['name'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      cycle: BillingCycle.values.firstWhere(
        (cycle) => cycle.name == storedCycle,
        orElse: () => BillingCycle.monthly,
      ),
      startDate:
          DateTime.tryParse(json['startDate'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  String name;
  double amount;
  BillingCycle cycle;
  DateTime startDate;

  final TextEditingController nameController;
  final TextEditingController amountController;

  CostBreakdown get breakdown =>
      subscriptionBreakdown(amount: amount, cycle: cycle);

  DateTime get nextPayment => nextPaymentDate(start: startDate, cycle: cycle);

  Map<String, dynamic> toJson() => {
    'name': name,
    'amount': amount,
    'cycle': cycle.name,
    'startDate': startDate.toIso8601String(),
  };

  void dispose() {
    nameController.dispose();
    amountController.dispose();
  }
}

/// "If I subscribe to these services, what will they cost me yearly?"
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key, this.scenario});

  final Scenario? scenario;

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late List<_SubscriptionEntry> _entries;

  @override
  void initState() {
    super.initState();
    final saved = widget.scenario?.rows('items') ?? const [];

    _entries = saved.isEmpty
        ? _defaults()
        : saved.map(_SubscriptionEntry.fromJson).toList();
  }

  /// Seeds the screen with the examples from the spec, so it opens with
  /// something to react to rather than an empty form.
  List<_SubscriptionEntry> _defaults() {
    final now = DateTime.now();
    return [
      _SubscriptionEntry(
        name: 'Netflix',
        amount: 29000,
        cycle: BillingCycle.monthly,
        startDate: DateTime(now.year, now.month, 5),
      ),
      _SubscriptionEntry(
        name: 'Spotify',
        amount: 12000,
        cycle: BillingCycle.monthly,
        startDate: DateTime(now.year, now.month, 12),
      ),
      _SubscriptionEntry(
        name: 'ChatGPT',
        amount: 52000,
        cycle: BillingCycle.monthly,
        startDate: DateTime(now.year, now.month, 20),
      ),
    ];
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  CostBreakdown get _total => _entries.fold(
    const CostBreakdown.zero(),
    (sum, entry) => sum + entry.breakdown,
  );

  /// Entries with a real charge, ordered by when they next bill.
  List<_SubscriptionEntry> get _upcoming {
    final billable = _entries.where((entry) => entry.amount > 0).toList()
      ..sort((a, b) => a.nextPayment.compareTo(b.nextPayment));
    return billable;
  }

  void _add() {
    setState(() {
      _entries = [
        ..._entries,
        _SubscriptionEntry(
          name: '',
          amount: 0,
          cycle: BillingCycle.monthly,
          startDate: DateTime.now(),
        ),
      ];
    });
  }

  void _remove(int index) {
    setState(() {
      final removed = _entries[index];
      _entries = [..._entries]..removeAt(index);
      // Disposal is deferred: the row is still mounted for this frame, and
      // disposing its controllers now would throw during the rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
    });
  }

  Map<String, dynamic> _collect() {
    final total = _total;
    final count = _entries.where((entry) => entry.amount > 0).length;

    return {
      'items': _entries.map((entry) => entry.toJson()).toList(),
      '_summaryYearly': total.yearly,
      '_summaryLabel':
          '$count ${count == 1 ? 'subscription' : 'subscriptions'} · '
          '${Money.format(total.monthly)} a month',
    };
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final accent = Palette.color(6, Theme.of(context).brightness);
    final upcoming = _upcoming;

    return PlannerPage(
      title: 'Subscriptions',
      subtitle: 'The quiet monthly drain',
      kind: ScenarioKind.subscriptions,
      collect: _collect,
      loadedScenarioId: widget.scenario?.id,
      children: [
        StatGrid(
          tiles: [
            StatTile(
              label: 'Monthly total',
              value: total.monthly,
              accent: accent,
              emphasis: true,
            ),
            StatTile(
              label: 'Yearly total',
              value: total.yearly,
              accent: accent,
              emphasis: true,
            ),
          ],
        ),
        plannerGap,
        for (var index = 0; index < _entries.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SubscriptionCard(
              key: ValueKey(_entries[index]),
              entry: _entries[index],
              accent: accent,
              onChanged: () => setState(() {}),
              onRemove: () => _remove(index),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Add subscription'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        if (upcoming.isNotEmpty) ...[
          plannerGap,
          SectionCard(
            title: 'Next payments',
            child: Column(
              children: [
                for (final entry in upcoming.take(5))
                  ValueRow(
                    label: entry.name.isEmpty ? 'Untitled' : entry.name,
                    value: Dates.relative(entry.nextPayment),
                    accent: accent,
                  ),
              ],
            ),
          ),
        ],
        plannerGap,
        InsightCard(message: _insight(total)),
      ],
    );
  }

  String _insight(CostBreakdown total) {
    if (total.yearly <= 0) {
      return 'Add your subscriptions to see what they cost together.';
    }

    return 'These subscriptions come to ${Money.format(total.monthly)} a '
        'month, which is ${Money.spoken(total.yearly)} a year. Cancelling '
        'just the priciest one would free up '
        '${Money.format(_priciestYearly())} annually.';
  }

  double _priciestYearly() {
    return _entries.fold<double>(
      0,
      (highest, entry) =>
          entry.breakdown.yearly > highest ? entry.breakdown.yearly : highest,
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    super.key,
    required this.entry,
    required this.accent,
    required this.onChanged,
    required this.onRemove,
  });

  final _SubscriptionEntry entry;
  final Color accent;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: entry.startDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      helpText: 'First or last payment date',
    );
    if (picked != null) {
      entry.startDate = picked;
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: entry.nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Service name',
                    isDense: true,
                  ),
                  style: theme.textTheme.titleMedium,
                  onChanged: (value) {
                    entry.name = value;
                    onChanged();
                  },
                ),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: 'Remove',
                icon: Icon(Icons.close_rounded, size: 20, color: context.muted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          NumberField(
            controller: entry.amountController,
            label: 'Amount per charge',
            prefix: Money.symbol,
            onChanged: (value) {
              entry.amount = value;
              onChanged();
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<BillingCycle>(
                  initialValue: entry.cycle,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (final cycle in BillingCycle.values)
                      DropdownMenuItem(value: cycle, child: Text(cycle.label)),
                  ],
                  onChanged: (cycle) {
                    if (cycle == null) return;
                    entry.cycle = cycle;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(context),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.hairline),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_rounded,
                          size: 17,
                          color: context.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            Dates.short(entry.startDate),
                            style: theme.textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (entry.amount > 0 && entry.cycle != BillingCycle.monthly) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '≈ ${Money.format(entry.breakdown.monthly)} a month',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.muted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
