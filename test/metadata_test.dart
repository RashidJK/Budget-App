import 'package:budget/models/category_fields.dart';
import 'package:budget/models/expense.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers category-specific metadata (§18) and the capture-first / enrich-later
/// contract (§19): metadata is always optional and can be added after the fact.

Future<AppState> _freshState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await Storage.open());
}

void main() {
  group('field schemas (§18)', () {
    test('fuel exposes litres, price and odometer', () {
      final keys = CategoryFields.forCategory('fuel').map((f) => f.key);
      expect(keys, containsAll(['litres', 'pricePerLitre', 'odometer']));
    });

    test('a category with no schema returns no fields', () {
      expect(CategoryFields.forCategory('other'), isEmpty);
      expect(CategoryFields.has('other'), isFalse);
      expect(CategoryFields.has('fuel'), isTrue);
    });
  });

  group('metadata persistence', () {
    test('metadata round-trips through JSON', () {
      final expense = Expense(
        id: 'e1',
        title: 'Petrol',
        amount: 62000,
        categoryId: 'fuel',
        profileId: 'personal',
        date: DateTime(2026, 7, 20),
        updatedAt: DateTime(2026, 7, 20),
        metadata: const {'litres': 20.5, 'station': 'TotalEnergies'},
      );

      final restored = Expense.fromJson(expense.toJson());
      expect(restored.metadata['litres'], 20.5);
      expect(restored.metadata['station'], 'TotalEnergies');
      expect(restored.hasMetadata, isTrue);
    });

    test('an expense with no metadata reads back empty', () {
      final expense = Expense(
        id: 'e2',
        title: 'Lunch',
        amount: 5000,
        categoryId: 'eating_out',
        profileId: 'personal',
        date: DateTime(2026, 7, 20),
        updatedAt: DateTime(2026, 7, 20),
      );
      expect(Expense.fromJson(expense.toJson()).hasMetadata, isFalse);
    });
  });

  group('capture first, enrich later (§19)', () {
    test('an expense is saved without metadata, then enriched', () async {
      final state = await _freshState();

      // Captured with just an amount — no fuel details yet.
      await state.addExpense(
        title: 'Petrol',
        amount: 62000,
        categoryId: 'fuel',
        date: DateTime.now(),
      );
      final expense = state.expenses.single;
      expect(expense.hasMetadata, isFalse);

      // Enriched later.
      await state.updateExpense(
        expense.copyWith(metadata: {'litres': 20.0, 'odometer': 45000}),
      );
      final enriched = state.expenses.single;
      expect(enriched.metadata['litres'], 20.0);
      // The rest of the expense is unchanged.
      expect(enriched.amount, 62000);
      expect(enriched.title, 'Petrol');
    });

    test('metadata survives a reload', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final state = AppState(storage);
      await state.addExpense(
        title: 'Petrol',
        amount: 62000,
        categoryId: 'fuel',
        date: DateTime.now(),
        metadata: const {'litres': 18.5},
      );

      final reloaded = AppState(storage);
      expect(reloaded.expenses.single.metadata['litres'], 18.5);
    });
  });
}
