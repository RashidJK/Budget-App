import 'package:budget/screens/analytics/analytics_screen.dart';
import 'package:budget/screens/planner/planner_home.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The desktop tool screens lead with a branded header band (echoing the
/// dashboard) and drop their app-bar title; the phone keeps the app bar and
/// shows no band. These pin that switch on both.

void main() {
  Future<AppState> freshState() async {
    SharedPreferences.setMockInitialValues({});
    return AppState(await Storage.open());
  }

  Widget host(AppState state, Widget child) => ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );

  void sized(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('Planner header band', () {
    testWidgets('desktop shows the gradient band', (tester) async {
      sized(tester, const Size(1200, 2000));
      await tester.pumpWidget(
        host(await freshState(), const PlannerHomeScreen()),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Plan what something costs before you spend it.'),
        findsOneWidget,
      );
    });

    testWidgets('phone keeps the app-bar title and no band', (tester) async {
      sized(tester, const Size(400, 900));
      await tester.pumpWidget(
        host(await freshState(), const PlannerHomeScreen()),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Plan what something costs before you spend it.'),
        findsNothing,
      );
      expect(find.text('Planner'), findsOneWidget);
    });
  });

  group('Analytics header band', () {
    Future<AppState> stateWithSpend() async {
      final state = await freshState();
      await state.addExpense(
        title: 'Lunch',
        amount: 5000,
        categoryId: 'fuel',
        date: DateTime.now(),
      );
      return state;
    }

    testWidgets('desktop shows the gradient band once there is data', (
      tester,
    ) async {
      sized(tester, const Size(1200, 2000));
      await tester.pumpWidget(
        host(await stateWithSpend(), const AnalyticsScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Where your money actually went.'), findsOneWidget);
    });

    testWidgets('phone keeps the app-bar title and no band', (tester) async {
      sized(tester, const Size(400, 900));
      await tester.pumpWidget(
        host(await stateWithSpend(), const AnalyticsScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Where your money actually went.'), findsNothing);
      expect(find.text('Analytics'), findsOneWidget);
    });
  });
}
