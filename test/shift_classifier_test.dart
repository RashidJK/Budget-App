import 'package:budget/screens/brain/shift/shift_classifier.dart';
import 'package:budget/screens/brain/shift/shift_decide.dart';
import 'package:budget/screens/brain/shift/shift_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifier picks the right intent', () {
    final cases = {
      'dinner with priya friday 8pm': ShiftIntent.event,
      'buy milk, eggs, bread and coffee': ShiftIntent.todo,
      'split 2400 between 3': ShiftIntent.split,
      '#ff6b35': ShiftIntent.color,
      '18% of 3450': ShiftIntent.calc,
      '5 miles in km': ShiftIntent.convert,
      'remind me to call mom tomorrow': ShiftIntent.reminder,
      'roll 2d6': ShiftIntent.random,
      'days until christmas': ShiftIntent.countdown,
      '3pm pst in ist': ShiftIntent.timezone,
      'flight to goa next weekend': ShiftIntent.travel,
      'meditate every morning': ShiftIntent.habit,
      'read 12 books this year, 4 done': ShiftIntent.goal,
      'pizza or burgers for friday?': ShiftIntent.poll,
      'rahul 98200 12345 rahul@mail.com': ShiftIntent.contact,
      'vercel.com/blog check later': ShiftIntent.link,
      '25 min focus': ShiftIntent.timer,
      'the city felt so quiet this morning': ShiftIntent.note,
    };
    cases.forEach((text, expected) {
      test('"$text" → ${expected.name}', () {
        expect(classify(text).intent.value, expected);
      });
    });
  });

  test('empty / tiny text is none', () {
    expect(classify('').intent.value, ShiftIntent.none);
    expect(classify('a').intent.value, ShiftIntent.none);
  });

  test('a confident intent commits through the state machine', () {
    final mem = decide(initialMemory, classify('#ff6b35'), '#ff6b35');
    expect(mem.ui, isA<CommittedState>());
    expect((mem.ui as CommittedState).intent, ShiftIntent.color);
  });

  test('forcing locks an intent until the text changes a lot', () {
    final f = force(ShiftIntent.timer, '25 min');
    expect(f.ui, isA<CommittedState>());
    expect((f.ui as CommittedState).forced, isTrue);
    expect(changedSubstantially('25 min', '25 mins'), isFalse);
    expect(changedSubstantially('25 min', 'call the plumber about the leak'), isTrue);
  });
}
