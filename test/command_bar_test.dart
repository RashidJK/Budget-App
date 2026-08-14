import 'package:budget/command/command_bar.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the command bar the way a user does — open it, type, read the live
/// preview, commit — to check the wiring the parser tests can't: that a
/// capture actually reaches state, and that a query never does.

Future<(Widget, AppState)> _host() async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState(await Storage.open());
  final app = ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => CommandBar.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  return (app, state);
}

Future<void> _open(WidgetTester tester, String text) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('typing an expense shows a confirmation and commits', (
    tester,
  ) async {
    final (app, state) = await _host();
    await tester.pumpWidget(app);

    await _open(tester, 'I spent 5000 on lunch');

    // Live preview shows the amount and an "Add expense" action.
    expect(find.textContaining('5,000'), findsWidgets);
    expect(find.text('Add expense'), findsOneWidget);

    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();

    // Success state with Undo, and the expense reached state.
    expect(find.text('Recorded'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(state.expenses, hasLength(1));
    expect(state.expenses.single.amount, 5000);
  });

  testWidgets('income is captured to the activity ledger', (tester) async {
    final (app, state) = await _host();
    await tester.pumpWidget(app);

    await _open(tester, 'Received 500000 salary');
    expect(find.text('Add income'), findsOneWidget);

    await tester.tap(find.text('Add income'));
    await tester.pumpAndSettle();

    expect(state.activities, hasLength(1));
    expect(state.expenses, isEmpty);
  });

  testWidgets('Undo reverses a capture', (tester) async {
    final (app, state) = await _host();
    await tester.pumpWidget(app);

    await _open(tester, '5000 lunch');
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    expect(state.expenses, hasLength(1));

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(state.expenses, isEmpty);
  });

  testWidgets('a history question shows an answer and records nothing', (
    tester,
  ) async {
    final (app, state) = await _host();
    await tester.pumpWidget(app);

    // Seed an expense so the query has something to total.
    await state.addExpense(
      title: 'Petrol',
      amount: 30000,
      categoryId: 'fuel',
      date: DateTime.now(),
    );

    await _open(tester, 'how much did I spend on fuel this month?');

    // The answer card appears; no "Add" action, and nothing new is written.
    expect(find.textContaining('Fuel'), findsWidgets);
    expect(find.text('Add expense'), findsNothing);
    expect(state.expenses, hasLength(1));
    expect(state.activities, isEmpty);
  });

  testWidgets('a fuel capture offers to enrich, and the details save', (
    tester,
  ) async {
    final (app, state) = await _host();
    await tester.pumpWidget(app);

    await _open(tester, 'Paid 80000 for fuel');
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();

    // Capture-first, enrich-later: the success card nudges for fuel details.
    expect(find.text('Add fuel details'), findsOneWidget);
    expect(state.expenses.single.hasMetadata, isFalse);

    await tester.tap(find.text('Add fuel details'));
    await tester.pumpAndSettle();

    // The metadata form appears with fuel fields.
    expect(find.text('Fuel details'), findsOneWidget);
    expect(find.text('Litres'), findsOneWidget);

    // Target the field under the "Litres" label specifically.
    final litresField = find.descendant(
      of: find.ancestor(
        of: find.text('Litres'),
        matching: find.byType(Column),
      ).first,
      matching: find.byType(TextField),
    );
    await tester.enterText(litresField, '20');
    await tester.ensureVisible(find.text('Save details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save details'));
    await tester.pumpAndSettle();

    expect(state.expenses.single.metadata['litres'], 20.0);
  });

  testWidgets('an ambiguous command offers one-tap clarification', (
    tester,
  ) async {
    final (app, state) = await _host();
    await tester.pumpWidget(app);

    // Create a person named John with no balance so it stays ambiguous.
    await state.resolvePerson('John');

    await _open(tester, 'I got 100000 from John');

    expect(find.text('What was this?'), findsOneWidget);
    // Chips for the candidate types.
    expect(find.text('Income'), findsOneWidget);
  });
}
