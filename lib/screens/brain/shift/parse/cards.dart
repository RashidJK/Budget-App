import '../shift_format.dart';
import '../shift_when.dart';
import 'common.dart';

// The text- and date-based shift parsers: note, todo, poll, habit, goal,
// contact, link, expense, split, timer, event, reminder, countdown, travel.
// Ported from Shapeshift's per-card parsers; the date ones use shift_when.dart
// in place of chrono-node.

// ---------------------------------------------------------------- note

class NoteData {
  const NoteData(this.title, this.body);
  final String title;
  final String body;
}

NoteData parseNote(String text) {
  final lines = text.split('\n');
  final first = collapse(lines.isNotEmpty ? lines[0] : '');
  final body = collapse(lines.skip(1).join(' '));
  if (body.isNotEmpty) return NoteData(capitalize(first), body);
  final m = RegExp(r'^(.{8,80}?[.!?])\s+(.+)$').firstMatch(first);
  if (m != null) return NoteData(capitalize(m.group(1)!), m.group(2)!);
  return NoteData(capitalize(first), '');
}

double completeNote(NoteData d) {
  final words = '${d.title} ${d.body}'.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  return (words / 10).clamp(0, 1).toDouble();
}

String summaryNote(NoteData d) => d.title;

// ---------------------------------------------------------------- todo

class TodoData {
  const TodoData(this.items, this.verb);
  final List<String> items;
  final String? verb;
}

TodoData parseTodo(String text) {
  var rest = collapse(text.replaceAll('\n', ', '));
  rest = rest.replaceFirst(RegExp(r'^(?:to ?do|todo list|list|shopping list|groceries)\s*:?\s*', caseSensitive: false), '');
  String? verb;
  final vm = RegExp(r'^(buy|get|pick up|grab|order)\s+', caseSensitive: false).firstMatch(rest);
  if (vm != null) {
    verb = vm.group(1)!.toLowerCase();
    rest = rest.substring(vm.end);
  }
  final items = rest
      .split(RegExp(r'\s*(?:,|;|\s&\s|\band\b|\n)\s*', caseSensitive: false))
      .map((s) => s.trim().replaceFirst(RegExp(r'^(?:buy|get|also)\s+', caseSensitive: false), '').replaceAll(RegExp(r'[.!]+$'), ''))
      .where((s) => s.isNotEmpty)
      .map(capitalize)
      .toList();
  return TodoData(items, verb);
}

double completeTodo(TodoData d) => (d.items.length / 3).clamp(0, 1).toDouble();

String summaryTodo(TodoData d) =>
    '${d.items.length} item${d.items.length == 1 ? '' : 's'} · ${d.items.take(3).join(', ')}';

// ---------------------------------------------------------------- poll

class PollData {
  const PollData(this.title, this.options);
  final String title;
  final List<String> options;
}

PollData parsePoll(String text) {
  var t = collapse(text).replaceAll(RegExp(r'\?+$'), '');
  String? stem;

  final colon = t.indexOf(':');
  if (colon > 0) {
    stem = t.substring(0, colon).trim();
    t = t.substring(colon + 1).trim();
  }

  var parts = t.split(RegExp(r'\s*(?:,|\bor\b|\bvs\.?\b|\/)\s*', caseSensitive: false)).where((s) => s.isNotEmpty).toList();
  if (parts.length < 2) return PollData(stem != null ? '${capitalize(stem)}?' : '', const []);

  String? context;
  final last = parts.last;
  final cm = RegExp(r'\s+((?:for|on|at|this|next|tonight|tomorrow|today)\b.*)$', caseSensitive: false).firstMatch(last);
  if (cm != null && cm.start > 0) {
    context = cm.group(1);
    parts[parts.length - 1] = last.substring(0, cm.start);
  }

  if (stem == null && RegExp(r'^(?:should|shall|what|which|where|when|who|do|does|would|want|let’?s|let'
          r"'?s|vote|poll)\b", caseSensitive: false)
      .hasMatch(parts[0])) {
    final words = parts[0].split(' ');
    final take = parts[1].split(' ').length; // always >= 1 for non-empty text
    if (words.length > take) {
      stem = words.sublist(0, words.length - take).join(' ');
      parts[0] = words.sublist(words.length - take).join(' ');
    }
  }

  parts = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  final base = capitalize(stem ?? parts.join(' or '));
  parts = parts.map(capitalize).toList();
  final title = '$base${context != null ? ' $context' : ''}?';
  return PollData(title, parts);
}

double completePoll(PollData d) =>
    ((d.options.length / 2).clamp(0, 1) * 0.8 + (d.title.isNotEmpty ? 0.2 : 0)).toDouble();

String summaryPoll(PollData d) => d.title.isNotEmpty ? d.title : (d.options.isNotEmpty ? d.options.join(' / ') : 'Poll');

// ---------------------------------------------------------------- habit

class HabitData {
  const HabitData(this.title, this.days, this.perWeek, this.label);
  final String title;

  /// Days of the week, 0 = Sunday … 6 = Saturday.
  final List<int> days;
  final int? perWeek;
  final String? label;
}

const _habitDays = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

String _fullDay(int i) =>
    ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][i];

List<int> _spread(int n) {
  const presets = {
    1: [1], 2: [2, 4], 3: [1, 3, 5], 4: [1, 2, 4, 5], 5: [1, 2, 3, 4, 5],
  };
  const order = [1, 3, 5, 0, 2, 4, 6];
  final list = presets[n] ?? order.sublist(0, n > 7 ? 7 : n);
  return [...list]..sort();
}

HabitData parseHabit(String text) {
  var rest = ' ${collapse(text)} ';
  var days = <int>[];
  int? perWeek;
  String? label;

  final nx = RegExp(r'\b(\d|once|twice|thrice)\s*(?:x|times?)?\s*(?:a|per|each|every)\s+week\b', caseSensitive: false).firstMatch(rest);
  if (nx != null) {
    final word = nx.group(1)!.toLowerCase();
    perWeek = word == 'once' ? 1 : word == 'twice' ? 2 : word == 'thrice' ? 3 : int.parse(word);
    rest = rest.replaceFirst(nx.group(0)!, ' ');
    label = '$perWeek× a week';
  }

  if (RegExp(r'\b(?:every\s*day|daily|every (?:morning|night|evening|afternoon)|each (?:day|morning|night))\b', caseSensitive: false).hasMatch(rest)) {
    days = [0, 1, 2, 3, 4, 5, 6];
    final part = RegExp(r'\b(?:every|each)\s+(morning|night|evening|afternoon)\b', caseSensitive: false).firstMatch(rest);
    label = part != null ? 'Every ${part.group(1)!.toLowerCase()}' : 'Daily';
    rest = rest.replaceAll(RegExp(r'\b(?:every\s*day|daily|every (?:morning|night|evening|afternoon)|each (?:day|morning|night))\b', caseSensitive: false), ' ');
  } else if (RegExp(r'\b(?:weekdays|every weekday)\b', caseSensitive: false).hasMatch(rest)) {
    days = [1, 2, 3, 4, 5];
    label = 'Weekdays';
    rest = rest.replaceAll(RegExp(r'\b(?:every\s+)?weekdays?\b', caseSensitive: false), ' ');
  } else if (RegExp(r'\b(?:weekends|every weekend)\b', caseSensitive: false).hasMatch(rest)) {
    days = [0, 6];
    label = 'Weekends';
    rest = rest.replaceAll(RegExp(r'\b(?:every\s+)?weekends?\b', caseSensitive: false), ' ');
  } else {
    final found = <int>{};
    rest = rest.replaceAllMapped(
      RegExp(r'\b(sun|mon|tue|tues|wed|thu|thur|thurs|fri|sat)(?:day|nesday|sday|urday|rsday)?s?\b', caseSensitive: false),
      (m) {
        final i = _habitDays.indexOf(m.group(1)!.substring(0, 3).toLowerCase());
        if (i >= 0) found.add(i);
        return ' ';
      },
    );
    if (found.isNotEmpty) {
      days = found.toList()..sort();
      label ??= days.length == 1 ? 'Every ${_fullDay(days[0])}' : '${days.length}× a week';
    }
  }

  if (label == null && RegExp(r'\bweekly\b', caseSensitive: false).hasMatch(rest)) {
    perWeek = 1;
    label = 'Weekly';
  }

  rest = rest.replaceAll(RegExp(r"\b(?:every|each|weekly|habit|routine|start|i want to|i will|i'll|and)\b", caseSensitive: false), ' ');
  rest = rest.replaceAll(RegExp(r'\b(?:in the )?(?:morning|night|evening)s?\b', caseSensitive: false), ' ');
  if (days.isEmpty && perWeek != null) days = _spread(perWeek);
  return HabitData(capitalize(tidy(rest)), days, perWeek, label);
}

double completeHabit(HabitData d) => (d.title.isNotEmpty ? 0.5 : 0) + (d.label != null ? 0.5 : 0);

String summaryHabit(HabitData d) =>
    [d.title.isNotEmpty ? d.title : 'Habit', d.label].where((e) => e != null && e.isNotEmpty).join(' · ');

// ---------------------------------------------------------------- goal

class GoalData {
  const GoalData(this.title, this.current, this.target, this.unit);
  final String title;
  final double current;
  final double? target;
  final String? unit;
}

const _goalNum = r'(\d[\d,]*(?:\.\d+)?)(k)?';

double _goalVal(String? num, String? k) =>
    (double.tryParse((num ?? '0').replaceAll(',', '')) ?? 0) * (k != null ? 1000 : 1);

GoalData parseGoal(String text) {
  var rest = ' ${collapse(text)} ';
  var current = 0.0;
  double? target;

  final of = RegExp('\\b$_goalNum\\s*(?:of|/|out of)\\s*$_goalNum\\b', caseSensitive: false).firstMatch(rest);
  if (of != null) {
    current = _goalVal(of.group(1), of.group(2));
    target = _goalVal(of.group(3), of.group(4));
    rest = rest.replaceFirst(of.group(0)!, ' ');
  } else {
    final done = RegExp('(?:\\b(?:saved|done|finished|completed|at)\\s+$_goalNum|\\b$_goalNum\\s*(?:done|so far|completed|finished|in))\\b', caseSensitive: false).firstMatch(rest);
    if (done != null) {
      current = _goalVal(done.group(1) ?? done.group(3), done.group(2) ?? done.group(4));
      rest = rest.replaceFirst(done.group(0)!, ' ');
    }
    final t = RegExp('\\b$_goalNum\\b', caseSensitive: false).firstMatch(rest);
    if (t != null) {
      target = _goalVal(t.group(1), t.group(2));
      rest = rest.replaceFirst(t.group(0)!, ' ');
    }
  }

  final unitMatch = RegExp(r'^\s*(?:[a-z]+\s+)?(books?|km|kms|miles?|pages?|workouts?|runs?|steps?|kg|lbs?|hours?|articles?|courses?|₹|rs|\$|dollars|rupees)\b', caseSensitive: false).firstMatch(rest);
  final unit = unitMatch?.group(1)?.toLowerCase();
  rest = rest.replaceAll(RegExp(r'\b(?:goal|target|progress|this year|this month|so far|done|by (?:end of )?\w+|in (?:january|february|march|april|may|june|july|august|september|october|november|december))\b', caseSensitive: false), ' ');
  rest = rest.replaceAll(RegExp(r'[,;]+'), ' ');
  return GoalData(capitalize(tidy(rest)), current < (target ?? current) ? current : (target ?? current), target, unit);
}

double completeGoal(GoalData d) =>
    (d.target != null ? 0.6 : 0) + (d.title.isNotEmpty ? 0.3 : 0) + (d.current != 0 ? 0.1 : 0);

String _num(double n) => n == n.truncateToDouble() ? n.toStringAsFixed(0) : '$n';

String summaryGoal(GoalData d) => d.target != null
    ? '${d.title.isNotEmpty ? d.title : 'Goal'} · ${_num(d.current)}/${_num(d.target!)}${d.unit != null ? ' ${d.unit}' : ''}'
    : (d.title.isNotEmpty ? d.title : 'Goal');

// ---------------------------------------------------------------- contact

class ContactData {
  const ContactData(this.name, this.phone, this.email, this.initials);
  final String name;
  final String? phone;
  final String? email;
  final String initials;
}

String formatPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) return '${digits.substring(0, 5)} ${digits.substring(5)}';
  if (digits.length == 12 && digits.startsWith('91')) {
    return '+91 ${digits.substring(2, 7)} ${digits.substring(7)}';
  }
  return raw.trim();
}

ContactData parseContact(String text) {
  var rest = collapse(text);
  final em = RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+').firstMatch(rest);
  final email = em?.group(0)?.toLowerCase();
  if (em != null) rest = rest.replaceFirst(em.group(0)!, ' ');

  String? phone;
  final pm = RegExp(r'(?:\+?\d{1,3}[\s-]?)?\(?\d{3,5}\)?[\s-]?\d{3,5}[\s-]?\d{0,5}').firstMatch(rest);
  if (pm != null && pm.group(0)!.replaceAll(RegExp(r'\D'), '').length >= 7) {
    phone = formatPhone(pm.group(0)!);
    rest = rest.replaceFirst(pm.group(0)!, ' ');
  }

  final name = titleCase(
    rest
        .replaceAll(RegExp(r'\b(?:save|add|contact|number|phone|email|mail|is|his|her|their|new|:)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r"[^a-z\s'.-]", caseSensitive: false), ' ')
        .trim(),
  );
  final initials = name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
  return ContactData(name, phone, email, initials);
}

double completeContact(ContactData d) =>
    (d.name.isNotEmpty ? 0.4 : 0) + (d.phone != null || d.email != null ? 0.4 : 0) + (d.phone != null && d.email != null ? 0.2 : 0);

String summaryContact(ContactData d) =>
    [d.name.isNotEmpty ? d.name : 'Contact', d.phone ?? d.email].where((e) => e != null && e.isNotEmpty).join(' · ');

// ---------------------------------------------------------------- link

class LinkData {
  const LinkData(this.url, this.domain, this.monogram, this.note);
  final String? url;
  final String? domain;
  final String monogram;
  final String note;
}

final RegExp _linkRe = RegExp(
  r'((?:https?:\/\/|www\.)[^\s]+|[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|dev|io|app|org|net|co|ai|in|so|xyz|me|design|sh|gg|tv)(?:\/[^\s]*)?)',
  caseSensitive: false,
);

LinkData parseLink(String text) {
  final m = _linkRe.firstMatch(text);
  if (m == null) return LinkData(null, null, '', capitalize(tidy(text)));
  final raw = m.group(1)!.replaceAll(RegExp(r'[.,)]+$'), '');
  final url = RegExp(r'^https?:\/\/', caseSensitive: false).hasMatch(raw) ? raw : 'https://$raw';
  String? domain;
  try {
    final host = Uri.parse(url).host.replaceFirst(RegExp(r'^www\.'), '');
    domain = host.isNotEmpty ? host : raw.replaceAll(RegExp(r'^https?:\/\/'), '').split('/')[0];
  } catch (_) {
    domain = raw.replaceAll(RegExp(r'^https?:\/\/'), '').split('/')[0];
  }
  final note = capitalize(tidy(collapse(text.replaceFirst(m.group(0)!, ' '))));
  return LinkData(url, domain, (domain.isNotEmpty ? domain[0] : '').toUpperCase(), note);
}

double completeLink(LinkData d) => (d.url != null ? 0.8 : 0) + (d.note.isNotEmpty ? 0.2 : 0);

String summaryLink(LinkData d) =>
    [d.domain ?? 'Link', d.note].where((e) => e.isNotEmpty).join(' · ');

// ---------------------------------------------------------------- expense

class ExpenseData {
  const ExpenseData(this.amount, this.item, this.currency);
  final double? amount;
  final String item;
  final String currency;
}

ExpenseData parseExpense(String text) {
  final amount = findAmount(text);
  final rest = amount != null ? removeRange(text, amount.index, amount.length) : text;
  final on = RegExp(r'\b(?:on|for|at|in)\s+(.+)$', caseSensitive: false).firstMatch(rest);
  var item = on != null ? on.group(1)! : rest;
  item = item.replaceAll(RegExp(r'\b(?:spent|paid|pay|bought|cost|costs|rupees|rs|bucks|dollars|today|yesterday)\b', caseSensitive: false), ' ');
  return ExpenseData(amount?.value, capitalize(tidy(item)), detectCurrency(text));
}

double completeExpense(ExpenseData d) => (d.amount != null ? 0.6 : 0) + (d.item.isNotEmpty ? 0.4 : 0);

String summaryExpense(ExpenseData d) {
  final s = [
    if (d.amount != null) formatAmount(d.amount!, d.currency),
    if (d.item.isNotEmpty) d.item,
  ].join(' · ');
  return s.isNotEmpty ? s : 'Expense';
}

// ---------------------------------------------------------------- split

class SplitData {
  const SplitData(this.total, this.people, this.currency);
  final double? total;
  final int? people;
  final String currency;
}

const Map<String, int> _wordNum = {
  'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
};

SplitData parseSplit(String text) {
  var rest = text;
  int? people;

  final n = RegExp(r'\b(?:between|among|amongst|with|by|for|into)\s+(\d+|two|three|four|five|six|seven|eight|nine|ten)\b(?:\s*(?:people|persons|friends|of us|ways))?', caseSensitive: false).firstMatch(rest) ??
      RegExp(r'\b(\d+|two|three|four|five|six|seven|eight|nine|ten)\s*(?:ways|people|persons|friends|of us)\b', caseSensitive: false).firstMatch(rest);
  if (n != null) {
    final g = n.group(1)!.toLowerCase();
    people = _wordNum[g] ?? int.tryParse(g);
    rest = rest.replaceFirst(n.group(0)!, ' ');
  } else {
    final names = RegExp(r'\b(?:between|among|with)\s+(.+)$', caseSensitive: false).firstMatch(rest);
    if (names != null) {
      final parts = names.group(1)!.split(RegExp(r'\s*(?:,|&|\band\b)\s*', caseSensitive: false)).where((p) => RegExp(r'[a-z]', caseSensitive: false).hasMatch(p)).toList();
      if (parts.length >= 2) {
        people = parts.length;
      } else if (parts.length == 1 && !RegExp(r'\d').hasMatch(parts[0])) {
        people = 2;
      }
      rest = rest.replaceFirst(names.group(0)!, ' ');
    }
  }

  final amount = findAmount(rest);
  return SplitData(amount?.value, people != null && people > 0 ? people : null, detectCurrency(text));
}

double completeSplit(SplitData d) => (d.total != null ? 0.55 : 0) + (d.people != null ? 0.45 : 0);

String summarySplit(SplitData d) => d.total != null && d.people != null
    ? '${formatAmount(d.total!, d.currency)} ÷ ${d.people} = ${formatAmount(d.total! / d.people!, d.currency)} each'
    : 'Split';

// ---------------------------------------------------------------- timer

class TimerData {
  const TimerData(this.seconds, this.label);
  final int? seconds;
  final String label;
}

const Map<String, int> _timerUnit = {'h': 3600, 'm': 60, 's': 1};

TimerData parseTimer(String text) {
  var rest = ' ${collapse(text).toLowerCase()} ';
  var seconds = 0;
  var found = false;

  final special = <(RegExp, int)>[
    (RegExp(r'\bpomodoro\b'), 25 * 60),
    (RegExp(r'\bhalf an? hour\b'), 30 * 60),
    (RegExp(r'\ban? hour\b'), 60 * 60),
    (RegExp(r'\ba minute\b'), 60),
  ];
  for (final (re, s) in special) {
    if (re.hasMatch(rest)) {
      seconds += s;
      found = true;
      if (re.pattern != r'\bpomodoro\b') rest = rest.replaceAll(re, ' ');
    }
  }

  rest = rest.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b'),
    (m) {
      seconds += (double.parse(m.group(1)!) * _timerUnit[m.group(2)![0]]!).round();
      found = true;
      return ' ';
    },
  );

  rest = rest.replaceAllMapped(RegExp(r'\b(\d{1,2}):(\d{2})\b'), (m) {
    seconds += int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
    found = true;
    return ' ';
  });

  final label = tidy(rest.replaceAll(RegExp(r'\b(?:timer|set|start|a|for|countdown|of)\b'), ' '));
  return TimerData(found ? seconds : null, capitalize(label));
}

double completeTimer(TimerData d) => (d.seconds != null ? 0.8 : 0) + (d.label.isNotEmpty ? 0.2 : 0);

String formatClock(int total) {
  final s = total < 0 ? 0 : total;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String summaryTimer(TimerData d) =>
    [d.label.isNotEmpty ? d.label : 'Timer', if (d.seconds != null) formatClock(d.seconds!)].join(' · ');

// ---------------------------------------------------------------- event

class EventData {
  const EventData({required this.title, this.date, this.hasTime = false, this.people = const [], this.link, this.location});
  final String title;
  final DateTime? date;
  final bool hasTime;
  final List<String> people;
  final String? link;
  final String? location;
}

const Map<String, String> _eventLinks = {
  'zoom': 'Zoom', 'meet': 'Google Meet', 'google meet': 'Google Meet', 'gmeet': 'Google Meet',
  'teams': 'Teams', 'facetime': 'FaceTime', 'skype': 'Skype', 'discord': 'Discord', 'whatsapp': 'WhatsApp',
};

final RegExp _eventStop = RegExp(r'\s+(?:on|at|in|for|about|to|from|via|over)\s+.*$', caseSensitive: false);

EventData parseEvent(String text, {DateTime? ref}) {
  var rest = ' ${collapse(text)} ';

  final date = findWhen(rest, ref: ref);
  if (date != null) rest = stripWhen(rest, date);
  rest = ' $rest ';

  String? link;
  final lm = RegExp(r'\s(?:on|over|via)\s+(google meet|gmeet|zoom|meet|teams|facetime|skype|discord|whatsapp)\b', caseSensitive: false).firstMatch(rest);
  if (lm != null) {
    link = _eventLinks[lm.group(1)!.toLowerCase()];
    rest = removeRange(rest, lm.start, lm.group(0)!.length);
  }

  String? location;
  final loc = RegExp(r"\s(?:at|in)\s+(?!\d)([a-z][\w' ]{1,40}?)(?=\s+(?:with|on|for)\s|\s*$)", caseSensitive: false).firstMatch(rest);
  if (loc != null) {
    location = titleCase(loc.group(1)!.trim());
    rest = removeRange(rest, loc.start, loc.group(0)!.length);
  }

  var people = <String>[];
  final wm = RegExp(r'\swith\s+(.+)$', caseSensitive: false).firstMatch(rest);
  if (wm != null) {
    final segment = wm.group(1)!.replaceAll(_eventStop, '');
    people = segment
        .split(RegExp(r'\s*(?:,|&|\band\b)\s*', caseSensitive: false))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && p.split(' ').length <= 3 && !RegExp(r'^(the|my|a)$', caseSensitive: false).hasMatch(p))
        .map(titleCase)
        .toList();
    rest = '${rest.substring(0, wm.start)} ${wm.group(1)!.substring(segment.length)}';
  }

  return EventData(
    title: capitalize(tidy(rest)),
    date: date?.start,
    hasTime: date?.hasTime ?? false,
    people: people,
    link: link,
    location: location,
  );
}

double completeEvent(EventData d) =>
    (d.title.isNotEmpty ? 0.35 : 0) + (d.date != null ? 0.3 : 0) + (d.hasTime ? 0.2 : 0) + (d.people.isNotEmpty || d.link != null || d.location != null ? 0.15 : 0);

String summaryEvent(EventData d) => [
  d.title.isNotEmpty ? d.title : 'Event',
  if (d.date != null) formatWhenLine(d.date!, d.hasTime),
].join(' · ');

// ---------------------------------------------------------------- reminder

class ReminderData {
  const ReminderData(this.task, this.when, this.hasTime);
  final String task;
  final DateTime? when;
  final bool hasTime;
}

ReminderData parseReminder(String text, {DateTime? ref}) {
  var rest = ' ${collapse(text)} ';
  rest = rest.replaceFirst(RegExp(r"\s(?:please\s+)?(?:remind me(?:\s+to)?|reminder:?|don'?t forget(?:\s+to)?|remember to)\s", caseSensitive: false), ' ');
  rest = rest.replaceAll(RegExp(r'\s(?:urgent(?:ly)?|asap|important|!+)(?=\s|$)', caseSensitive: false), ' ');
  final date = findWhen(rest, ref: ref);
  if (date != null) rest = stripWhen(rest, date);
  return ReminderData(capitalize(tidy(rest)), date?.start, date?.hasTime ?? false);
}

double completeReminder(ReminderData d) =>
    (d.task.isNotEmpty ? 0.55 : 0) + (d.when != null ? 0.3 : 0) + (d.hasTime ? 0.15 : 0);

String summaryReminder(ReminderData d) => [
  d.task.isNotEmpty ? d.task : 'Reminder',
  if (d.when != null) dayLabel(d.when!),
].join(' · ');

// ---------------------------------------------------------------- countdown

class CountdownData {
  const CountdownData(this.title, this.date, this.days);
  final String title;
  final DateTime? date;
  final int? days;
}

const Map<String, List<int>> _holidays = {
  'christmas': [12, 25], 'xmas': [12, 25], 'christmas eve': [12, 24],
  'new year': [1, 1], 'new years': [1, 1], "new year's": [1, 1],
  'new years eve': [12, 31], "new year's eve": [12, 31],
  'halloween': [10, 31], "valentine's day": [2, 14], 'valentines day': [2, 14], 'valentines': [2, 14],
  'independence day': [8, 15], 'republic day': [1, 26],
};

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

int daysBetween(DateTime from, DateTime to) =>
    _startOfDay(to).difference(_startOfDay(from)).inDays;

CountdownData parseCountdown(String text, {DateTime? ref}) {
  final now = ref ?? DateTime.now();
  var rest = ' ${collapse(text)} ';
  DateTime? date;
  var title = '';

  final names = _holidays.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final name in names) {
    final re = RegExp('\\b${name.replaceAll("'", "'?")}\\b', caseSensitive: false);
    final m = re.firstMatch(rest);
    if (m == null) continue;
    final md = _holidays[name]!;
    date = DateTime(now.year, md[0], md[1]);
    if (daysBetween(now, date) < 0) date = DateTime(now.year + 1, md[0], md[1]);
    title = name.replaceAllMapped(RegExp(r'\b\w'), (c) => c.group(0)!.toUpperCase()).replaceAll("'S", "'s");
    rest = rest.replaceFirst(m.group(0)!, ' ');
    break;
  }

  if (date == null) {
    final hit = findWhen(rest, ref: now);
    if (hit != null) {
      date = hit.start;
      rest = stripWhen(rest, hit);
    }
  }

  if (title.isEmpty) {
    title = capitalize(tidy(rest
        .replaceAll(RegExp(r'\b(?:how many|days?|weeks?|until|till|til|to go|left|countdown|count down|before|is it|are there|the)\b', caseSensitive: false), ' ')
        .replaceAll('?', ' ')));
  }

  return CountdownData(title, date, date != null ? daysBetween(now, date) : null);
}

double completeCountdown(CountdownData d) => (d.date != null ? 0.7 : 0) + (d.title.isNotEmpty ? 0.3 : 0);

String summaryCountdown(CountdownData d) {
  if (d.days == null) return d.title.isNotEmpty ? d.title : 'Countdown';
  if (d.days == 0) return '${d.title.isNotEmpty ? d.title : 'It'} is today';
  final t = d.title.isNotEmpty ? d.title : 'then';
  return '${d.days!.abs()} days ${d.days! < 0 ? 'since' : 'until'} $t';
}

// ---------------------------------------------------------------- travel

class TravelData {
  const TravelData(this.destination, this.origin, this.start, this.end);
  final String? destination;
  final String? origin;
  final DateTime? start;
  final DateTime? end;
}

final RegExp _travelStop = RegExp(
  r'\s+(?:to|next|this|on|for|from|in|by|via|tomorrow|today|tonight|with|and|trip|flight|train|bus|weekend|week|month|work|business|vacation|holiday|leave|leaving|return(?:ing)?|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|(?:mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)(?:day)?|\d)\b.*$',
  caseSensitive: false,
);

TravelData parseTravel(String text, {DateTime? ref}) {
  var rest = ' ${collapse(text)} ';
  DateTime? start;
  DateTime? end;

  final hit = findWhen(rest.replaceAll(RegExp(r'[–—]'), '-'), ref: ref);
  if (hit != null) {
    start = hit.start;
    end = hit.end;
    rest = stripWhen(rest, hit);
    rest = ' $rest ';
  }

  String? grab(RegExp re) {
    final m = re.firstMatch(rest);
    if (m == null) return null;
    final place = ' ${m.group(1)!}'.replaceAll(_travelStop, '').trim();
    return place.isNotEmpty ? titleCase(place) : null;
  }

  final destination = grab(RegExp(r"\b(?:to|for|visit(?:ing)?|in)\s+([a-z][a-z .'-]{1,40})", caseSensitive: false));
  final origin = grab(RegExp(r"\bfrom\s+([a-z][a-z .'-]{1,40})", caseSensitive: false));
  return TravelData(destination, origin, start, end);
}

double completeTravel(TravelData d) =>
    (d.destination != null ? 0.5 : 0) + (d.start != null ? 0.35 : 0) + (d.end != null ? 0.15 : 0);

String summaryTravel(TravelData d) => d.destination != null ? 'Trip to ${d.destination}' : 'Trip';
