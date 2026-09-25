import 'package:flutter/material.dart';

import '../../models/brain_item.dart';
import '../../widgets/week_calendar.dart';
import 'brain_command_bar.dart' show brainKindColor;

/// The Second Brain's week strip — the shared [WeekCalendar] in the brain's
/// violet.
class BrainCalendar extends StatelessWidget {
  const BrainCalendar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final DateTime? selected;
  final ValueChanged<DateTime?> onSelect;

  @override
  Widget build(BuildContext context) {
    return WeekCalendar(
      selected: selected,
      onSelect: onSelect,
      accent: brainKindColor(BrainKind.note),
    );
  }
}
