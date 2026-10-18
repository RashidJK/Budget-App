import 'package:budget/screens/brain/shift/parse/timezone.dart';
import 'package:flutter_test/flutter_test.dart';

/// The timezone card now resolves zones through the IANA database, so a
/// conversion is DST-aware rather than pinned to a standard-time offset. The
/// telling case is a zone that observes DST (US Pacific) against one that
/// doesn't (India): the same "3pm PT" lands an hour apart in summer vs winter.
/// The old fixed-offset parser gave the same answer for both.
void main() {
  test('3pm PT → IST shifts by an hour between summer and winter (DST)', () {
    final summer = parseTimezone('3pm pst in ist', DateTime(2025, 7, 15, 12));
    final winter = parseTimezone('3pm pst in ist', DateTime(2025, 1, 15, 12));

    // PDT (UTC−7) in July, PST (UTC−8) in January → IST (UTC+5:30) differs 1h.
    expect(formatIn(summer.to!, summer.instant), '3:30 AM');
    expect(formatIn(winter.to!, winter.instant), '4:30 AM');
  });

  test('the source zone reads back the time that was typed', () {
    final summer = parseTimezone('3pm pst in ist', DateTime(2025, 7, 15, 12));
    expect(formatIn(summer.from, summer.instant), '3:00 PM');
    expect(summer.from.label, 'PT');
    expect(summer.to!.label, 'IST');
  });

  test(
    'India observes no DST — IST is identical summer and winter at noon',
    () {
      final summer = parseTimezone('noon ist', DateTime(2025, 7, 15, 12));
      final winter = parseTimezone('noon ist', DateTime(2025, 1, 15, 12));
      expect(formatIn(summer.from, summer.instant), '12:00 PM');
      expect(formatIn(winter.from, winter.instant), '12:00 PM');
    },
  );
}
