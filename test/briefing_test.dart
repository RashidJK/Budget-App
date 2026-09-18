import 'package:budget/screens/briefing.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The nav bar's ✨ opens a briefing tailored to the area you're in. These cover
/// that each [BriefingKind] renders its own heading and figures.
Future<AppState> _freshState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await Storage.open());
}

Future<void> _openBriefing(
  WidgetTester tester,
  AppState state,
  BriefingKind kind, {
  String? accountId,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    showBriefing(context, kind: kind, accountId: accountId),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('home briefing summarises money on hand', (tester) async {
    final state = await _freshState();
    await state.updateAccount(
      state.accounts.single.copyWith(openingBalance: 250000),
    );

    await _openBriefing(tester, state, BriefingKind.home);

    expect(find.textContaining('You hold'), findsOneWidget);
    expect(find.text('Balance'), findsOneWidget);
  });

  testWidgets('expenses briefing summarises this month', (tester) async {
    final state = await _freshState();
    await state.addExpense(
      title: 'Petrol',
      amount: 30000,
      categoryId: 'fuel',
      date: DateTime.now(),
    );

    await _openBriefing(tester, state, BriefingKind.expenses);

    expect(find.text('This month'), findsOneWidget); // heading
    expect(find.text('Entries'), findsOneWidget);
    expect(find.textContaining("You've logged"), findsOneWidget);
  });

  testWidgets('analytics briefing summarises the trend', (tester) async {
    final state = await _freshState();
    await state.addExpense(
      title: 'Rent',
      amount: 40000,
      categoryId: 'housing',
      date: DateTime.now(),
    );

    await _openBriefing(tester, state, BriefingKind.analytics);

    expect(find.text('Your trend'), findsOneWidget);
    expect(find.text('Projected'), findsOneWidget);
  });

  testWidgets('planner briefing looks ahead', (tester) async {
    final state = await _freshState();

    await _openBriefing(tester, state, BriefingKind.planner);

    expect(find.text('Looking ahead'), findsOneWidget);
    expect(find.text('Days left'), findsOneWidget);
  });

  testWidgets('account briefing summarises one account', (tester) async {
    final state = await _freshState();
    final account = state.accounts.single;
    await state.updateAccount(account.copyWith(openingBalance: 500000));

    await _openBriefing(
      tester,
      state,
      BriefingKind.account,
      accountId: account.id,
    );

    // Its own in/out figures, not the global money summary.
    expect(find.textContaining('holds'), findsOneWidget);
    expect(find.text('In'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
  });
}
