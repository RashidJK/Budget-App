import 'dart:math' as math;

/// Natural-language arithmetic: "18% of 3450", "1200 / 3", "15% off 80".
/// Ported from Shapeshift's calc parser — normalise phrasing to an expression,
/// then evaluate it with shunting-yard. Never uses `eval`.
class CalcData {
  const CalcData(this.expression, this.result);
  final String expression;
  final double? result;
}

const _prec = {'+': 1, '-': 1, '*': 2, '/': 2, '^': 3, 'u-': 4};
const _rightAssoc = {'^', 'u-'};

String normalizeExpression(String text) {
  var s = text.toLowerCase().trim();
  s = s
      .replaceAll(RegExp(r"^(?:what(?:'s| is)|calc(?:ulate)?|compute|how much is)\s+"), '')
      .replaceAll(RegExp(r'[=?]+\s*$'), '');
  s = s.replaceAllMapped(RegExp(r'(\d),(\d{3})'), (m) => '${m[1]}${m[2]}');
  s = s.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*%\s*off\s+(\d+(?:\.\d+)?)'),
    (m) => '${m[2]}*(1-${m[1]}/100)',
  );
  s = s.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*%\s*of\s+'),
    (m) => '(${m[1]}/100)*',
  );
  s = s.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)\s*%'), (m) => '(${m[1]}/100)');
  s = s
      .replaceAll(RegExp(r'\bplus\b'), '+')
      .replaceAll(RegExp(r'\bminus\b'), '-')
      .replaceAll(RegExp(r'\b(?:times|multiplied by)\b'), '*');
  s = s
      .replaceAll(RegExp(r'\b(?:divided by|over)\b'), '/')
      .replaceAll(RegExp(r'\bsquared\b'), '^2')
      .replaceAll(RegExp(r'\bcubed\b'), '^3');
  s = s
      .replaceAll(RegExp(r'[×x]'), '*')
      .replaceAll('÷', '/')
      .replaceAll('**', '^');
  return s;
}

class _Tok {
  _Tok(this.type, [this.num = 0, this.op = '']);
  final String type; // num | op | lp | rp
  final double num;
  final String op;
}

List<_Tok>? _tokenize(String s) {
  final out = <_Tok>[];
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == ' ') {
      i++;
      continue;
    }
    if (RegExp(r'[\d.]').hasMatch(c)) {
      var j = i;
      while (j < s.length && RegExp(r'[\d.]').hasMatch(s[j])) {
        j++;
      }
      final v = double.tryParse(s.substring(i, j));
      if (v == null || !v.isFinite) return null;
      out.add(_Tok('num', v));
      i = j;
      continue;
    }
    if ('+-*/^'.contains(c)) {
      final prev = out.isNotEmpty ? out.last : null;
      final unary =
          c == '-' && (prev == null || prev.type == 'op' || prev.type == 'lp');
      out.add(_Tok('op', 0, unary ? 'u-' : c));
      i++;
      continue;
    }
    if (c == '(') {
      final prev = out.isNotEmpty ? out.last : null;
      if (prev != null && (prev.type == 'num' || prev.type == 'rp')) {
        out.add(_Tok('op', 0, '*'));
      }
      out.add(_Tok('lp'));
      i++;
      continue;
    }
    if (c == ')') {
      out.add(_Tok('rp'));
      i++;
      continue;
    }
    return null;
  }
  return out;
}

/// Shunting-yard to RPN, then evaluate.
double? evaluate(String expr) {
  final tokens = _tokenize(expr);
  if (tokens == null || tokens.isEmpty) return null;
  final output = <_Tok>[];
  final ops = <_Tok>[];
  for (final tok in tokens) {
    if (tok.type == 'num') {
      output.add(tok);
    } else if (tok.type == 'op') {
      while (ops.isNotEmpty) {
        final top = ops.last;
        if (top.type != 'op') break;
        final p1 = _prec[tok.op]!;
        final p2 = _prec[top.op]!;
        if (p2 > p1 || (p2 == p1 && !_rightAssoc.contains(tok.op))) {
          output.add(ops.removeLast());
        } else {
          break;
        }
      }
      ops.add(tok);
    } else if (tok.type == 'lp') {
      ops.add(tok);
    } else {
      while (ops.isNotEmpty && ops.last.type != 'lp') {
        output.add(ops.removeLast());
      }
      if (ops.isEmpty) return null;
      ops.removeLast();
    }
  }
  while (ops.isNotEmpty) {
    final op = ops.removeLast();
    if (op.type == 'lp') return null;
    output.add(op);
  }
  final stack = <double>[];
  for (final tok in output) {
    if (tok.type == 'num') {
      stack.add(tok.num);
    } else if (tok.type == 'op') {
      if (tok.op == 'u-') {
        if (stack.isEmpty) return null;
        stack.add(-stack.removeLast());
        continue;
      }
      if (stack.length < 2) return null;
      final b = stack.removeLast();
      final a = stack.removeLast();
      final r = switch (tok.op) {
        '+' => a + b,
        '-' => a - b,
        '*' => a * b,
        '/' => a / b,
        _ => math.pow(a, b).toDouble(),
      };
      stack.add(r);
    }
  }
  if (stack.length != 1 || !stack.first.isFinite) return null;
  return stack.first;
}

String prettyExpression(String expr) => expr
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll('*', ' × ')
    .replaceAll('/', ' ÷ ')
    .replaceAll('+', ' + ')
    .replaceAllMapped(RegExp(r'(?<=[\d)])-'), (_) => ' − ')
    .replaceAll('^', '^');

CalcData parseCalc(String text) {
  final norm = normalizeExpression(text);
  final result = evaluate(norm);
  final pretty = text.contains('%')
      ? text.trim().replaceAll(RegExp(r'[=?]+\s*$'), '')
      : prettyExpression(norm);
  return CalcData(
    pretty,
    result == null ? null : (result * 1e10).round() / 1e10,
  );
}

double completeCalc(CalcData d) =>
    d.result != null ? 1 : (d.expression.isNotEmpty ? 0.3 : 0);

/// Group a plain number with thousands separators (Western), trimming a
/// redundant ".0".
String formatPlainNumber(double n) {
  if (n == n.truncateToDouble()) {
    final digits = n.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return '${n < 0 ? '-' : ''}$buf';
  }
  return (n * 1e10).round() / 1e10 == n ? '$n' : n.toStringAsFixed(2);
}

String summaryCalc(CalcData d) =>
    d.result != null ? '${d.expression} = ${formatPlainNumber(d.result!)}' : d.expression;
