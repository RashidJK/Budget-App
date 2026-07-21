import 'package:budget/models/scenario.dart';
import 'package:budget/screens/planner/daily_habit.dart';
import 'package:budget/screens/planner/savings.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the planner screens the way a user does, to check the two claims
/// the engine tests can't make: that results actually recalculate as values
/// change, and that saving a scenario persists what was on screen.
Future<Widget> _host(Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();

  return ChangeNotifierProvider(
    create: (_) => AppState(storage),
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

/// The animated figures tween over ~420ms, so the widget tree shows an
/// in-between value until the animation lands. Settling first means
/// assertions read the final number rather than a frame of the count-up.
Future<void> _settle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 600));

/// Gives the test a viewport tall enough to lay out a whole planner page.
///
/// The screens are lists, so on a phone-sized surface anything below the fold
/// is never built and finders silently miss it. Assertions about results that
/// sit under the inputs need everything mounted at once.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('daily habit recalculates as the amount changes', (
    tester,
  ) async {
    await tester.pumpWidget(await _host(const DailyHabitScreen()));
    await _settle(tester);

    // Opens on the spec's example: TSh 5,000 every day.
    expect(find.text('TSh 1,825,000'), findsOneWidget);
    expect(find.text('TSh 150,000'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '2500');
    await _settle(tester);

    // Halving the amount halves every figure, with no save step in between.
    expect(find.text('TSh 912,500'), findsOneWidget);
    expect(find.text('TSh 75,000'), findsOneWidget);
  });

  testWidgets('switching to weekdays only lowers the weekly figure', (
    tester,
  ) async {
    await tester.pumpWidget(await _host(const DailyHabitScreen()));
    await _settle(tester);

    expect(find.text('TSh 35,000'), findsOneWidget);

    await tester.tap(find.text('Weekdays only'));
    await _settle(tester);

    // Five days at 5,000 rather than seven.
    expect(find.text('TSh 25,000'), findsOneWidget);
  });

  testWidgets('the insight sentence tracks the numbers', (tester) async {
    await tester.pumpWidget(await _host(const DailyHabitScreen()));
    await _settle(tester);

    expect(
      find.textContaining('TSh 1.8 million a year'),
      findsOneWidget,
    );
  });

  testWidgets('savings simulator reports the spec comparison', (
    tester,
  ) async {
    _useTallViewport(tester);
    await tester.pumpWidget(await _host(const SavingsScreen()));
    await _settle(tester);

    // 5,000/day against 2,500/day: 75,000 saved monthly, 50% of the total.
    expect(find.text('TSh 75,000'), findsWidgets);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('a pricier alternative is flagged rather than sold as a saving', (
    tester,
  ) async {
    _useTallViewport(tester);
    await tester.pumpWidget(await _host(const SavingsScreen()));
    await _settle(tester);

    // Make the "alternative" more expensive than the status quo.
    final amountFields = find.byType(TextField);
    await tester.enterText(amountFields.at(3), '9000');
    await _settle(tester);

    expect(find.text('Yearly extra'), findsOneWidget);
    expect(find.textContaining('actually costs'), findsOneWidget);
  });

  testWidgets('saving a scenario stores the figures on screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    final state = AppState(storage);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: DailyHabitScreen()),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Save'));
    await _settle(tester);

    await tester.enterText(find.byType(TextField).last, 'Lunch money');
    await tester.tap(find.text('Save').last);
    await _settle(tester);

    expect(state.scenarios, hasLength(1));

    final saved = state.scenarios.single;
    expect(saved.name, 'Lunch money');
    expect(saved.kind, ScenarioKind.dailyHabit);
    expect(saved.summaryYearly, 1825000);
    expect(saved.number('amount'), 5000);
  });

  testWidgets('a saved scenario reopens with its inputs restored', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    final state = AppState(storage);

    final saved = await state.saveScenario(
      name: 'Weekend treats',
      kind: ScenarioKind.dailyHabit,
      data: {
        'amount': 12000.0,
        'categoryId': 'eating_out',
        'frequency': 'weekendsOnly',
        'customDays': 15.0,
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(home: DailyHabitScreen(scenario: saved)),
      ),
    );
    await _settle(tester);

    // 12,000 on two days a week.
    expect(find.text('TSh 24,000'), findsOneWidget);
    // Reopening an existing scenario offers Update, not a second Save.
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });
}
