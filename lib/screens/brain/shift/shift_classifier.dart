import 'dart:math' as math;

import 'parse/color.dart' show referenceColorRe;
import 'parse/timezone.dart' show zones;
import 'shift_intent.dart';
import 'shift_signals.dart';

/// The offline intent classifier — a keyword scorer plus softmax, ported from
/// Shapeshift's jev/mock.ts. It plays the role the hosted "Jev" model plays in
/// the original: decide which card the text wants, and answer the typed
/// signal questions. Everything numeric is then computed by the parsers.
///
/// "Jev decides, code computes" — this is the decides half, running fully
/// offline so it needs no network or account.
class ClassifyResult {
  const ClassifyResult(this.intent, this.signals);
  final Answer<ShiftIntent> intent;
  final Signals signals;
}

bool _has(RegExp re, String t) => re.hasMatch(t);

final _dateWords = RegExp(
  r'\b(today|tonight|tomorrow|tmrw|mon(day)?|tue(s(day)?)?|wed(nesday)?|thu(rs(day)?)?|fri(day)?|sat(urday)?|sun(day)?|next week|this week|noon|midnight|morning|evening|\d{1,2}\s?(am|pm)|\d{1,2}:\d{2}|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\b');
final _gather = RegExp(
  r'\b(dinner|lunch|breakfast|brunch|coffee|meeting|meet|call|sync|standup|party|drinks|date|catch ?up|interview|appointment|hangout|1:1|session with|with [a-z]+)\b');
const _unit =
    r'(km|kms|kilomet(er|re)s?|mi|miles?|m|met(er|re)s?|cm|mm|ft|feet|foot|in|inch(es)?|yd|yards?|kg|kgs|kilos?|g|grams?|lbs?|pounds?|oz|ounces?|l|lit(er|re)s?|ml|gal(lons?)?|cups?|°?c|°?f|celsius|fahrenheit|kelvin|mph|kph|km/h)';
final _convertFull = RegExp('\\d\\s*$_unit\\s+(to|in|into|as)\\s+$_unit\\b');
final _convertPart = RegExp('\\d\\s*$_unit\\b');
const _colorWordsSrc =
    r'(red|crimson|scarlet|maroon|burgundy|pink|rose|coral|salmon|peach|orange|tangerine|amber|gold|yellow|mustard|lemon|cream|beige|sand|tan|brown|chocolate|olive|lime|green|sage|mint|emerald|forest|teal|turquoise|cyan|sky|blue|navy|cobalt|indigo|violet|purple|lavender|lilac|magenta|plum|grey|gray|slate|charcoal|black|white|ivory)(ish)?';
final _colorWords = RegExp('\\b$_colorWordsSrc\\b');
final _colorWordsEnd = RegExp('$_colorWordsSrc\\s*\$');
final _colorReference = RegExp(referenceColorRe.pattern, caseSensitive: false);
final _zoneWord = RegExp(
  '\\b(${(zones.keys.toList()..sort((a, b) => b.length.compareTo(a.length))).join('|')})\\b');
final _clock = RegExp(r'\b\d{1,2}(:\d{2})?\s*(am|pm)\b|\b\d{1,2}:\d{2}\b|\b(noon|midnight)\b');

Map<ShiftIntent, double> _intentScores(String raw) {
  final t = raw.toLowerCase().trim();
  final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final s = <ShiftIntent, double>{};
  void add(ShiftIntent k, double v) => s[k] = (s[k] ?? 0) + v;
  double get(ShiftIntent k) => s[k] ?? 0;
  final num = RegExp(r'\d').hasMatch(t);

  if (_has(RegExp(r'https?:\/\/|www\.|\b[a-z0-9-]+\.(com|dev|io|app|org|net|co|ai|in|so)\b'), t)) add(ShiftIntent.link, 6);
  if (_has(RegExp(r'#[0-9a-f]{3}\b|#[0-9a-f]{6}\b|rgba?\('), t)) add(ShiftIntent.color, 7);
  if (_has(RegExp(r'#[0-9a-f]{1,5}$'), t)) add(ShiftIntent.color, 3);
  if (_has(_colorWords, t)) add(ShiftIntent.color, 2.5);
  if (_has(_colorReference, t)) add(ShiftIntent.color, 4.5);
  if (_has(RegExp(r'\b(colou?r|shade|hue) (of|like)\b'), t)) add(ShiftIntent.color, 3);
  if (_has(_colorWordsEnd, t)) add(ShiftIntent.color, 1.5);
  if (_has(RegExp(r'\b(colou?r|shade|hue|palette|tone of)\b'), t)) add(ShiftIntent.color, 2);
  if (_has(RegExp(r'[\w.+-]+@[\w-]+\.\w+'), t)) add(ShiftIntent.contact, 5);
  if (_has(RegExp(r'(\+?91[\s-]?)?[6-9]\d{4}[\s-]?\d{3,5}'), t)) add(ShiftIntent.contact, 4);
  if (_has(RegExp(r"\b(remind|reminder|don'?t forget|remember to)\b"), t)) add(ShiftIntent.reminder, 6);
  if (_has(RegExp(r'\b(split|divide|share)\b'), t)) add(ShiftIntent.split, num ? 5 : 3);
  if (_has(RegExp(r'\b(between|among)\s+(\d+|two|three|four|five|six)\b'), t) && num) add(ShiftIntent.split, 2);
  if (_has(RegExp(r'\b(spent|paid|bought|cost|expense)\b'), t)) add(ShiftIntent.expense, num ? 5 : 3);
  if (_has(RegExp(r'^(₹|rs\.?|\$)\s?\d'), t)) add(ShiftIntent.expense, 2);
  if (_has(_convertFull, t)) {
    add(ShiftIntent.convert, 7);
  } else if (_has(_convertPart, t) && !_has(RegExp(r'\b(min|mins|minutes?|hours?|hrs?|sec|secs?)\b'), t) && words.length <= 3) {
    add(ShiftIntent.convert, 2);
  }
  if (_has(RegExp(r'\bconvert\b'), t)) add(ShiftIntent.convert, 3);
  if (_has(RegExp(r'^[\d\s+\-*/x×÷^().,%]+$'), t) && _has(RegExp(r'\d\s*[+\-*/x×÷^%]\s*[\d(]'), t)) add(ShiftIntent.calc, 7);
  if (_has(RegExp(r'\d\s*%\s*(of|off)\b'), t)) add(ShiftIntent.calc, 6);
  if (_has(RegExp(r"\b(what'?s|calculate|compute)\b.*\d"), t)) add(ShiftIntent.calc, 3);
  if (_has(RegExp(r'\b(timer|countdown|stopwatch|pomodoro)\b'), t)) add(ShiftIntent.timer, 6);
  if (_has(RegExp(r'\b\d+\s*(h|hr|hrs|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)\b'), t)) add(ShiftIntent.timer, 3);
  if (_has(RegExp(r'\b(focus|break|rest|nap|deep work)\b'), t) && _has(RegExp(r'\d'), t)) add(ShiftIntent.timer, 2.5);
  if (_has(RegExp(r'\b(every\s*day|daily|every (morning|night|evening)|each (day|morning)|\d\s*x\s*a\s*week|times a week|habit|weekly|every (mon|tue|wed|thu|fri|sat|sun))'), t)) add(ShiftIntent.habit, 5);
  if (_has(RegExp(r'\b(flight|fly|flying|trip|travel|vacation|holiday|train to|bus to|road ?trip|visit|getaway)\b'), t)) add(ShiftIntent.travel, 5);
  if (_has(RegExp(r'\bto [a-z]+'), t) && _has(RegExp(r'\b(next weekend|this weekend|flight|trip)\b'), t)) add(ShiftIntent.travel, 1);
  if (_has(RegExp(r'\b(or|vs)\b'), t) && t.endsWith('?')) {
    add(ShiftIntent.poll, 5.5);
  } else if (_has(RegExp(r'\b\w+ or \w+'), t)) {
    add(ShiftIntent.poll, 2);
  }
  if (_has(RegExp(r'\b(poll|vote)\b'), t)) add(ShiftIntent.poll, 3);
  if (_has(RegExp(r'\b(days?|weeks?|sleeps?)\s+(until|till|til|to go|left|before)\b|\bcount ?down\b|\bhow (many days|long) (until|till|til)\b'), t)) add(ShiftIntent.countdown, 6.5);
  final zoneHits = _zoneWord.allMatches(t).length;
  if (zoneHits >= 2 && (_has(_clock, t) || _has(RegExp(r'\b(in|to)\b'), t))) {
    add(ShiftIntent.timezone, 7);
  } else if (zoneHits == 1 && (_has(_clock, t) || _has(RegExp(r'\btime\b'), t))) {
    add(ShiftIntent.timezone, 5.5);
  }
  if (_has(RegExp(r'\b(roll|flip|toss)\b|\b\d*d\d+\b|\bcoin\b|\bdice\b|\bdie\b|\brandom\b|\b(pick|choose) (one|a random|for me)\b'), t)) add(ShiftIntent.random, 6.5);
  if (_has(RegExp(r'\b\d[\d,]*\s*(of|\/|out of)\s*\d[\d,]*\b'), t) && _has(RegExp(r'[a-z]{3,}'), t)) add(ShiftIntent.goal, 4.5);
  if (_has(RegExp(r'\b(goal|target)\b'), t)) add(ShiftIntent.goal, 3);
  if (_has(RegExp(r'\b(done|so far|saved|completed|finished)\b'), t) && _has(RegExp(r'\d'), t)) {
    add(ShiftIntent.goal, (RegExp(r'\d+').allMatches(t).length) >= 2 ? 5 : 2.5);
  }
  final listSeps = RegExp(r',|\band\b|&|\n').allMatches(t).length;
  if (listSeps >= 2) {
    add(ShiftIntent.todo, 4);
  } else if (listSeps == 1 && _has(RegExp(r'^(buy|get|todo|to do|groceries)\b'), t)) {
    add(ShiftIntent.todo, 3);
  }
  if (_has(RegExp(r'^(buy|get|pick up|grab)\b'), t)) add(ShiftIntent.todo, 2);
  final gather = _has(_gather, t);
  if (_has(_dateWords, t)) add(ShiftIntent.event, gather || words.length <= 6 ? 2.5 : 1);
  if (gather) add(ShiftIntent.event, 3);
  if (_has(RegExp(r'\b(on|over|via) (zoom|meet|teams|facetime)\b'), t)) add(ShiftIntent.event, 2);
  if (_has(RegExp(r'\b(i think|i feel|felt|feeling|thinking|wonder|realized|idea|thought|maybe we)\b'), t)) add(ShiftIntent.note, 2);
  if (words.length >= 8) {
    add(ShiftIntent.note, 3);
  } else if (words.length >= 5) {
    add(ShiftIntent.note, 2.2);
  } else if (words.length >= 3) {
    add(ShiftIntent.note, 1);
  }
  if (t.length < 3) {
    add(ShiftIntent.none, 8);
  } else if (words.length == 1 && !num) {
    add(ShiftIntent.none, 3);
  } else {
    add(ShiftIntent.none, 0.5);
  }

  // Mutual exclusions, mirroring the criteria wording.
  if (get(ShiftIntent.split) >= 5) s[ShiftIntent.calc] = math.min(get(ShiftIntent.calc), 1);
  if (get(ShiftIntent.convert) >= 7) s[ShiftIntent.calc] = math.min(get(ShiftIntent.calc), 1);
  if (get(ShiftIntent.reminder) >= 6) {
    s[ShiftIntent.event] = math.min(get(ShiftIntent.event), 2.5);
    s[ShiftIntent.habit] = math.min(get(ShiftIntent.habit), 2);
  }
  if (get(ShiftIntent.habit) >= 5) s[ShiftIntent.event] = math.min(get(ShiftIntent.event), 2);
  if (get(ShiftIntent.travel) >= 5) s[ShiftIntent.event] = math.min(get(ShiftIntent.event), 2);
  if (get(ShiftIntent.poll) >= 5) s[ShiftIntent.event] = math.min(get(ShiftIntent.event), 2);
  if (get(ShiftIntent.contact) >= 4) s[ShiftIntent.timer] = 0;
  if (get(ShiftIntent.timer) >= 3) s[ShiftIntent.convert] = math.min(get(ShiftIntent.convert), 1);
  if (get(ShiftIntent.link) >= 6) s[ShiftIntent.note] = 0;
  if (get(ShiftIntent.countdown) >= 6) s[ShiftIntent.event] = math.min(get(ShiftIntent.event), 2);
  if (get(ShiftIntent.timezone) >= 5.5) {
    s[ShiftIntent.event] = math.min(get(ShiftIntent.event), 2);
    s[ShiftIntent.convert] = math.min(get(ShiftIntent.convert), 1);
    s[ShiftIntent.timer] = math.min(get(ShiftIntent.timer), 1);
  }
  if (get(ShiftIntent.random) >= 6) {
    s[ShiftIntent.poll] = math.min(get(ShiftIntent.poll), 2);
    s[ShiftIntent.calc] = math.min(get(ShiftIntent.calc), 1);
    s[ShiftIntent.convert] = math.min(get(ShiftIntent.convert), 1);
  }
  if (get(ShiftIntent.goal) >= 4.5) s[ShiftIntent.calc] = math.min(get(ShiftIntent.calc), 1);
  return s;
}

Map<ShiftIntent, double> _softmax(Map<ShiftIntent, double> scores, double temp) {
  final exps = {for (final k in ShiftIntent.values) k: math.exp((scores[k] ?? 0) / temp)};
  final sum = exps.values.fold(0.0, (a, b) => a + b);
  return {for (final k in ShiftIntent.values) k: exps[k]! / sum};
}

Answer<String> _pick(List<String> values, String value, double confidence) {
  final rest = (1 - confidence) / math.max(1, values.length - 1);
  return Answer(value, confidence, {for (final v in values) v: v == value ? confidence : rest});
}

Answer<String> _choose(List<String> values, String t, List<(RegExp, String)> rules, String fallback) {
  for (final (re, v) in rules) {
    if (re.hasMatch(t)) return _pick(values, v, 0.86);
  }
  return _pick(values, fallback, 0.74);
}

/// Classify a line of text into an intent + its signals, fully offline.
ClassifyResult classify(String text) {
  final t = text.toLowerCase().trim();
  if (t.length < 2) {
    return ClassifyResult(
      Answer(ShiftIntent.none, 1, {ShiftIntent.none: 1}),
      Signals.neutral(),
    );
  }

  final probs = _softmax(_intentScores(t), 0.8);
  var top = ShiftIntent.values.first;
  for (final k in ShiftIntent.values) {
    if (probs[k]! > probs[top]!) top = k;
  }
  final intent = Answer(top, probs[top]!, probs);

  final colorMood = _choose(colorMoods, t, [
    (RegExp(r'\b(pastel|soft|pale|baby|light)\b'), 'pastel'),
    (RegExp(r'\b(dark|deep|midnight|navy)\b'), 'dark'),
    (RegExp(r'\b(neon|vivid|bright|electric|hot)\b'), 'vivid'),
    (RegExp(r'\b(warm|sunset|fire|red|orange|yellow|amber|coral|peach|gold)\b'), 'warm'),
    (RegExp(r'\b(cool|ocean|sea|sky|blue|green|teal|purple|mint|ice)\b'), 'cool'),
    (RegExp(r'\b(grey|gray|beige|sand|stone|neutral|cream)\b'), 'neutral'),
  ], 'neutral');

  final recurring = RegExp(r'\b(every|daily|weekly|monthly|each (day|week|morning)|\dx a week|times a week|repeat)').hasMatch(t) ? 0.88 : 0.08;
  final urgentHit = RegExp(r'\b(urgent|asap|immediately|right now|important|critical|!!)').hasMatch(t);
  final soonHit = RegExp(r'\b(today|tonight|soon|by \d|deadline|tomorrow)\b').hasMatch(t);
  final urgencyScore = urgentHit ? 1.75 : (soonHit ? 0.9 : 0.2);

  return ClassifyResult(
    intent,
    Signals(
      isQuestion: RegExp(r'\?\s*$|^(what|why|how|when|where|who|should|could|would|is|are|do|does|can)\b').hasMatch(t) ? 0.9 : 0.06,
      recurring: recurring,
      urgencyScore: urgencyScore,
      tone: _choose(tones, t, [
        (RegExp(r'\b(worried|stressed|anxious|ugh|deadline|panic|tired|frustrat)'), 'stressed'),
        (RegExp(r"\b(can'?t wait|excited|yay|so pumped|!{1,}$)"), 'excited'),
        (RegExp(r'\b(grateful|happy|love|thankful|glad|great)\b'), 'positive'),
        (RegExp(r'\b(wonder|thinking about|realized|reflect|maybe|lately|i think)\b'), 'reflective'),
      ], 'neutral'),
      eventMode: _choose(eventModes, t, [
        (RegExp(r'\b(zoom|meet|teams|facetime|video|skype|discord)\b'), 'video_call'),
        (RegExp(r'\b(phone|call|ring)\b'), 'phone_call'),
        (RegExp(r'\b(dinner|lunch|breakfast|coffee|drinks|party|at [a-z]+)\b'), 'in_person'),
      ], 'unspecified'),
      transport: _choose(transports, t, [
        (RegExp(r'\b(flight|fly|flying|plane|airport)\b'), 'flight'),
        (RegExp(r'\b(train|rail)\b'), 'train'),
        (RegExp(r'\b(bus|coach)\b'), 'bus'),
        (RegExp(r'\b(drive|car|road ?trip)\b'), 'car'),
      ], 'unspecified'),
      tripType: _choose(tripTypes, t, [
        (RegExp(r'\b(work|business|conference|client|offsite|meeting)\b'), 'work'),
        (RegExp(r'\b(vacation|holiday|beach|getaway|leisure|visit|weekend)\b'), 'leisure'),
      ], 'unspecified'),
      expenseCategory: _choose(expenseCategories, t, [
        (RegExp(r'\b(uber|ola|cab|taxi|fuel|petrol|metro|bus|train|auto|parking)\b'), 'transport'),
        (RegExp(r'\b(food|lunch|dinner|breakfast|coffee|groceries|swiggy|zomato|pizza|restaurant|drinks)\b'), 'food'),
        (RegExp(r'\b(rent|electricity|wifi|internet|bill|recharge|netflix|spotify|subscription)\b'), 'bills'),
        (RegExp(r'\b(movie|concert|game|tickets?|show)\b'), 'entertainment'),
        (RegExp(r'\b(medicine|doctor|pharmacy|gym|hospital)\b'), 'health'),
        (RegExp(r'\b(shoes|shirt|clothes|amazon|phone|laptop|headphones|gift)\b'), 'shopping'),
      ], 'other'),
      colorMood: colorMood,
      timerKind: _choose(timerKinds, t, [
        (RegExp(r'\b(focus|pomodoro|deep work|study|work)\b'), 'focus'),
        (RegExp(r'\b(break|rest|nap|breather)\b'), 'break'),
        (RegExp(r'\b(stopwatch|count up)\b'), 'stopwatch'),
      ], 'countdown'),
      hasExplicitOptions: RegExp(r'\b\w+\s+(or|vs)\s+\w+').hasMatch(t) ? 0.9 : 0.05,
      isShoppingList: RegExp(r'\b(buy|get|groceries|shopping|milk|eggs|bread|coffee|pick up|order)\b').hasMatch(t) ? 0.88 : 0.1,
    ),
  );
}
