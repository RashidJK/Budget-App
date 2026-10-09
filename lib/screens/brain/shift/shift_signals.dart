// Signals: the extra typed questions the classifier answers alongside "which
// card" — is it urgent? recurring? a video call? a shopping list? — plus the
// hysteresis gating that keeps badges and header icons from blinking while you
// type. Ported from Shapeshift's jev/types + signals.ts.

/// One classified answer: the winning [value], its [confidence] and the full
/// probability spread.
class Answer<T> {
  const Answer(this.value, this.confidence, this.probabilities);
  final T value;
  final double confidence;
  final Map<T, double> probabilities;
}

const tones = ['neutral', 'positive', 'excited', 'stressed', 'reflective'];
const eventModes = ['in_person', 'video_call', 'phone_call', 'unspecified'];
const transports = ['flight', 'train', 'bus', 'car', 'unspecified'];
const tripTypes = ['work', 'leisure', 'unspecified'];
const expenseCategories = ['food', 'transport', 'shopping', 'bills', 'entertainment', 'health', 'other'];
const colorMoods = ['warm', 'cool', 'neutral', 'vivid', 'pastel', 'dark'];
const timerKinds = ['countdown', 'focus', 'break', 'stopwatch'];

/// The raw signal bundle the classifier emits for a line of text.
class Signals {
  const Signals({
    required this.isQuestion,
    required this.recurring,
    required this.urgencyScore,
    required this.tone,
    required this.eventMode,
    required this.transport,
    required this.tripType,
    required this.expenseCategory,
    required this.colorMood,
    required this.timerKind,
    required this.hasExplicitOptions,
    required this.isShoppingList,
  });

  final double isQuestion;
  final double recurring;
  final double urgencyScore;
  final Answer<String> tone;
  final Answer<String> eventMode;
  final Answer<String> transport;
  final Answer<String> tripType;
  final Answer<String> expenseCategory;
  final Answer<String> colorMood;
  final Answer<String> timerKind;
  final double hasExplicitOptions;
  final double isShoppingList;

  static Answer<String> _neutral(String v) => Answer(v, 1, {v: 1});

  factory Signals.neutral() => Signals(
    isQuestion: 0,
    recurring: 0,
    urgencyScore: 0,
    tone: _neutral('neutral'),
    eventMode: _neutral('unspecified'),
    transport: _neutral('unspecified'),
    tripType: _neutral('unspecified'),
    expenseCategory: _neutral('other'),
    colorMood: _neutral('neutral'),
    timerKind: _neutral('countdown'),
    hasExplicitOptions: 0,
    isShoppingList: 0,
  );
}

/// Gated signals — thresholded and hysteresis-smoothed, with "escape" values
/// (unspecified/other) collapsed to null. This is what cards actually read.
class GatedSignals {
  const GatedSignals({
    this.eventMode,
    this.transport,
    this.tripType,
    this.expenseCategory,
    this.colorMood,
    this.timerKind,
    this.tone,
    this.recurring = false,
    this.isQuestion = false,
    this.hasExplicitOptions = false,
    this.isShoppingList = false,
    this.urgency = 0,
    this.urgent = false,
  });

  final String? eventMode;
  final String? transport;
  final String? tripType;
  final String? expenseCategory;
  final String? colorMood;
  final String? timerKind;
  final String? tone;
  final bool recurring;
  final bool isQuestion;
  final bool hasExplicitOptions;
  final bool isShoppingList;
  final double urgency;
  final bool urgent;
}

const _choiceMin = 0.6;
const _choiceKeep = 0.5;
const _noulOn = 0.65;
const _noulOff = 0.45;
const _urgentOn = 1.2;
const _urgentOff = 1.0;

const _escapes = {'unspecified', 'other'};

String? _gateChoice(Answer<String> a, String? prev) {
  if (_escapes.contains(a.value)) return null;
  if (a.confidence >= _choiceMin) return a.value;
  if (prev == a.value && a.confidence >= _choiceKeep) return prev;
  return null;
}

bool _gateNoul(double p, bool prev) {
  if (p >= _noulOn) return true;
  if (p <= _noulOff) return false;
  return prev;
}

/// Read only the signals [used] by the committed intent, applying thresholds
/// and hysteresis against [prev] so nothing blinks while typing.
GatedSignals gateSignals(GatedSignals prev, Signals s, Set<String> used) {
  return GatedSignals(
    eventMode: used.contains('eventMode') ? _gateChoice(s.eventMode, prev.eventMode) : null,
    transport: used.contains('transport') ? _gateChoice(s.transport, prev.transport) : null,
    tripType: used.contains('tripType') ? _gateChoice(s.tripType, prev.tripType) : null,
    expenseCategory: used.contains('expenseCategory') ? _gateChoice(s.expenseCategory, prev.expenseCategory) : null,
    colorMood: used.contains('colorMood') ? _gateChoice(s.colorMood, prev.colorMood) : null,
    timerKind: used.contains('timerKind') ? _gateChoice(s.timerKind, prev.timerKind) : null,
    tone: used.contains('tone') ? _gateChoice(s.tone, prev.tone) : null,
    recurring: used.contains('recurring') && _gateNoul(s.recurring, prev.recurring),
    isQuestion: used.contains('isQuestion') && _gateNoul(s.isQuestion, prev.isQuestion),
    hasExplicitOptions: used.contains('hasExplicitOptions') && _gateNoul(s.hasExplicitOptions, prev.hasExplicitOptions),
    isShoppingList: used.contains('isShoppingList') && _gateNoul(s.isShoppingList, prev.isShoppingList),
    urgency: used.contains('urgency') ? s.urgencyScore : 0,
    urgent: used.contains('urgency') &&
        (prev.urgent ? s.urgencyScore > _urgentOff : s.urgencyScore > _urgentOn),
  );
}
