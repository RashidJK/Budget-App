import 'package:budget/models/brain_item.dart';
import 'package:budget/screens/brain/brain_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A fixed "now" so relative dates are deterministic: Wed 2026-01-14.
  final now = DateTime(2026, 1, 14);

  test('a URL or bare domain becomes a link', () {
    expect(BrainParser.parse('https://flutter.dev').kind, BrainKind.link);
    expect(BrainParser.parse('www.google.com').kind, BrainKind.link);
    final bare = BrainParser.parse('docs.flutter.dev/gestures');
    expect(bare.kind, BrainKind.link);
    expect(bare.url, 'docs.flutter.dev/gestures');

    final inline = BrainParser.parse('see https://x.com later');
    expect(inline.kind, BrainKind.link);
    expect(inline.url, 'https://x.com');
  });

  test('task prefixes become tasks, stripped of the prefix', () {
    expect(BrainParser.parse('todo call the bank').kind, BrainKind.task);
    expect(BrainParser.parse('todo call the bank').text, 'call the bank');
    expect(BrainParser.parse('- buy milk').text, 'buy milk');
    expect(BrainParser.parse('remind me to pay rent').text, 'pay rent');
  });

  test('a due phrase on a task sets the date and leaves the text clean', () {
    final t = BrainParser.parse('todo call the bank tomorrow', now: now);
    expect(t.kind, BrainKind.task);
    expect(t.dueDate, DateTime(2026, 1, 15));
    expect(t.text, 'call the bank');

    // Next Friday from Wed 14th is the 16th; "by" is tidied away.
    final f = BrainParser.parse('todo file taxes by friday', now: now);
    expect(f.dueDate, DateTime(2026, 1, 16));
    expect(f.text, 'file taxes');
  });

  test('journal prefixes become journal entries', () {
    final j = BrainParser.parse('journal: shipped the second brain');
    expect(j.kind, BrainKind.journal);
    expect(j.text, 'shipped the second brain');
  });

  test('anything else is a note', () {
    expect(BrainParser.parse('App idea for a launcher').kind, BrainKind.note);
    // A plain sentence with a date word but no task cue stays a note.
    expect(BrainParser.parse('Great weather today').kind, BrainKind.note);
  });

  test('detect is the kind of a full parse', () {
    expect(BrainParser.detect('todo x'), BrainKind.task);
    expect(BrainParser.detect('https://a.co'), BrainKind.link);
    expect(BrainParser.detect('just thinking'), BrainKind.note);
  });
}
