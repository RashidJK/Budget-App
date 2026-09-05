import 'package:budget/screens/home_shell.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pressing "+" morphs the left island into an inline expense prompt in place,
/// and the right circle becomes a "back to the tab" button. Capture happens in
/// the bar itself — no modal.
void main() {
  testWidgets('the + morphs the island into a prompt that records', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await Storage.open());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(theme: AppTheme.light(), home: const HomeShell()),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(state.expenses, isEmpty);
    expect(find.byType(TextField), findsNothing);

    // Press "+": the prompt appears and the right circle offers the way back.
    await tester.tap(find.bySemanticsLabel('Add or capture'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.bySemanticsLabel('Back to Home'), findsOneWidget);

    // Type an expense and submit it.
    await tester.enterText(find.byType(TextField), '5000 lunch');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // It was recorded, and the bar returned to its "+".
    expect(state.expenses, isNotEmpty);
    expect(find.bySemanticsLabel('Add or capture'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the back circle exits capture without recording', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await Storage.open());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(theme: AppTheme.light(), home: const HomeShell()),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    await tester.tap(find.bySemanticsLabel('Add or capture'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5000 lunch');
    await tester.pump();

    // Tap the "back to Home" circle — nothing recorded, prompt closed.
    await tester.tap(find.bySemanticsLabel('Back to Home'));
    await tester.pumpAndSettle();

    expect(state.expenses, isEmpty);
    expect(find.byType(TextField), findsNothing);
    expect(find.bySemanticsLabel('Add or capture'), findsOneWidget);
  });
}
