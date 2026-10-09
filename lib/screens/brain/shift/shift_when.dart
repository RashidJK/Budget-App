// A small, dependency-free date parser standing in for chrono-node (which
// can't be added offline). It covers the phrasings the shift cards actually
// use: relative days (today/tomorrow/next week/in 3 days), weekdays, month +
// day with optional ranges, weekends, and clock times (8pm, 8:30, noon). It
// always reads forward — a date already past rolls to the next occurrence.

/// A span of the input to blank out once a date has been read from it.
class WhenSpan {
  const WhenSpan(this.start, this.end);
  final int start;
  final int end;
}

/// The result of reading a date/time out of some text.
class WhenHit {
  const WhenHit(this.start, this.end, this.hasTime, this.spans);

  /// The resolved instant (midnight when no clock time was given).
  final DateTime start;

  /// The end of a range ("12–15 oct"), if one was named.
  final DateTime? end;

  /// Whether a clock time was present (so callers can show "8 PM" vs just a day).
  final bool hasTime;

  /// Every stretch of the input that contributed to the date, for [stripWhen].
  final List<WhenSpan> spans;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

const _weekdays = {
  'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
};

const _monthAlt =
    'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|'
    'jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?';

final _weekdayRe = RegExp(
  r'\b(next|this)?\s*(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)(?:day|nesday|sday|urday|rsday)?s?\b',
);
final _relRe = RegExp(r'\b(today|tonight|tomorrow|tmrw|tmr|yesterday)\b');
final _weekRe = RegExp(r'\b(next|this)\s+week\b');
final _weekendRe = RegExp(r'\b(next|this)\s+weekend\b');
final _inRe = RegExp(
  r'\bin\s+(\d+|a|an|a few|several)\s+(day|days|week|weeks|month|months)\b',
);
final _fromNowRe = RegExp(r'\b(\d+)\s+(day|days|week|weeks)\s+from now\b');
final _monthDayRe = RegExp(
  '\\b($_monthAlt)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:\\s*[-–—]\\s*(\\d{1,2}))?\\b',
);
final _dayMonthRe = RegExp(
  '\\b(\\d{1,2})(?:st|nd|rd|th)?(?:\\s*[-–—]\\s*(\\d{1,2})(?:st|nd|rd|th)?)?\\s+($_monthAlt)\\b',
);
final _timeRe = RegExp(
  r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b|\b(\d{1,2}):(\d{2})\b|\b(noon|midnight)\b',
);

int _wordNum(String w) => switch (w) {
  'a' || 'an' => 1,
  'a few' => 3,
  'several' => 5,
  _ => int.tryParse(w) ?? 1,
};

int _monthIndex(String name) => _months[name.substring(0, 3)]!;

DateTime _addMonths(DateTime d, int months) {
  final total = d.month - 1 + months;
  final year = d.year + total ~/ 12;
  final month = total % 12 + 1;
  final day = d.day;
  // Clamp to the last valid day of the target month.
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > lastDay ? lastDay : day);
}

class _Candidate {
  _Candidate(this.index, this.length, this.start, this.end);
  final int index;
  final int length;
  final DateTime start;
  final DateTime? end;
}

/// Read the first date/time out of [text]. Returns null when there's nothing
/// date-like. [ref] pins "now" (tests, and the caller's clock).
WhenHit? findWhen(String text, {DateTime? ref}) {
  final now = ref ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final t = text.toLowerCase();

  final candidates = <_Candidate>[];

  void relative() {
    final m = _relRe.firstMatch(t);
    if (m == null) return;
    final word = m.group(1)!;
    final start = switch (word) {
      'yesterday' => today.subtract(const Duration(days: 1)),
      'tomorrow' || 'tmrw' || 'tmr' => today.add(const Duration(days: 1)),
      _ => today, // today / tonight
    };
    candidates.add(_Candidate(m.start, m.end - m.start, start, null));
  }

  void week() {
    final m = _weekRe.firstMatch(t);
    if (m == null) return;
    final start = m.group(1) == 'next' ? today.add(const Duration(days: 7)) : today;
    candidates.add(_Candidate(m.start, m.end - m.start, start, null));
  }

  void weekend() {
    final m = _weekendRe.firstMatch(t);
    if (m == null) return;
    // Coming Saturday; "next" pushes a week on when we're already at the weekend.
    var sat = today;
    while (sat.weekday != DateTime.saturday) {
      sat = sat.add(const Duration(days: 1));
    }
    if (m.group(1) == 'next' &&
        (today.weekday == DateTime.friday ||
            today.weekday == DateTime.saturday ||
            today.weekday == DateTime.sunday)) {
      sat = sat.add(const Duration(days: 7));
    }
    candidates.add(
      _Candidate(m.start, m.end - m.start, sat, sat.add(const Duration(days: 1))),
    );
  }

  void inN() {
    final m = _inRe.firstMatch(t);
    if (m == null) return;
    final n = _wordNum(m.group(1)!);
    final unit = m.group(2)!;
    final start = unit.startsWith('month')
        ? _addMonths(today, n)
        : today.add(Duration(days: unit.startsWith('week') ? n * 7 : n));
    candidates.add(_Candidate(m.start, m.end - m.start, start, null));
  }

  void fromNow() {
    final m = _fromNowRe.firstMatch(t);
    if (m == null) return;
    final n = int.parse(m.group(1)!);
    final days = m.group(2)!.startsWith('week') ? n * 7 : n;
    candidates.add(
      _Candidate(m.start, m.end - m.start, today.add(Duration(days: days)), null),
    );
  }

  void weekday() {
    final m = _weekdayRe.firstMatch(t);
    if (m == null) return;
    final target = _weekdays[m.group(2)!.substring(0, 3)]!;
    var d = today.add(const Duration(days: 1));
    while (d.weekday != target) {
      d = d.add(const Duration(days: 1));
    }
    if (m.group(1) == 'next') d = d.add(const Duration(days: 7));
    candidates.add(_Candidate(m.start, m.end - m.start, d, null));
  }

  DateTime forwardYear(int month, int day) {
    var date = DateTime(now.year, month, day);
    if (date.isBefore(today)) date = DateTime(now.year + 1, month, day);
    return date;
  }

  void monthDay() {
    final m = _monthDayRe.firstMatch(t);
    if (m == null) return;
    final month = _monthIndex(m.group(1)!);
    final day = int.parse(m.group(2)!);
    final start = forwardYear(month, day);
    DateTime? end;
    if (m.group(3) != null) end = forwardYear(month, int.parse(m.group(3)!));
    candidates.add(_Candidate(m.start, m.end - m.start, start, end));
  }

  void dayMonth() {
    final m = _dayMonthRe.firstMatch(t);
    if (m == null) return;
    final day = int.parse(m.group(1)!);
    final month = _monthIndex(m.group(3)!);
    final start = forwardYear(month, day);
    DateTime? end;
    if (m.group(2) != null) end = forwardYear(month, int.parse(m.group(2)!));
    candidates.add(_Candidate(m.start, m.end - m.start, start, end));
  }

  relative();
  week();
  weekend();
  inN();
  fromNow();
  weekday();
  monthDay();
  dayMonth();

  _Candidate? day;
  for (final c in candidates) {
    if (day == null || c.index < day.index) day = c;
  }

  // Clock time (may stand alone, or attach to the day anchor).
  final timeMatch = _timeRe.firstMatch(t);
  int? hour;
  int? minute;
  if (timeMatch != null) {
    if (timeMatch.group(6) != null) {
      hour = timeMatch.group(6) == 'noon' ? 12 : 0;
      minute = 0;
    } else if (timeMatch.group(3) != null) {
      hour = int.parse(timeMatch.group(1)!) % 12;
      if (timeMatch.group(3) == 'pm') hour += 12;
      minute = int.parse(timeMatch.group(2) ?? '0');
    } else {
      hour = int.parse(timeMatch.group(4)!);
      minute = int.parse(timeMatch.group(5)!);
    }
    if (hour > 23 || minute > 59) {
      hour = null;
      minute = null;
    }
  }

  if (day == null && hour == null) return null;

  final spans = <WhenSpan>[];
  DateTime start;
  DateTime? end;
  if (day != null) {
    start = day.start;
    end = day.end;
    spans.add(WhenSpan(day.index, day.index + day.length));
  } else {
    start = today;
  }

  var hasTime = false;
  if (hour != null) {
    hasTime = true;
    final min = minute ?? 0;
    start = DateTime(start.year, start.month, start.day, hour, min);
    if (end != null) end = DateTime(end.year, end.month, end.day, hour, min);
    spans.add(WhenSpan(timeMatch!.start, timeMatch.end));
    // Forward-date a bare time that's already passed today.
    if (day == null && start.isBefore(now)) {
      start = start.add(const Duration(days: 1));
    }
  }

  return WhenHit(start, end, hasTime, spans);
}

/// Remove every [WhenHit.spans] stretch from [text], leaving the rest tidy.
String stripWhen(String text, WhenHit hit) {
  final spans = [...hit.spans]..sort((a, b) => b.start.compareTo(a.start));
  var out = text;
  for (final s in spans) {
    final start = s.start.clamp(0, out.length);
    final end = s.end.clamp(0, out.length);
    if (start >= end) continue;
    out = '${out.substring(0, start)} ${out.substring(end)}';
  }
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}
