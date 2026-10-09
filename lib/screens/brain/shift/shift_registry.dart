import 'parse/calc.dart';
import 'parse/cards.dart';
import 'parse/color.dart';
import 'parse/convert.dart';
import 'parse/random.dart';
import 'parse/timezone.dart';
import 'shift_intent.dart';

// The extension point: maps each intent to its parser, completeness score,
// one-line summary and the signals it reads. The card widgets live in
// cards/shift_cards.dart; everything else about a card type is here.

/// Parse [text] for [intent] into that card's typed data (dynamic — each card
/// knows its own type). [ref] pins "now" for date cards; [colorMood] feeds the
/// colour parser's mood fallback.
dynamic shiftParse(ShiftIntent intent, String text, {DateTime? ref, String? colorMood}) {
  return switch (intent) {
    ShiftIntent.event => parseEvent(text, ref: ref),
    ShiftIntent.reminder => parseReminder(text, ref: ref),
    ShiftIntent.todo => parseTodo(text),
    ShiftIntent.timer => parseTimer(text),
    ShiftIntent.habit => parseHabit(text),
    ShiftIntent.color => parseColor(text, colorMood),
    ShiftIntent.split => parseSplit(text),
    ShiftIntent.expense => parseExpense(text),
    ShiftIntent.convert => parseConvert(text),
    ShiftIntent.calc => parseCalc(text),
    ShiftIntent.travel => parseTravel(text, ref: ref),
    ShiftIntent.poll => parsePoll(text),
    ShiftIntent.contact => parseContact(text),
    ShiftIntent.link => parseLink(text),
    ShiftIntent.countdown => parseCountdown(text, ref: ref),
    ShiftIntent.timezone => parseTimezone(text, ref),
    ShiftIntent.random => parseRandom(text),
    ShiftIntent.goal => parseGoal(text),
    ShiftIntent.note => parseNote(text),
    ShiftIntent.none => null,
  };
}

/// 0..1, how filled-in the parsed card is.
double shiftComplete(ShiftIntent intent, dynamic d) {
  return switch (intent) {
    ShiftIntent.event => completeEvent(d as EventData),
    ShiftIntent.reminder => completeReminder(d as ReminderData),
    ShiftIntent.todo => completeTodo(d as TodoData),
    ShiftIntent.timer => completeTimer(d as TimerData),
    ShiftIntent.habit => completeHabit(d as HabitData),
    ShiftIntent.color => completeColor(d as ColorData),
    ShiftIntent.split => completeSplit(d as SplitData),
    ShiftIntent.expense => completeExpense(d as ExpenseData),
    ShiftIntent.convert => completeConvert(d as ConvertData),
    ShiftIntent.calc => completeCalc(d as CalcData),
    ShiftIntent.travel => completeTravel(d as TravelData),
    ShiftIntent.poll => completePoll(d as PollData),
    ShiftIntent.contact => completeContact(d as ContactData),
    ShiftIntent.link => completeLink(d as LinkData),
    ShiftIntent.countdown => completeCountdown(d as CountdownData),
    ShiftIntent.timezone => completeTimezone(d as TimezoneData),
    ShiftIntent.random => completeRandom(d as RandomData),
    ShiftIntent.goal => completeGoal(d as GoalData),
    ShiftIntent.note => completeNote(d as NoteData),
    ShiftIntent.none => 0,
  };
}

/// One line describing the parsed card — used for the saved Brain item and the
/// command palette.
String shiftSummary(ShiftIntent intent, dynamic d) {
  return switch (intent) {
    ShiftIntent.event => summaryEvent(d as EventData),
    ShiftIntent.reminder => summaryReminder(d as ReminderData),
    ShiftIntent.todo => summaryTodo(d as TodoData),
    ShiftIntent.timer => summaryTimer(d as TimerData),
    ShiftIntent.habit => summaryHabit(d as HabitData),
    ShiftIntent.color => summaryColor(d as ColorData),
    ShiftIntent.split => summarySplit(d as SplitData),
    ShiftIntent.expense => summaryExpense(d as ExpenseData),
    ShiftIntent.convert => summaryConvert(d as ConvertData),
    ShiftIntent.calc => summaryCalc(d as CalcData),
    ShiftIntent.travel => summaryTravel(d as TravelData),
    ShiftIntent.poll => summaryPoll(d as PollData),
    ShiftIntent.contact => summaryContact(d as ContactData),
    ShiftIntent.link => summaryLink(d as LinkData),
    ShiftIntent.countdown => summaryCountdown(d as CountdownData),
    ShiftIntent.timezone => summaryTimezone(d as TimezoneData),
    ShiftIntent.random => summaryRandom(d as RandomData),
    ShiftIntent.goal => summaryGoal(d as GoalData),
    ShiftIntent.note => summaryNote(d as NoteData),
    ShiftIntent.none => '',
  };
}

/// The signals a given intent's card actually reads (everything else is
/// ignored by the gater, so it can't blink the card).
Set<String> shiftUsedSignals(ShiftIntent intent) {
  return switch (intent) {
    ShiftIntent.event => {'eventMode', 'recurring'},
    ShiftIntent.reminder => {'urgency', 'recurring'},
    ShiftIntent.todo => {'isShoppingList', 'urgency'},
    ShiftIntent.timer => {'timerKind'},
    ShiftIntent.expense => {'expenseCategory'},
    ShiftIntent.travel => {'transport', 'tripType'},
    ShiftIntent.poll => {'hasExplicitOptions'},
    ShiftIntent.color => {'colorMood'},
    ShiftIntent.note => {'tone', 'isQuestion'},
    _ => const {},
  };
}
