import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/activity.dart';
import '../../services/format.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/inputs.dart';

/// Bottom sheet for editing a non-expense activity — income, transfer, loan or
/// repayment.
///
/// Deliberately minimal: amount, description, date and profile cover the vast
/// majority of edits. The activity's type and second party are fixed at
/// capture time (changing "income" into a "transfer", or re-pointing a loan at
/// a different person, is a different record), so they're shown but not edited
/// here. This closes the jarring gap where expenses were tap-to-edit but
/// activities could only be swipe-deleted and re-captured.
class ActivityEditSheet extends StatefulWidget {
  const ActivityEditSheet({super.key, required this.activity});

  final Activity activity;

  static Future<void> show(BuildContext context, Activity activity) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ActivityEditSheet(activity: activity),
    );
  }

  @override
  State<ActivityEditSheet> createState() => _ActivityEditSheetState();
}

class _ActivityEditSheetState extends State<ActivityEditSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _description;
  late String _profileId;
  late DateTime _date;
  double _parsedAmount = 0;

  @override
  void initState() {
    super.initState();
    final activity = widget.activity;
    _amount = TextEditingController(text: Money.number(activity.amount));
    _description = TextEditingController(text: activity.description);
    _profileId =
        activity.profileId ?? context.read<AppState>().defaultProfileId;
    _date = activity.date;
    _parsedAmount = activity.amount;
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _canSave => _parsedAmount > 0;

  Future<void> _save() async {
    final state = context.read<AppState>();
    await state.updateActivity(
      widget.activity.copyWith(
        amount: _parsedAmount,
        description: _description.text.trim(),
        profileId: _profileId,
        date: _date,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activity = widget.activity;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit ${activity.type.label.toLowerCase()}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            NumberField(
              controller: _amount,
              label: 'Amount',
              prefix: Money.symbol,
              onChanged: (value) => setState(() => _parsedAmount = value),
            ),
            const SizedBox(height: 16),
            LabelledField(
              controller: _description,
              label: 'Description',
              hint: activity.type.label,
            ),
            const SizedBox(height: 16),
            ProfilePicker(
              selectedId: _profileId,
              onChanged: (id) => setState(() => _profileId = id),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.hairline),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 18,
                      color: context.muted,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      Dates.relative(_date),
                      style: theme.textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text(
                      Dates.full(_date),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: context.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
