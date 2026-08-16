import 'package:budget/models/activity.dart';
import 'package:budget/screens/tracker/expense_list.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-expense activities (income/transfer/loan) used to be swipe-delete-only;
/// this covers the new tap-to-edit flow through ActivityEditSheet.
Future<AppState> _freshState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await Storage.open());
}

Future<void> _pump(WidgetTester tester, AppState state, Activity activity) {
  return tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(children: [ActivityRow(activity: activity)]),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tapping an activity opens the editor and saves changes', (
    tester,
  ) async {
    final state = await _freshState();
    final now = DateTime.now();
    await state.addActivity(
      Activity(
        id: 'a1',
        type: ActivityType.income,
        amount: 100000,
        date: now,
        updatedAt: now,
        description: 'Salary',
      ),
    );
    final activity = state.activities.single;

    await _pump(tester, state, activity);

    await tester.tap(find.text('Salary'));
    await tester.pumpAndSettle();
    expect(find.text('Save changes'), findsOneWidget);

    // Amount is the first field in the sheet; change it and save.
    await tester.enterText(find.byType(TextField).first, '150000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(state.activities.single.amount, 150000);
    // The edit must not turn it into an expense or duplicate the record.
    expect(state.activities, hasLength(1));
    expect(state.expenses, isEmpty);
  });
}
