import 'shift_classifier.dart';
import 'shift_intent.dart';

// Turns a flickery stream of classifier results into calm UI states. Raw model
// output jitters as you type, so a card only commits when a challenger wins
// twice in a row (or is very sure), and a near-tie is offered as a choice.
// Ported from Shapeshift's decide.ts.

/// What the capture bar is showing right now.
sealed class UiState {
  const UiState();
}

/// Just a text box — no card yet.
class InputState extends UiState {
  const InputState();
}

/// A faint preview the user hasn't committed to.
class GhostState extends UiState {
  const GhostState(this.intent);
  final ShiftIntent intent;
}

/// A close call between two intents, offered as "did you mean" chips.
class ChooseState extends UiState {
  const ChooseState(this.a, this.b);
  final ShiftIntent a;
  final ShiftIntent b;
}

/// A settled card. [forced] when the user picked it by hand.
class CommittedState extends UiState {
  const CommittedState(this.intent, {this.forced = false});
  final ShiftIntent intent;
  final bool forced;
}

const _inputBelow = 0.4;
const _commitAt = 0.7;
const _chooseGap = 0.15;
const _chooseFloor = 0.25;
const _challengerOverride = 0.85;
const _challengerWins = 2;
const _dropBelow = 0.3;
const _forcedChangeRatio = 0.3;

typedef Challenger = ({ShiftIntent intent, int wins});

class DecideMemory {
  const DecideMemory(this.ui, this.challenger, this.forcedText);
  final UiState ui;
  final Challenger? challenger;
  final String? forcedText;
}

const DecideMemory initialMemory = DecideMemory(InputState(), null, null);

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = <int>[i];
    for (var j = 1; j <= b.length; j++) {
      cur.add([
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      ].reduce((x, y) => x < y ? x : y));
    }
    prev = cur;
  }
  return prev[b.length];
}

bool changedSubstantially(String from, String to) {
  final len = [from.length, to.length, 1].reduce((a, b) => a > b ? a : b);
  return levenshtein(from, to) > _forcedChangeRatio * len;
}

List<MapEntry<ShiftIntent, double>> _ranked(ClassifyResult result) {
  final entries = result.intent.probabilities.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries;
}

/// Stateless mapping from a single result to a UI state.
UiState rawState(ClassifyResult result) {
  final top = result.intent.value;
  final conf = result.intent.confidence;
  if (top == ShiftIntent.none || conf < _inputBelow) {
    final r = _ranked(result).where((e) => e.key != ShiftIntent.none).toList();
    if (top != ShiftIntent.none && r.length >= 2) {
      final a = r[0];
      final b = r[1];
      if (a.value > _chooseFloor && b.value > _chooseFloor && a.value - b.value < _chooseGap) {
        return ChooseState(a.key, b.key);
      }
    }
    return const InputState();
  }
  final r = _ranked(result);
  if (r.length >= 2) {
    final a = r[0];
    final b = r[1];
    if (a.key != ShiftIntent.none &&
        b.key != ShiftIntent.none &&
        a.value > _chooseFloor &&
        b.value > _chooseFloor &&
        a.value - b.value < _chooseGap) {
      return ChooseState(a.key, b.key);
    }
  }
  if (conf < _commitAt) return GhostState(top);
  return CommittedState(top);
}

/// Fold a new result into the calm-UI memory. [text] is what it was computed for.
DecideMemory decide(DecideMemory mem, ClassifyResult result, String text) {
  if (text.trim().isEmpty) return initialMemory;

  final prev = mem.ui;

  // A forced intent sticks until the text changes substantially.
  if (prev is CommittedState && prev.forced && mem.forcedText != null) {
    if (!changedSubstantially(mem.forcedText!, text)) return mem;
  }

  final raw = rawState(result);

  if (prev is CommittedState && !prev.forced) {
    final current = prev.intent;
    final top = result.intent.value;
    final topConf = result.intent.confidence;
    final currentP = result.intent.probabilities[current] ?? 0;

    if (top == current) return DecideMemory(prev, null, null);

    if (top == ShiftIntent.none) {
      if (currentP < _dropBelow) return const DecideMemory(InputState(), null, null);
      return DecideMemory(mem.ui, null, mem.forcedText);
    }

    if (topConf >= _challengerOverride) {
      return DecideMemory(CommittedState(top), null, null);
    }
    final wins = mem.challenger?.intent == top ? mem.challenger!.wins + 1 : 1;
    if (wins >= _challengerWins && topConf >= _inputBelow) {
      return DecideMemory(raw, null, null);
    }
    if (currentP < _dropBelow && topConf < _inputBelow) {
      return const DecideMemory(InputState(), null, null);
    }
    return DecideMemory(prev, (intent: top, wins: wins), null);
  }

  return DecideMemory(raw, null, null);
}

/// User picked an intent from a chip or the palette.
DecideMemory force(ShiftIntent intent, String text) =>
    DecideMemory(CommittedState(intent, forced: true), null, text);

/// Tab on a ghost: promote without locking.
DecideMemory promote(DecideMemory mem) {
  final ui = mem.ui;
  if (ui is! GhostState) return mem;
  return DecideMemory(CommittedState(ui.intent), null, null);
}

ShiftIntent? activeIntent(UiState ui) => switch (ui) {
  CommittedState(:final intent) => intent,
  GhostState(:final intent) => intent,
  _ => null,
};
