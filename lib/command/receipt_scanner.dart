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
/// this abstraction, never on a specific OCR provider. Swapping in a real
/// on-device or cloud OCR later is one implementation change with no UI churn.
abstract class ReceiptScanner {
  Future<ScannedReceipt?> scan(String imagePath);
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
