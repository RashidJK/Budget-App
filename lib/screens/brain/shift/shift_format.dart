// Small date/time formatting helpers so the cards don't need the intl package.

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Today" / "Tomorrow" / "Yesterday", otherwise "Fri, Oct 9" (with the year
/// when it isn't the current one).
String dayLabel(DateTime d, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final date = DateTime(d.year, d.month, d.day);
  final diff = date.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  final base = '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
  return d.year == ref.year ? base : '$base ${d.year}';
}

/// "8:00 PM".
String timeLabel(DateTime d) {
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  var h = d.hour % 12;
  if (h == 0) h = 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
}

/// "Fri, Oct 9" or "Fri, Oct 9, 8:00 PM" when a time is present.
String formatWhenLine(DateTime d, bool hasTime, {DateTime? now}) {
  final parts = [dayLabel(d, now: now), if (hasTime) timeLabel(d)];
  return parts.join(', ');
}
