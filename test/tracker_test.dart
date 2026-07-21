import 'package:budget/models/expense.dart';
import 'package:budget/models/palette.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _freshState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await Storage.open());
}

void main() {
  group('first launch', () {
    test('seeds categories and profiles', () async {
      final state = await _freshState();

      expect(state.categories, isNotEmpty);
      expect(state.profiles, isNotEmpty);
      expect(
        state.categories.map((category) => category.name),
        contains('Eating Out'),
      );
    });

    test('seeded categories occupy distinct palette slots', () async {
      final state = await _freshState();

      final slots = state.categories
          .map((category) => category.colorSlot)
          .whereType<int>()
          .toList();

      // Two categories sharing a hue would be indistinguishable in a chart.
      expect(slots.toSet().length, slots.length);
    });
  });

  group('palette', () {
    test('runs out rather than inventing a ninth hue', () {
      final allTaken = List<int>.generate(Palette.length, (index) => index);

      expect(Palette.firstFree(allTaken), isNull);
      expect(Palette.firstFree([0, 1]), 2);
    });

    test('a category with no slot renders neutral, not transparent', () {
      final color = Palette.color(null, Brightness.light);

      expect(color, Palette.neutralLight);
      expect(color.a, 1.0);
    });

    test('an out-of-range slot degrades to neutral instead of throwing', () {
      expect(Palette.color(99, Brightness.light), Palette.neutralLight);
      expect(Palette.color(-1, Brightness.dark), Palette.neutralDark);
    });
  });

  group('categories', () {
    test('a new category takes the next free slot automatically', () async {
      final state = await _freshState();
      final before = state.usedColorSlots;

      await state.addCategory(name: 'Advertising', iconName: 'megaphone');

      final added = state.categories.last;
      expect(added.name, 'Advertising');
      expect(before.contains(added.colorSlot), isFalse);
    });

    test('categories past the palette go neutral', () async {
      final state = await _freshState();

      // Fill every remaining slot, then add one more.
      for (var index = 0; index < Palette.length + 2; index++) {
        await state.addCategory(name: 'Extra $index', iconName: 'more');
      }

      final overflow = state.categories.last;
      expect(overflow.colorSlot, isNull);
    });

    test('deleting a category moves its expenses instead of deleting', () async {
      final state = await _freshState();
      await state.addExpense(
        title: 'Lunch',
        amount: 5000,
        categoryId: 'eating_out',
        date: DateTime.now(),
      );

      await state.deleteCategory('eating_out', reassignTo: 'other');

      expect(state.expenses, hasLength(1));
      expect(state.expenses.single.categoryId, 'other');
      expect(
        state.categories.map((category) => category.id),
        isNot(contains('eating_out')),
      );
    });

    test('an expense whose category vanished still resolves', () async {
      final state = await _freshState();

      final resolved = state.categoryById('does-not-exist');
      expect(resolved.name, 'Other');
      expect(resolved.colorSlot, isNull);
    });
  });

  group('profiles', () {
    test('expenses default to the active profile', () async {
      final state = await _freshState();
      final business = state.profiles.firstWhere((p) => p.isBusiness);

      await state.setActiveProfile(business.id);
      await state.addExpense(
        title: 'Hosting',
        amount: 40000,
        categoryId: 'bills',
        date: DateTime.now(),
      );

      expect(state.expenses.single.profileId, business.id);
    });

    test('the dashboard scopes to the active profile', () async {
      final state = await _freshState();
      final personal = state.profiles.first;
      final business = state.profiles.firstWhere((p) => p.isBusiness);

      await state.addExpense(
        title: 'Lunch',
        amount: 5000,
        categoryId: 'eating_out',
        date: DateTime.now(),
        profileId: personal.id,
      );
      await state.addExpense(
        title: 'Hosting',
        amount: 40000,
        categoryId: 'bills',
        date: DateTime.now(),
        profileId: business.id,
      );

      await state.setActiveProfile(business.id);
      expect(state.spentThisMonth, 40000);

      await state.setActiveProfile(personal.id);
      expect(state.spentThisMonth, 5000);

      // "All" shows the combined figure.
      await state.setActiveProfile(null);
      expect(state.spentThisMonth, 45000);
    });

    test('deleting a profile reassigns its expenses', () async {
      final state = await _freshState();
      final business = state.profiles.firstWhere((p) => p.isBusiness);
      final personal = state.profiles.first;

      await state.addExpense(
        title: 'Hosting',
        amount: 40000,
        categoryId: 'bills',
        date: DateTime.now(),
        profileId: business.id,
      );

      await state.deleteProfile(business.id, reassignTo: personal.id);

      expect(state.expenses, hasLength(1));
      expect(state.expenses.single.profileId, personal.id);
    });

    test('the last profile cannot be deleted', () async {
      final state = await _freshState();

      // Reduce to one, then try again.
      final business = state.profiles.firstWhere((p) => p.isBusiness);
      final personal = state.profiles.first;
      await state.deleteProfile(business.id, reassignTo: personal.id);
      await state.deleteProfile(personal.id, reassignTo: personal.id);

      expect(state.profiles, hasLength(1));
    });
  });

  group('filtering', () {
    Future<AppState> seeded() async {
      final state = await _freshState();
      await state.addExpense(
        title: 'Lunch at Kariakoo',
        amount: 5000,
        categoryId: 'eating_out',
        date: DateTime(2026, 7, 10),
        note: 'with the team',
      );
      await state.addExpense(
        title: 'Petrol',
        amount: 30000,
        categoryId: 'fuel',
        date: DateTime(2026, 7, 20),
      );
      await state.addExpense(
        title: 'Netflix',
        amount: 29000,
        categoryId: 'subscriptions',
        date: DateTime(2026, 6, 5),
      );
      return state;
    }

    test('an empty filter matches everything', () async {
      final state = await seeded();

      expect(state.search(const ExpenseFilter()), hasLength(3));
      expect(const ExpenseFilter().isActive, isFalse);
    });

    test('search matches titles', () async {
      final state = await seeded();

      final results = state.search(const ExpenseFilter(query: 'petrol'));
      expect(results, hasLength(1));
      expect(results.single.title, 'Petrol');
    });

    test('search matches notes too, and ignores case', () async {
      final state = await seeded();

      final results = state.search(const ExpenseFilter(query: 'TEAM'));
      expect(results, hasLength(1));
      expect(results.single.title, 'Lunch at Kariakoo');
    });

    test('category filter accepts several at once', () async {
      final state = await seeded();

      final results = state.search(
        const ExpenseFilter(categoryIds: {'fuel', 'subscriptions'}),
      );
      expect(results, hasLength(2));
    });

    test('the date range is inclusive of both end days', () async {
      final state = await seeded();

      final results = state.search(
        ExpenseFilter(from: DateTime(2026, 7, 10), to: DateTime(2026, 7, 20)),
      );

      // Both boundary expenses are kept, the June one is not.
      expect(results, hasLength(2));
    });

    test('an expense late on the end day is still inside the range', () async {
      final state = await _freshState();
      await state.addExpense(
        title: 'Dinner',
        amount: 20000,
        categoryId: 'eating_out',
        date: DateTime(2026, 7, 20, 22, 30),
      );

      final results = state.search(
        ExpenseFilter(from: DateTime(2026, 7, 20), to: DateTime(2026, 7, 20)),
      );
      expect(results, hasLength(1));
    });

    test('constraints combine rather than widen', () async {
      final state = await seeded();

      final results = state.search(
        const ExpenseFilter(query: 'lunch', categoryIds: {'fuel'}),
      );
      expect(results, isEmpty);
    });

    test('activeCount ignores the query, which has its own field', () async {
      const filter = ExpenseFilter(
        query: 'lunch',
        categoryIds: {'fuel'},
        profileId: 'personal',
      );

      expect(filter.activeCount, 2);
      expect(filter.isActive, isTrue);
    });
  });

  group('budgets', () {
    test('a category with no budget produces no progress card', () async {
      final state = await _freshState();
      await state.addExpense(
        title: 'Lunch',
        amount: 5000,
        categoryId: 'eating_out',
        date: DateTime.now(),
      );

      expect(state.hasAnyBudget, isFalse);
      expect(state.budgetProgress(), isEmpty);
    });

    test('progress reflects spend against the limit', () async {
      final state = await _freshState();
      final eatingOut = state.categories.firstWhere(
        (c) => c.id == 'eating_out',
      );
      await state.updateCategory(eatingOut.copyWith(monthlyBudget: 100000));

      await state.addExpense(
        title: 'Lunch',
        amount: 30000,
        categoryId: 'eating_out',
        date: DateTime.now(),
      );

      final progress = state.budgetProgress().single;
      expect(progress.spent, 30000);
      expect(progress.budget, 100000);
      expect(progress.fraction, closeTo(0.3, 0.001));
      expect(progress.remaining, 70000);
      expect(progress.isOver, isFalse);
    });

    test('over-budget is flagged and the bar is clamped to full', () async {
      final state = await _freshState();
      final fuel = state.categories.firstWhere((c) => c.id == 'fuel');
      await state.updateCategory(fuel.copyWith(monthlyBudget: 50000));

      await state.addExpense(
        title: 'Petrol',
        amount: 80000,
        categoryId: 'fuel',
        date: DateTime.now(),
      );

      final progress = state.budgetProgress().single;
      expect(progress.isOver, isTrue);
      expect(progress.fraction, greaterThan(1));
      expect(progress.barFraction, 1.0);
      expect(progress.remaining, -30000);
    });

    test('clearing a budget removes the card', () async {
      final state = await _freshState();
      final fuel = state.categories.firstWhere((c) => c.id == 'fuel');

      await state.updateCategory(fuel.copyWith(monthlyBudget: 50000));
      expect(state.hasAnyBudget, isTrue);

      await state.updateCategory(
        state.categoryById('fuel').copyWith(clearBudget: true),
      );
      expect(state.hasAnyBudget, isFalse);
    });

    test('budgets survive a round-trip through storage', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final state = AppState(storage);

      final fuel = state.categories.firstWhere((c) => c.id == 'fuel');
      await state.updateCategory(fuel.copyWith(monthlyBudget: 75000));

      // A fresh state reading the same storage should see the budget.
      final reloaded = AppState(storage);
      expect(reloaded.categoryById('fuel').monthlyBudget, 75000);
    });

    test('progress is ordered worst-first', () async {
      final state = await _freshState();
      final eatingOut = state.categories.firstWhere(
        (c) => c.id == 'eating_out',
      );
      final fuel = state.categories.firstWhere((c) => c.id == 'fuel');
      await state.updateCategory(eatingOut.copyWith(monthlyBudget: 100000));
      await state.updateCategory(fuel.copyWith(monthlyBudget: 100000));

      await state.addExpense(
        title: 'Petrol',
        amount: 90000,
        categoryId: 'fuel',
        date: DateTime.now(),
      );
      await state.addExpense(
        title: 'Lunch',
        amount: 20000,
        categoryId: 'eating_out',
        date: DateTime.now(),
      );

      // Fuel is closer to its limit, so it leads.
      expect(state.budgetProgress().first.category.id, 'fuel');
    });
  });

  group('monthly totals', () {
    test('returns one entry per month, oldest first, empties included',
        () async {
      final state = await _freshState();
      await state.addExpense(
        title: 'Lunch',
        amount: 5000,
        categoryId: 'eating_out',
        date: DateTime.now(),
      );

      final months = state.monthlyTotals(months: 6);
      expect(months, hasLength(6));
      expect(months.last.total, 5000); // current month
      expect(months.first.total, 0); // five months ago
      // Chronological order.
      expect(
        months.first.month.isBefore(months.last.month),
        isTrue,
      );
    });
  });

  group('deleting expenses', () {
    test('an expense can be restored with its id intact', () async {
      final state = await _freshState();
      await state.addExpense(
        title: 'Lunch',
        amount: 5000,
        categoryId: 'eating_out',
        date: DateTime.now(),
      );

      final original = state.expenses.single;
      await state.deleteExpense(original.id, discardAttachments: false);
      expect(state.expenses, isEmpty);

      await state.restoreExpense(original);
      expect(state.expenses.single.id, original.id);
    });
  });
}
