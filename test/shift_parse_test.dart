import 'package:budget/screens/brain/shift/parse/calc.dart';
import 'package:budget/screens/brain/shift/parse/cards.dart';
import 'package:budget/screens/brain/shift/parse/color.dart';
import 'package:budget/screens/brain/shift/parse/convert.dart';
import 'package:budget/screens/brain/shift/parse/random.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ref = DateTime(2026, 10, 8, 9); // Thu

  test('calc evaluates natural arithmetic', () {
    expect(parseCalc('18% of 3450').result, 621);
    expect(parseCalc('1200 / 3').result, 400);
    expect(parseCalc('15% off 80').result, 68);
    expect(parseCalc('not a sum').result, isNull);
  });

  test('convert handles length and temperature', () {
    final miles = parseConvert('5 miles in km');
    expect(miles.from, 'mi');
    expect(miles.to, 'km');
    expect(miles.result, closeTo(8.0467, 0.001));
    final temp = parseConvert('72f to c');
    expect(temp.result, closeTo(22.22, 0.01));
  });

  test('split divides a total between people', () {
    final d = parseSplit('split 2400 between 3');
    expect(d.total, 2400);
    expect(d.people, 3);
    expect(summarySplit(d), '₹2,400 ÷ 3 = ₹800 each');
  });

  test('color reads hex, named and references', () {
    expect(parseColor('#ff6b35').hex, '#ff6b35');
    expect(parseColor('minecraft diamond').hex, '#4aedd9');
    expect(parseColor('tiffany blue').hex, '#0abab5');
  });

  test('expense pulls amount and item', () {
    final d = parseExpense('spent 450 on uber');
    expect(d.amount, 450);
    expect(d.item, 'Uber');
  });

  test('todo splits a list', () {
    final d = parseTodo('buy milk, eggs, bread and coffee');
    expect(d.items, ['Milk', 'Eggs', 'Bread', 'Coffee']);
    expect(d.verb, 'buy');
  });

  test('event extracts title, people and when', () {
    final d = parseEvent('dinner with priya friday 8pm', ref: ref);
    expect(d.title, 'Dinner');
    expect(d.people, ['Priya']);
    expect(d.date, DateTime(2026, 10, 9, 20));
    expect(d.hasTime, isTrue);
  });

  test('countdown resolves a holiday', () {
    final d = parseCountdown('days until christmas', ref: ref);
    expect(d.title, 'Christmas');
    expect(d.date, DateTime(2026, 12, 25));
    expect(d.days! > 0, isTrue);
  });

  test('timer sums a duration', () {
    final d = parseTimer('25 min focus');
    expect(d.seconds, 1500);
    expect(d.label, 'Focus');
  });

  test('random reads dice notation', () {
    final d = parseRandom('roll 2d6');
    expect(d.kind, RandomKind.dice);
    expect(d.count, 2);
    expect(d.sides, 6);
  });

  test('goal reads progress', () {
    final d = parseGoal('read 12 books this year, 4 done');
    expect(d.target, 12);
    expect(d.current, 4);
    expect(d.unit, 'books');
  });

  test('contact splits name, phone and email', () {
    final d = parseContact('rahul 98200 12345 rahul@mail.com');
    expect(d.email, 'rahul@mail.com');
    expect(d.phone, '98200 12345');
    expect(d.name, 'Rahul');
  });

  test('link reads url and note', () {
    final d = parseLink('vercel.com/blog check later');
    expect(d.url, 'https://vercel.com/blog');
    expect(d.domain, 'vercel.com');
    expect(d.note, 'Check later');
  });

  test('poll reads options', () {
    final d = parsePoll('pizza or burgers for friday?');
    expect(d.options, ['Pizza', 'Burgers']);
    expect(d.title.toLowerCase(), contains('friday'));
  });
}
