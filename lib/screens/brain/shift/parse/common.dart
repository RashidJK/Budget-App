// Shared helpers for the shift parsers — text tidying, money detection and
// amount formatting. A direct port of Shapeshift's `lib/parse/common.ts`,
// minus the chrono date helpers (those live in shift_when.dart).

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String titleCase(String s) => s
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map(capitalize)
    .join(' ');

String collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Strip dangling connector words left behind after removing a phrase.
String tidy(String s) {
  var out = collapse(
    s.replaceAll(RegExp(r'[,;]+\s*$'), '').replaceAll(RegExp(r'^\s*[,;:-]+'), ''),
  );
  final dangling = RegExp(
    r'\s+(on|at|by|for|with|to|in|and|the|this|next|from|every)$',
    caseSensitive: false,
  );
  final leading = RegExp(r'^(on|at|by|for|and|the|to)\s+', caseSensitive: false);
  for (var i = 0; i < 4; i++) {
    final next = out.replaceAll(dangling, '').replaceAll(leading, '');
    if (next == out) break;
    out = next;
  }
  return out.trim();
}

const String defaultCurrency = '₹';

String detectCurrency(String text) {
  if (RegExp(r'\$|\busd\b|dollars?\b', caseSensitive: false).hasMatch(text)) {
    return r'$';
  }
  if (RegExp(r'€|\beur(os?)?\b', caseSensitive: false).hasMatch(text)) return '€';
  if (RegExp(r'£|\bgbp\b|pounds? sterling', caseSensitive: false).hasMatch(text)) {
    return '£';
  }
  return defaultCurrency;
}

final RegExp _amountRe = RegExp(
  r'(?:₹|rs\.?|inr|\$|€|£)?\s?(\d[\d,]*(?:\.\d+)?)\s?(k\b)?',
  caseSensitive: false,
);

double? toNumber(String raw) => double.tryParse(raw.replaceAll(',', ''));

class AmountHit {
  const AmountHit(this.value, this.index, this.length);
  final double value;
  final int index;
  final int length;
}

/// Find the first money-like amount in the text.
AmountHit? findAmount(String text) {
  for (final m in _amountRe.allMatches(text)) {
    final n = toNumber(m.group(1)!);
    if (n == null || !n.isFinite) continue;
    final hasK = m.group(2) != null;
    return AmountHit(hasK ? n * 1000 : n, m.start, m.group(0)!.length);
  }
  return null;
}

String removeRange(String text, int index, int length) =>
    '${text.substring(0, index)} ${text.substring(index + length)}';

/// Group an integer string the Indian way (12,34,567) or the Western way
/// (1,234,567) — `toLocaleString` has no Dart equivalent, so do it by hand.
String _group(String digits, bool indian) {
  if (digits.length <= 3) return digits;
  final head = digits.substring(0, digits.length - 3);
  final tail = digits.substring(digits.length - 3);
  final groupSize = indian ? 2 : 3;
  final buf = <String>[];
  var i = head.length;
  while (i > 0) {
    final start = (i - groupSize) < 0 ? 0 : i - groupSize;
    buf.insert(0, head.substring(start, i));
    i = start;
  }
  return '${buf.join(',')},$tail';
}

String formatAmount(double n, [String currency = defaultCurrency]) {
  final indian = currency == '₹';
  final rounded = (n * 100).round() / 100;
  final isInt = rounded == rounded.truncateToDouble();
  final neg = rounded < 0;
  final abs = rounded.abs();
  final String body;
  if (isInt) {
    body = _group(abs.toStringAsFixed(0), indian);
  } else {
    final fixed = abs.toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    body = '${_group(fixed.substring(0, dot), indian)}${fixed.substring(dot)}';
  }
  return '$currency${neg ? '-' : ''}$body';
}
