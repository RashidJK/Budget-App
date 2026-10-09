import 'dart:math' as math;

/// Randomisers: "roll 2d6", "flip a coin", "random number 1-100",
/// "pick one: tacos, sushi or pizza". Ported from Shapeshift's random parser.
enum RandomKind { dice, coin, number, pick }

class RandomData {
  const RandomData(this.kind, {this.count = 1, this.sides = 6, this.min = 1, this.max = 100, this.options = const []});
  final RandomKind kind;
  final int count;
  final int sides;
  final int min;
  final int max;
  final List<String> options;
}

const Map<String, int> _words = {'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6};

int _clamp(num n, int lo, int hi) => n.isFinite ? n.clamp(lo, hi).toInt() : lo;

RandomData parseRandom(String text) {
  final t = text.toLowerCase().trim();

  if (RegExp(r'\b(coin|heads|tails|toss)\b').hasMatch(t)) {
    return const RandomData(RandomKind.coin);
  }

  final dnd = RegExp(r'\b(\d+)?d(\d+)\b').firstMatch(t);
  if (dnd != null) {
    return RandomData(
      RandomKind.dice,
      count: _clamp(int.tryParse(dnd.group(1) ?? '1') ?? 1, 1, 10),
      sides: _clamp(int.parse(dnd.group(2)!), 2, 1000),
    );
  }

  final dice = RegExp(r'\b(\d+|a|an|one|two|three|four|five|six)?\s*(?:dice|die)\b').firstMatch(t);
  if (dice != null) {
    final g = dice.group(1);
    final n = g != null ? (_words[g] ?? int.tryParse(g) ?? 1) : 1;
    return RandomData(RandomKind.dice, count: _clamp(n, 1, 10), sides: 6);
  }

  final range = RegExp(r'\b(-?\d+)\s*(?:-|–|to|and)\s*(-?\d+)\b').firstMatch(t);
  if (range != null && RegExp(r'\b(number|random|between|pick|choose|rng)\b').hasMatch(t)) {
    final a = int.parse(range.group(1)!);
    final b = int.parse(range.group(2)!);
    return RandomData(RandomKind.number, min: math.min(a, b), max: math.max(a, b));
  }

  final list = t.replaceFirst(
    RegExp(r'^.*?\b(?:pick|choose|decide|random(?:ly)?|between)\b\s*(?:one|a random one)?\s*(?:from|between|of|:)?\s*'),
    '',
  );
  final options = list
      .split(RegExp(r'\s*(?:,|\bor\b|\/|\n)\s*'))
      .map((s) => s.trim().replaceAll(RegExp(r'[?.!]+$'), ''))
      .where((s) => s.isNotEmpty)
      .map((s) => s[0].toUpperCase() + s.substring(1))
      .toList();
  if (options.length >= 2) return RandomData(RandomKind.pick, options: options);

  return const RandomData(RandomKind.number, min: 1, max: 100);
}

List<String> rollRandom(RandomData d, [math.Random? rng]) {
  final rand = rng ?? math.Random();
  int intIn(int lo, int hi) => lo + rand.nextInt(hi - lo + 1);
  switch (d.kind) {
    case RandomKind.coin:
      return [rand.nextDouble() < 0.5 ? 'Heads' : 'Tails'];
    case RandomKind.dice:
      return List.generate(d.count, (_) => '${intIn(1, d.sides)}');
    case RandomKind.number:
      return ['${intIn(d.min, d.max)}'];
    case RandomKind.pick:
      return [d.options[intIn(0, d.options.length - 1)]];
  }
}

String describeRandom(RandomData d) => switch (d.kind) {
  RandomKind.coin => 'Coin flip',
  RandomKind.dice => d.sides == 6 ? '${d.count} ${d.count == 1 ? 'die' : 'dice'}' : '${d.count}d${d.sides}',
  RandomKind.number => 'Number from ${d.min} to ${d.max}',
  RandomKind.pick => 'Pick one of ${d.options.length}',
};

double completeRandom(RandomData d) => 1;

String summaryRandom(RandomData d) => describeRandom(d);
