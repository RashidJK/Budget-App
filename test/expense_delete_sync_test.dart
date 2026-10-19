import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/sync/merge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deleting an expense must TOMBSTONE it, not drop it — otherwise the deletion
/// can't replicate (a vanished record can't tell the server it's gone) and the
/// expense reappears on other devices after a sync. These pin that contract.
Future<AppState> _freshState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await Storage.open());
}

Future<(AppState, Storage, String)> _stateWithOneExpense() async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  final state = AppState(storage);
  await state.addExpense(
    title: 'Lunch',
    amount: 5000,
    categoryId: 'fuel',
    date: DateTime.now(),
  );
  return (state, storage, state.expenses.single.id);
}

void main() {
  test('deleting an expense hides it but keeps a tombstone for sync', () async {
    final (state, storage, id) = await _stateWithOneExpense();

    await state.deleteExpense(id);

    // Gone from every view…
    expect(state.expenses.any((e) => e.id == id), isFalse);
    expect(state.scopedExpenses.any((e) => e.id == id), isFalse);
    expect(state.spentThisMonth, 0);

    // …but still on disk as a tombstone, so the next sync pushes the deletion.
    final stored = storage.readExpenses().firstWhere((m) => m['id'] == id);
    expect(stored['deletedAt'], isNotNull);
  });

  test('restoring a deleted expense brings it back once, live', () async {
    final (state, storage, id) = await _stateWithOneExpense();
    final original = state.expenses.single;

    await state.deleteExpense(id, discardAttachments: false);
    expect(state.expenses, isEmpty);

    await state.restoreExpense(original);

    // Exactly one live copy — no duplicate alongside the tombstone.
    expect(state.expenses.where((e) => e.id == id), hasLength(1));
    expect(state.expenses.single.isDeleted, isFalse);
    expect(state.spentThisMonth, 5000);
    // Still a single stored record for that id (the revived one).
    expect(storage.readExpenses().where((m) => m['id'] == id), hasLength(1));
  });

  test('a tombstoned expense drops out of totals and search', () async {
    final (state, _, id) = await _stateWithOneExpense();
    await state.deleteExpense(id);

    expect(state.expensesInMonth(DateTime.now()), isEmpty);
    expect(state.expenseCountForCategory('fuel'), 0);
  });

  test('deleting a missing id is a no-op', () async {
    final state = await _freshState();
    await state.deleteExpense('does-not-exist'); // must not throw
    expect(state.expenses, isEmpty);
  });
}
