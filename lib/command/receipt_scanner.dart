import '../models/activity.dart';
import 'command_parser.dart';

/// One line item extracted from a receipt (spec §15).
class ScannedItem {
  const ScannedItem({required this.label, required this.amount});
  final String label;
  final double amount;

  Map<String, dynamic> toJson() => {'label': label, 'amount': amount};
}

/// The structured result of scanning a receipt (spec §14).
class ScannedReceipt {
  const ScannedReceipt({
    required this.total,
    required this.date,
    this.merchant,
    this.categoryId,
    this.items = const [],
    this.confidence = 0.6,
  });

  final double total;
  final DateTime date;
  final String? merchant;
  final String? categoryId;
  final List<ScannedItem> items;
  final double confidence;

  /// Converts the scan into a not-yet-saved activity the confirmation card can
  /// show and the user can accept, edit or enrich later (spec §19).
  ParsedActivity toParsedActivity({required String defaultProfileId}) {
    return ParsedActivity(
      type: ActivityType.expense,
      amount: total,
      date: date,
      description: merchant ?? 'Receipt',
      categoryId: categoryId,
      profileId: defaultProfileId,
      merchant: merchant,
    );
  }
}

/// Extracts structured data from a receipt image.
///
/// Deliberately an interface (spec §39, Phase 4): the command bar depends on
/// this abstraction, never on a specific OCR provider.
abstract class ReceiptScanner {
  Future<ScannedReceipt?> scan(String imagePath);
}

/// The scanner the command bar uses when none is injected.
///
/// Production sets this to the on-device ML Kit scanner in `main()`; tests and
/// non-mobile builds leave it as the mock, so nothing depends on the native
/// plugin being present.
ReceiptScanner defaultReceiptScanner = const MockReceiptScanner();

/// Turns the raw text ML Kit reads off a receipt into a [ScannedReceipt].
///
/// This is the whole brain of the scan feature, and it is **pure** — no ML Kit,
/// no image — so every heuristic below is unit-tested against real receipt
/// layouts. The native recognizer just hands it a string.
class ReceiptTextParser {
  const ReceiptTextParser();

  /// Amounts on a receipt: "12,000", "12,000.00", "1200.50", "TZS 3,500".
  static final RegExp _amount = RegExp(
    r'(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)',
  );

  static final RegExp _date = RegExp(
    r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b',
  );

  /// Words that mark the line holding the grand total, most reliable first.
  /// Includes Swahili ("jumla" = total, "kiasi" = amount) for local receipts.
  static const _totalKeywords = [
    'grand total',
    'total',
    'jumla',
    'amount due',
    'kiasi',
    'net',
  ];

  ScannedReceipt? parse(String rawText, {DateTime? now}) {
    final lines = rawText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    final total = _extractTotal(lines);
    if (total == null || total <= 0) return null;

    final merchant = _extractMerchant(lines);
    final date = _extractDate(lines) ?? now ?? DateTime.now();

    return ScannedReceipt(
      total: total,
      date: date,
      merchant: merchant,
      categoryId: _guessCategory(rawText.toLowerCase()),
      // Middling by design — a scanned expense lands as "needs review" until
      // the user confirms (spec §20).
      confidence: 0.55,
    );
  }

  /// Prefers the amount on a line labelled "total"/"jumla"; otherwise the
  /// largest monetary value on the receipt, which is almost always the total.
  double? _extractTotal(List<String> lines) {
    for (final keyword in _totalKeywords) {
      // Match on word boundaries, so "net" doesn't fire inside "internet" and
      // "total" doesn't fire inside "subtotal" / "total items".
      final pattern = RegExp('\\b${RegExp.escape(keyword)}\\b');
      for (final line in lines) {
        final lower = line.toLowerCase();
        if (!pattern.hasMatch(lower)) continue;
        final onLine = _amountsIn(line);
        if (onLine.isNotEmpty) return onLine.reduce((a, b) => a > b ? a : b);
      }
    }

    final all = lines.expand(_amountsIn).toList();
    if (all.isEmpty) return null;
    return all.reduce((a, b) => a > b ? a : b);
  }

  List<double> _amountsIn(String line) {
    return _amount
        .allMatches(line)
        .map((m) => double.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0)
        .where((value) => value > 0)
        .toList();
  }

  /// The merchant is the first "name-like" line near the top — alphabetic,
  /// not a date, phone number or amount.
  String? _extractMerchant(List<String> lines) {
    for (final line in lines.take(5)) {
      final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '');
      final digits = line.replaceAll(RegExp(r'\D'), '');
      if (letters.length < 3) continue;
      if (digits.length > letters.length) continue; // mostly numbers
      if (_date.hasMatch(line)) continue;
      if (RegExp(r'receipt|invoice|tel|phone|p\.?o\.?box', caseSensitive: false)
          .hasMatch(line)) {
        continue;
      }
      return _tidy(line);
    }
    return null;
  }

  DateTime? _extractDate(List<String> lines) {
    for (final line in lines) {
      final match = _date.firstMatch(line);
      if (match == null) continue;
      var day = int.parse(match.group(1)!);
      var month = int.parse(match.group(2)!);
      var year = int.parse(match.group(3)!);
      if (year < 100) year += 2000;
      // Tolerate US-style m/d ordering when day is clearly a month.
      if (month > 12 && day <= 12) {
        final swap = day;
        day = month;
        month = swap;
      }
      if (month < 1 || month > 12 || day < 1 || day > 31) continue;
      // DateTime silently rolls impossible dates over (31 Feb → 3 Mar), which
      // would file the expense in the wrong month; reject those and fall back.
      final candidate = DateTime(year, month, day);
      if (candidate.day != day || candidate.month != month) continue;
      return candidate;
    }
    return null;
  }

  /// Best-effort category from merchant/keyword hints; returns a seed category
  /// id (falls back to "Other" if the user deleted it).
  static const _categoryHints = <String, List<String>>{
    // Note: no bare "total" — it would match the TOTAL line on every receipt.
    'fuel': ['totalenergies', 'oryx', 'puma energy', 'petrol', 'fuel', 'gapco', 'lake oil'],
    'groceries': ['supermarket', 'shoppers', 'shoprite', 'market', 'mini mart', 'grocer'],
    'eating_out': ['restaurant', 'cafe', 'coffee', 'hotel', 'grill', 'pizza', 'kitchen', 'bar &'],
    'bills': ['luku', 'tanesco', 'electric', 'water', 'internet', 'tigo', 'vodacom', 'airtel', 'halotel'],
    'family': ['pharmacy', 'chemist', 'hospital', 'clinic'],
  };

  String? _guessCategory(String lowerText) {
    for (final entry in _categoryHints.entries) {
      for (final hint in entry.value) {
        if (lowerText.contains(hint)) return entry.key;
      }
    }
    return null;
  }

  String _tidy(String line) {
    final cleaned = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Title-case an ALL-CAPS store name so it reads naturally.
    if (cleaned == cleaned.toUpperCase()) {
      return cleaned
          .split(' ')
          .map(
            (word) => word.isEmpty
                ? word
                : word[0] + word.substring(1).toLowerCase(),
          )
          .join(' ');
    }
    return cleaned;
  }
}

/// A stand-in that returns a plausible receipt without real OCR, so the whole
/// capture → confirm → save flow is buildable and demonstrable now.
///
/// It does *not* read the image — a production build replaces this with a real
/// [ReceiptScanner]. The confidence is deliberately middling so a scanned
/// expense lands as "needs review" until the user confirms it (spec §20).
class MockReceiptScanner implements ReceiptScanner {
  const MockReceiptScanner({this.now});

  /// Test seam for a deterministic date.
  final DateTime Function()? now;

  @override
  Future<ScannedReceipt?> scan(String imagePath) async {
    // Simulate a short extraction delay so the UI's progress state is real.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final date = now?.call() ?? DateTime.now();
    return ScannedReceipt(
      total: 47500,
      date: date,
      merchant: 'Shoppers Plaza',
      categoryId: 'groceries',
      confidence: 0.6,
      items: const [
        ScannedItem(label: 'Milk', amount: 8000),
        ScannedItem(label: 'Bread', amount: 3000),
        ScannedItem(label: 'Chicken', amount: 18000),
        ScannedItem(label: 'Other', amount: 18500),
      ],
    );
  }
}
