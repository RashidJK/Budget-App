import 'package:budget/screens/brain/shift/shift_when.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A fixed Thursday so weekday/relative math is deterministic.
  final ref = DateTime(2026, 10, 8, 9); // Thu 9:00 AM

  test('no date-like text returns null', () {
    expect(findWhen('split 2400 between 3', ref: ref), isNull);
    expect(findWhen('buy milk and eggs', ref: ref), isNull);
  });

  test('relative days', () {
    expect(findWhen('tomorrow', ref: ref)!.start, DateTime(2026, 10, 9));
    expect(findWhen('today', ref: ref)!.start, DateTime(2026, 10, 8));
    expect(findWhen('next week', ref: ref)!.start, DateTime(2026, 10, 15));
  });

  test('weekday rolls forward to the next occurrence', () {
    expect(findWhen('friday', ref: ref)!.start, DateTime(2026, 10, 9));
    expect(findWhen('next friday', ref: ref)!.start, DateTime(2026, 10, 16));
    expect(findWhen('monday', ref: ref)!.start, DateTime(2026, 10, 12));
  });

  test('day + time combine, hasTime set', () {
    final hit = findWhen('friday 8pm', ref: ref)!;
    expect(hit.start, DateTime(2026, 10, 9, 20));
    expect(hit.hasTime, isTrue);
  });

  test('bare time today, forward-dated once past', () {
    expect(findWhen('5pm', ref: ref)!.start, DateTime(2026, 10, 8, 17));
    final late = DateTime(2026, 10, 8, 20);
    expect(findWhen('5pm', ref: late)!.start, DateTime(2026, 10, 9, 17));
    expect(findWhen('noon', ref: ref)!.start, DateTime(2026, 10, 8, 12));
  });

  test('month + day, forward year', () {
    expect(findWhen('dec 12', ref: ref)!.start, DateTime(2026, 12, 12));
    expect(findWhen('12 december', ref: ref)!.start, DateTime(2026, 12, 12));
    // Already past this year → next year.
    expect(findWhen('jan 5', ref: ref)!.start, DateTime(2027, 1, 5));
  });

  test('in N days / N days from now', () {
    expect(findWhen('in 3 days', ref: ref)!.start, DateTime(2026, 10, 11));
    expect(findWhen('in 2 weeks', ref: ref)!.start, DateTime(2026, 10, 22));
    expect(findWhen('5 days from now', ref: ref)!.start, DateTime(2026, 10, 13));
  });

  test('date range keeps an end', () {
    final hit = findWhen('12-15 oct', ref: ref)!;
    expect(hit.start, DateTime(2026, 10, 12));
    expect(hit.end, DateTime(2026, 10, 15));
  });

  test('weekend spans Sat-Sun', () {
    final hit = findWhen('this weekend', ref: ref)!;
    expect(hit.start, DateTime(2026, 10, 10)); // Sat
    expect(hit.end, DateTime(2026, 10, 11)); // Sun
  });

  test('stripWhen removes the matched date text', () {
    final hit = findWhen('call mom friday 8pm', ref: ref)!;
    expect(stripWhen('call mom friday 8pm', hit), 'call mom');
  });
}
