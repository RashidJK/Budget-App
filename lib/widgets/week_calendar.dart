import 'package:flutter/material.dart';

import '../theme.dart';

/// A horizontal week strip (Sun…Sat) with the current day highlighted. Tapping
/// a day selects it; tapping the selected day again clears the selection.
///
/// Shared by the Second Brain and the Budget dashboard — [accent] tints it to
/// each app's identity colour.
class WeekCalendar extends StatelessWidget {
  const WeekCalendar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.accent,
  });

  /// The chosen day, or null when nothing is filtered.
  final DateTime? selected;
  final ValueChanged<DateTime?> onSelect;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Sunday that starts this week (weekday: Mon=1…Sun=7).
    final sunday = today.subtract(Duration(days: now.weekday % 7));
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return SizedBox(
      height: 62,
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _Day(
                label: labels[i],
                date: sunday.add(Duration(days: i)),
                isToday: sunday.add(Duration(days: i)) == today,
                isSelected: selected != null &&
                    DateTime(selected!.year, selected!.month, selected!.day) ==
                        sunday.add(Duration(days: i)),
                accent: accent,
                onTap: onSelect,
              ),
            ),
        ],
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.label,
    required this.date,
    required this.isToday,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final bool isToday;
  final bool isSelected;
  final Color accent;
  final ValueChanged<DateTime?> onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(isSelected ? null : date),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isSelected ? accent : context.muted,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? accent : Colors.transparent,
              shape: BoxShape.circle,
              border: isToday && !isSelected
                  ? Border.all(color: accent.withValues(alpha: 0.55), width: 1.5)
                  : null,
            ),
            child: Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? Colors.white
                    : (isToday ? accent : context.scheme.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
