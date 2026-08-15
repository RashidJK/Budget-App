import 'package:budget/screens/tracker/expense_list.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The enrich-later loop must be completable from history, not only right
/// after capture (spec §19): an expense that can still take category details
/// advertises it; one already enriched does not.

Future<(Widget, AppState)> _host() async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState(await Storage.open());
  final app = ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const ExpenseListScreen(),
    ),
  );
  return (app, state);
}

void main() {
  testWidgets('a detail-less fuel expense offers to be enriched', (
    tester,
  ) async {
    final (app, state) = await _host();
    await state.addExpense(
      title: 'Petrol',
      amount: 62000,
      categoryId: 'fuel',
      date: DateTime.now(),
    );

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('Add fuel details'), findsOneWidget);
  });

  testWidgets('an already-enriched expense does not nag', (tester) async {
    final (app, state) = await _host();
    await state.addExpense(
      title: 'Petrol',
      amount: 62000,
      categoryId: 'fuel',
      date: DateTime.now(),
      metadata: const {'litres': 20.0},
    );

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('Add fuel details'), findsNothing);
  });

  testWidgets('a category with no schema never shows the affordance', (
    tester,
  ) async {
    final (app, state) = await _host();
    await state.addExpense(
      title: 'Something',
      amount: 1000,
      categoryId: 'other', // no field schema
      date: DateTime.now(),
    );

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.textContaining('details'), findsNothing);
  });

  testWidgets('tapping the affordance opens the details editor', (
    tester,
  ) async {
    final (app, state) = await _host();
    await state.addExpense(
      title: 'Petrol',
      amount: 62000,
      categoryId: 'fuel',
      date: DateTime.now(),
    );

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add fuel details'));
    await tester.pumpAndSettle();

    // The metadata sheet is up, with fuel fields.
    expect(find.text('Fuel details'), findsOneWidget);
    expect(find.text('Litres'), findsOneWidget);
  });
}
