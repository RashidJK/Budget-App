import '../../models/brain_item.dart';

/// The result of interpreting a free-typed capture.
class BrainCapture {
  const BrainCapture(this.kind, this.text, {this.url, this.dueDate});

  final BrainKind kind;
  final String text;
  final String? url;
  final DateTime? dueDate;
}

/// Turns a line of free text into a typed capture, the way the budget's command
/// parser turns "coffee 3k" into an expense.
///
/// The cues are deliberately lightweight and prefix-based, so the guess is
/// predictable and the user can always override it with a kind pill:
///   • a URL (or a bare domain)                → link
///   • "todo …", "- …", "remind me to …"       → task (with a due date if named)
///   • "journal: …", "diary: …", "log: …"      → journal
///   • anything else                            → note
class BrainParser {
  static final _url = RegExp(r'(https?://|www\.)\S+', caseSensitive: false);
  static final _bareDomain = RegExp(
    r'^[\w-]+(\.[\w-]+)+(/\S*)?$',
    caseSensitive: false,
  );

  static const _journalPrefixes = ['journal:', 'diary:', 'log:', 'dear diary'];
  static const _taskPrefixes = [
    'todo:',
    'todo ',
    'task:',
    'task ',
    '- [ ]',
    '- [] ',
    '[] ',
    '[ ] ',
    '- ',
    'remember to ',
    'remind me to ',
    'remind me ',
  ];

  /// Full interpretation. [now] lets tests pin relative dates.
  static BrainCapture parse(String raw, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final text = raw.trim();
    if (text.isEmpty) return const BrainCapture(BrainKind.note, '');

    // Link — contains a URL, or the whole thing is a bare domain.
    final urlMatch = _url.firstMatch(text);
    if (urlMatch != null || _bareDomain.hasMatch(text)) {
      return BrainCapture(
        BrainKind.link,
        text,
        url: urlMatch?.group(0) ?? text,
      );
    }

    // Journal.
    final journal = _stripPrefix(text, _journalPrefixes);
    if (journal != null) return BrainCapture(BrainKind.journal, journal);

    // Task, with an optional due date pulled from the text.
    final task = _stripPrefix(text, _taskPrefixes);
    if (task != null) {
      final (cleaned, due) = _extractDue(task, today);
      return BrainCapture(BrainKind.task, cleaned, dueDate: due);
    }

    return BrainCapture(BrainKind.note, text);
  }

  /// Kind only — cheap enough to run on every keystroke for live highlighting.
  static BrainKind detect(String raw) => parse(raw).kind;

  static String? _stripPrefix(String text, List<String> prefixes) {
    final lower = text.toLowerCase();
    for (final p in prefixes) {
      if (lower.startsWith(p)) {
        final rest = text.substring(p.length).trim();
        return rest.isEmpty ? text : rest;
      }
    }
    return null;
  }

  static (String, DateTime?) _extractDue(String text, DateTime today) {
    final lower = text.toLowerCase();
    final base = DateTime(today.year, today.month, today.day);

    final phrases = <String, DateTime>{
      'next week': base.add(const Duration(days: 7)),
      'tomorrow': base.add(const Duration(days: 1)),
      'tonight': base,
      'today': base,
    };
    for (final entry in phrases.entries) {
      final idx = lower.indexOf(entry.key);
      if (idx != -1) {
        return (_cut(text, idx, entry.key.length), entry.value);
      }
    }

    const days = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    for (var i = 0; i < days.length; i++) {
      final idx = lower.indexOf(days[i]);
      if (idx != -1) {
        var d = base;
        do {
          d = d.add(const Duration(days: 1));
        } while (d.weekday != i + 1);
        return (_cut(text, idx, days[i].length), d);
      }
    }

    return (text, null);
  }

  /// Removes the date phrase from [text] and tidies up a dangling "by"/"on".
  static String _cut(String text, int idx, int len) {
    final joined = text.substring(0, idx) + text.substring(idx + len);
    final cleaned = joined
        .replaceAll(RegExp(r'\b(by|on)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? text.trim() : cleaned;
  }
}
