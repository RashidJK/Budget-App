import 'package:budget/models/activity.dart';
import 'package:budget/screens/tracker/dashboard.dart';
import 'package:budget/state/app_state.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers the home "snapshot" carousel — the sideways-scrolling insight cards
/// under the hero — and the derived metrics that feed the newer cards.
Future<AppState> _freshState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await Storage.open());
}

/// The dashboard is a tall vertical list with a horizontal card row near the
/// top; a wide, tall viewport lays enough of both axes out that finders can see
/// the cards rather than silently missing ones below or right of the fold.
void _useLargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpDashboard(WidgetTester tester, AppState state) async {
  _useLargeViewport(tester);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const DashboardScreen(),
      ),
    ),
  );
  // The hero figure counts up; settle so the tree is stable before asserting.
  await tester.pumpAndSettle(const Duration(milliseconds: 600));
}

void main() {
  group('derived snapshot metrics', () {
    test('spentToday counts only expenses dated today', () async {
      final state = await _freshState();
      final now = DateTime.now();

      await state.addExpense(
        title: 'Lunch',
        amount: 5000,
        categoryId: 'eating_out',
        date: now,
      );
      await state.addExpense(
        title: 'Yesterday petrol',
        amount: 8000,
        categoryId: 'fuel',
        date: now.subtract(const Duration(days: 1)),
      );

      expect(state.spentToday, 5000);
    });

    test('expenseCountThisMonth ignores other months', () async {
      final state = await _freshState();
      final now = DateTime.now();

      await state.addExpense(
        title: 'A',
        amount: 1000,
        categoryId: 'other',
        date: now,
      );
      await state.addExpense(
        title: 'B',
        amount: 2000,
        categoryId: 'other',
        date: now,
      );
      await state.addExpense(
        title: 'Last month',
        amount: 9000,
        categoryId: 'other',
        date: DateTime(now.year, now.month - 1, 15),
      );

      expect(state.expenseCountThisMonth, 2);
    });

    test('projected pace is daily average across the whole month', () async {
      final state = await _freshState();
      final now = DateTime.now();
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

      await state.addExpense(
        title: 'Groceries',
        amount: 12000,
        categoryId: 'groceries',
        date: now,
      );

      expect(
        state.projectedThisMonth,
        closeTo(state.dailyAverageThisMonth * daysInMonth, 0.001),
      );
      // The projection can only add to what's already spent.
      expect(
        state.projectedThisMonth,
        greaterThanOrEqualTo(state.spentThisMonth),
      );
    });
  });

  group('snapshot row', () {
    testWidgets('renders the always-on insight cards once there is spend', (
      tester,
    ) async {
      final state = await _freshState();
      final now = DateTime.now();
      await state.addExpense(
        title: 'Lunch',
        amount: 5000,
        categoryId: 'eating_out',
        date: now,
      );
      await state.addExpense(
        title: 'Petrol',
        amount: 30000,
        categoryId: 'fuel',
        date: now,
      );

      await _pumpDashboard(tester, state);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Daily average'), findsOneWidget);
      expect(find.text('Projected'), findsOneWidget);
      expect(find.text('Entries'), findsOneWidget);
      expect(find.text('Biggest'), findsOneWidget);
      // Two expenses this month.
      expect(find.text('2'), findsOneWidget);
      // Fuel is the larger category, so it leads the "Top" card.
      expect(find.text('Top: Fuel'), findsOneWidget);
    });

    testWidgets('conditional cards stay hidden with nothing to show', (
      tester,
    ) async {
      final state = await _freshState();
      await state.addExpense(
        title: 'Lunch',
        amount: 5000,
        categoryId: 'eating_out',
        date: DateTime.now(),
      );

      await _pumpDashboard(tester, state);

      // No prior-month spend, so this card never appears. ("Income" is
      // ambiguous — the hero card carries an Income quick-action — so it's
      // asserted by count in the dedicated test below.)
      expect(find.text('Last month'), findsNothing);
    });

    testWidgets('the income card appears only once income is logged', (
      tester,
    ) async {
      final state = await _freshState();
      await state.addExpense(
        title: 'Lunch',
        amount: 5000,
        categoryId: 'eating_out',
        date: DateTime.now(),
      );

      // The word "Income" is ambiguous (hero toggle + hero quick-action), so
      // the card is identified by its own figure. Before any income there is
      // no income card, so its compact value is absent.
      await _pumpDashboard(tester, state);
      expect(find.text('TSh 120K'), findsNothing);

      final now = DateTime.now();
      await state.addActivity(
        Activity(
          id: 'inc-1',
          type: ActivityType.income,
          amount: 120000,
          date: now,
          updatedAt: now,
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // The income snapshot card now shows its figure.
      expect(find.text('TSh 120K'), findsOneWidget);
    });

    testWidgets('the row is absent before any spend', (tester) async {
      final state = await _freshState();

      await _pumpDashboard(tester, state);

      expect(find.text('Today'), findsNothing);
      expect(find.text('Daily average'), findsNothing);
    });
  });

  group('hero toggle', () {
    testWidgets('switches the headline figure between Spent, Income and Net', (
      tester,
    ) async {
      final state = await _freshState();
      final now = DateTime.now();
      await state.addExpense(
        title: 'Rent',
        amount: 40000,
        categoryId: 'housing',
        date: now,
      );
      await state.addActivity(
        Activity(
          id: 'inc-1',
          type: ActivityType.income,
          amount: 100000,
          date: now,
          updatedAt: now,
        ),
      );
      // Give the balance card a distinct total so its 40px figure never
      // collides with any hero metric (spent 40k / income 100k / net 60k).
      await state.updateAccount(
        state.accounts.single.copyWith(openingBalance: 1000000),
      );

      await _pumpDashboard(tester, state);

      // The snapshot cards echo the same figures, so target the hero's number
      // by its distinctive display-token size (40px).
      Finder heroFigure(String text) => find.byWidgetPredicate(
        (w) => w is Text && w.data == text && w.style?.fontSize == 40,
      );

      // Defaults to Spent.
      expect(heroFigure('TSh 40,000'), findsOneWidget);

      // Tap the toggle segments by key — both deck cards carry an "Income"
      // action label, so plain text would be ambiguous.
      await tester.tap(find.byKey(const ValueKey('metric-income')));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      expect(heroFigure('TSh 100,000'), findsOneWidget);

      // Net = income − spent = 60,000.
      await tester.tap(find.byKey(const ValueKey('metric-net')));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      expect(heroFigure('TSh 60,000'), findsOneWidget);
    });
  });
}
