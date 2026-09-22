import 'package:budget/screens/home_shell.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tapping "+" opens the capture prompt in place — it spans the full panel and
/// a "Close" ✕ appears in the quick-action row above it. The prompt wears a
/// repeating Siri-style stroke, so once it's open we pump fixed frames rather
/// than settling (which never ends).
void main() {
  testWidgets('the + opens a prompt that records an expense', (tester) async {
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

    // Press "+": the prompt and the "Close" button appear.
    await tester.tap(find.bySemanticsLabel('Add or capture'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);

    // Type an expense and submit it.
    await tester.enterText(find.byType(TextField), '5000 lunch');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // It was recorded, and the bar returned to its "+".
    expect(state.expenses, isNotEmpty);
    expect(find.bySemanticsLabel('Add or capture'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the Close button exits capture without recording', (
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

    await tester.tap(find.bySemanticsLabel('Add or capture'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), '5000 lunch');
    await tester.pump();

    // Tap the "Close" ✕ — nothing recorded, prompt closed.
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(state.expenses, isEmpty);
    expect(find.byType(TextField), findsNothing);
    expect(find.bySemanticsLabel('Add or capture'), findsOneWidget);
  });
}
