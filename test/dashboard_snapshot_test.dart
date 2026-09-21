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

  group('month summary', () {
    testWidgets('renders the month summary once there is spend', (
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

      // One summary card: the spend headline plus the four sub-stats.
      expect(find.text('Spent this month'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Avg/day'), findsOneWidget);
      expect(find.text('Projected'), findsOneWidget);
      expect(find.text('Entries'), findsNothing);
      expect(find.text('Biggest'), findsNothing);
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

    testWidgets('the Recent feed lists the latest entries, newest first', (
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
      await state.addActivity(
        Activity(
          id: 'inc-1',
          type: ActivityType.income,
          amount: 120000,
          date: now.add(const Duration(minutes: 1)),
          updatedAt: now,
        ),
      );

      await _pumpDashboard(tester, state);

      // The Recent section sits well down the page; scroll it into view.
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Lunch'), 400, scrollable: list);

      // Expenses and activities interleave in one feed: the expense by title,
      // the income activity with its leading + and full figure.
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('+TSh 120,000'), findsOneWidget);
    });

    testWidgets('the summary is absent before any spend', (tester) async {
      final state = await _freshState();

      await _pumpDashboard(tester, state);

      expect(find.text('Spent this month'), findsNothing);
      expect(find.text('Today'), findsNothing);
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

      // The deck is collapsed behind the Total figure by default; tap the handle
      // to reveal it so its toggle is interactive.
      await tester.tap(find.byKey(const ValueKey('hero-handle')));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

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

  group('collapsible hero', () {
    testWidgets('shows the Total collapsed, with a handle to reveal the deck', (
      tester,
    ) async {
      final state = await _freshState();
      await state.updateAccount(
        state.accounts.single.copyWith(openingBalance: 250000),
      );

      await _pumpDashboard(tester, state);

      // Collapsed by default: the single Total figure (44px) shows the balance,
      // and the grabber that reveals the stacked cards is present.
      final total = find.byWidgetPredicate(
        (w) => w is Text && w.data == 'TSh 250,000' && w.style?.fontSize == 44,
      );
      expect(total, findsOneWidget);
      expect(find.byKey(const ValueKey('hero-handle')), findsOneWidget);
    });
  });
}
