import 'package:budget/command/receipt_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

/// The OCR feature's brain is [ReceiptTextParser] — pure text → structured
/// receipt — so it's tested here against realistic receipt layouts. The ML Kit
/// recognizer that feeds it a string is a thin native wrapper with no logic.

const _parser = ReceiptTextParser();
final _now = DateTime(2026, 8, 15);

void main() {
  group('total extraction', () {
    test('prefers the amount on the TOTAL line over larger sub-amounts', () {
      const text = '''
SHOPPERS PLAZA
Milk            8,000
Bread           3,000
Chicken        18,000
Subtotal       29,000
TOTAL          35,000
CASH           40,000
''';
      final receipt = _parser.parse(text, now: _now);
      // 40,000 (cash tendered) is larger, but TOTAL is the real amount.
      expect(receipt!.total, 35000);
    });

    test('handles Swahili "JUMLA" as total', () {
      const text = '''
DUKA LA VITU
Sukari          5,000
JUMLA          12,500
''';
      expect(_parser.parse(text, now: _now)!.total, 12500);
    });

    test('falls back to the largest amount with no total keyword', () {
      const text = '''
KIOSK
Soda   2,000
Water  1,000
6,500
''';
      expect(_parser.parse(text, now: _now)!.total, 6500);
    });

    test('parses decimal amounts', () {
      const text = 'CAFE\nTotal 1,234.50';
      expect(_parser.parse(text, now: _now)!.total, closeTo(1234.50, 0.001));
    });
  });

  group('merchant extraction', () {
    test('takes the store name from the top', () {
      const text = '''
TOTALENERGIES MIKOCHENI
Tel: 0754 000 000
Total 80,000
''';
      final receipt = _parser.parse(text, now: _now)!;
      expect(receipt.merchant, 'Totalenergies Mikocheni');
    });

    test('skips a leading receipt/phone line', () {
      const text = '''
RECEIPT
0754123456
SHOPRITE
Total 40,000
''';
      expect(_parser.parse(text, now: _now)!.merchant, 'Shoprite');
    });
  });

  group('category guess', () {
    test('a fuel station reads as fuel', () {
      const text = 'TOTALENERGIES\nTotal 80,000';
      expect(_parser.parse(text, now: _now)!.categoryId, 'fuel');
    });

    test('a supermarket reads as groceries', () {
      const text = 'CITY SUPERMARKET\nTotal 55,000';
      expect(_parser.parse(text, now: _now)!.categoryId, 'groceries');
    });

    test('an unknown merchant leaves the category unset', () {
      const text = 'RANDOM SHOP\nTotal 5,000';
      expect(_parser.parse(text, now: _now)!.categoryId, isNull);
    });
  });

  group('date extraction', () {
    test('reads a dd/mm/yyyy date', () {
      const text = 'SHOP\n12/07/2026\nTotal 5,000';
      expect(_parser.parse(text, now: _now)!.date, DateTime(2026, 7, 12));
    });

    test('falls back to now when no date is present', () {
      const text = 'SHOP\nTotal 5,000';
      expect(_parser.parse(text, now: _now)!.date, _now);
    });
  });

  group('edge cases', () {
    test('empty or amount-less text yields no receipt', () {
      expect(_parser.parse('', now: _now), isNull);
      expect(_parser.parse('Thank you\nCome again', now: _now), isNull);
    });

    test('a scanned receipt lands as needs-review confidence', () {
      final receipt = _parser.parse('SHOP\nTotal 5,000', now: _now)!;
      expect(receipt.confidence, lessThan(0.75));
    });
  });
}
