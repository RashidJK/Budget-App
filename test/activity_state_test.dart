import 'package:budget/command/command_parser.dart';
import 'package:budget/models/activity.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verifies the accounting rules the spec is most emphatic about (§34, §37
/// rules 4–5): transfers and loans must never move the expense or income
/// totals, and loan balances must update correctly on repayment.

Future<AppState> _freshState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await Storage.open());
}

ParsedActivity _parsed(
  ActivityType type, {
  required double amount,
  String? personName,
  String description = '',
}) {
  return ParsedActivity(
    type: type,
    amount: amount,
    date: DateTime.now(),
    description: description,
    personName: personName,
  );
}

void main() {
  group('capture routing', () {
    test('an expense capture flows into the expense list', () async {
      final state = await _freshState();
      await state.capture(
        _parsed(ActivityType.expense, amount: 5000, description: 'Lunch'),
      );

      expect(state.expenses, hasLength(1));
      expect(state.expenses.single.amount, 5000);
      expect(state.activities, isEmpty);
    });

    test('income goes to the activity ledger, not expenses', () async {
      final state = await _freshState();
      await state.capture(
        _parsed(ActivityType.income, amount: 500000, description: 'Salary'),
      );

      expect(state.expenses, isEmpty);
      expect(state.activities, hasLength(1));
      expect(state.activities.single.type, ActivityType.income);
    });

    test('capture is undoable', () async {
      final state = await _freshState();
      final result = await state.capture(
        _parsed(ActivityType.income, amount: 500000),
      );
      expect(state.activities, hasLength(1));

      await state.undoCapture(result);
      expect(state.activities, isEmpty);
    });
  });

  group('accounting isolation (§34)', () {
    test('a transfer changes neither expenses nor income', () async {
      final state = await _freshState();
      final before = state.spentThisMonth;

      await state.capture(
        _parsed(ActivityType.transfer, amount: 100000),
      );

      expect(state.spentThisMonth, before);
      expect(state.incomeThisMonth, 0);
    });

    test('lending money is not an expense', () async {
      final state = await _freshState();
      await state.capture(
        _parsed(ActivityType.loanOut, amount: 100000, personName: 'John'),
      );

      expect(state.spentThisMonth, 0);
      expect(state.incomeThisMonth, 0);
    });

    test('borrowing money is not income', () async {
      final state = await _freshState();
      await state.capture(
        _parsed(ActivityType.loanIn, amount: 500000, personName: 'John'),
      );

      expect(state.incomeThisMonth, 0);
      expect(state.spentThisMonth, 0);
    });

    test('income counts toward the income total only', () async {
      final state = await _freshState();
      await state.capture(_parsed(ActivityType.income, amount: 500000));

      expect(state.incomeThisMonth, 500000);
      expect(state.spentThisMonth, 0);
    });
  });

  group('loan balances (§9, §10)', () {
    test('lending creates a receivable owed to the user', () async {
      final state = await _freshState();
      await state.capture(
        _parsed(ActivityType.loanOut, amount: 100000, personName: 'John'),
      );

      final john = state.people.firstWhere((p) => p.name == 'John');
      expect(state.balanceWith(john.id), 100000);
      expect(state.totalOwedToUser, 100000);
    });

    test('a repayment received reduces the receivable', () async {
      final state = await _freshState();
      await state.capture(
        _parsed(ActivityType.loanOut, amount: 100000, personName: 'John'),
      );
      await state.capture(
        _parsed(
          ActivityType.receivableRepayment,
          amount: 50000,
          personName: 'John',
        ),
      );

      final john = state.people.firstWhere((p) => p.name == 'John');
      // Owed 100k, received 50k back → 50k remaining (spec §10 example).
      expect(state.balanceWith(john.id), 50000);
    });

    test('borrowing creates a liability the user owes', () async {
      final state = await _freshState();
      await state.capture(
        _parsed(ActivityType.loanIn, amount: 500000, personName: 'Mary'),
      );

      final mary = state.people.firstWhere((p) => p.name == 'Mary');
      expect(state.balanceWith(mary.id), -500000);
      expect(state.totalOwedByUser, 500000);
    });

    test('repaying a loan reduces the liability', () async {
      final state = await _freshState();
      await state.capture(
        _parsed(ActivityType.loanIn, amount: 500000, personName: 'Mary'),
      );
      await state.capture(
        _parsed(ActivityType.loanRepayment, amount: 50000, personName: 'Mary'),
      );

      final mary = state.people.firstWhere((p) => p.name == 'Mary');
      // Owed 500k, repaid 50k → 450k remaining (spec §9 example).
      expect(state.balanceWith(mary.id), -450000);
    });

    test('the same name resolves to one person, not duplicates', () async {
      final state = await _freshState();
      await state.capture(
        _parsed(ActivityType.loanOut, amount: 100000, personName: 'John'),
      );
      await state.capture(
        _parsed(ActivityType.loanOut, amount: 50000, personName: 'john'),
      );

      expect(state.people.where((p) => p.matchKey == 'john'), hasLength(1));
      final john = state.people.firstWhere((p) => p.matchKey == 'john');
      expect(state.balanceWith(john.id), 150000);
    });
  });

  group('merchant memory (§5)', () {
    test('a merchant categorised once is remembered next time', () async {
      final state = await _freshState();

      // "DUKA" is not a built-in keyword, so only learning can categorise it.
      await state.capture(
        ParsedActivity(
          type: ActivityType.expense,
          amount: 12000,
          date: DateTime(2026, 7, 20),
          description: 'Duka',
          categoryId: 'groceries',
          merchant: 'DUKA',
        ),
      );

      final parser = CommandParser(state.parseContext());
      final result = parser.parse('paid 5000 at DUKA');
      expect(result.activity!.categoryId, 'groceries');
    });

    test('learning survives a reload', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final state = AppState(storage);
      await state.capture(
        ParsedActivity(
          type: ActivityType.expense,
          amount: 12000,
          date: DateTime(2026, 7, 20),
          categoryId: 'groceries',
          merchant: 'DUKA',
        ),
      );

      final reloaded = AppState(storage);
      expect(reloaded.parseContext().merchantCategories['duka'], 'groceries');
    });
  });

  group('parse context', () {
    test('exposes known people and their balances to the parser', () async {
      final state = await _freshState();
      await state.capture(
        _parsed(ActivityType.loanOut, amount: 100000, personName: 'John'),
      );

      final context = state.parseContext();
      expect(context.loanNetByPersonKey['john'], 100000);
      expect(context.people.map((p) => p.name), contains('John'));
    });

    test('an incoming payment from a debtor resolves to a repayment', () async {
      final state = await _freshState();
      await state.capture(
        _parsed(ActivityType.loanOut, amount: 100000, personName: 'John'),
      );

      // "I got 50000 from John" — John owes the user, so this is a repayment.
      final parser = CommandParser(state.parseContext());
      final result = parser.parse('I got 50000 from John');
      expect(result.kind, CommandKind.create);
      expect(result.activity!.type, ActivityType.receivableRepayment);
    });
  });

  group('delete and restore (Undo)', () {
    test('restoring a deleted activity clears the tombstone', () async {
      final state = await _freshState();
      final now = DateTime.now();
      final activity = await state.addActivity(
        Activity(
          id: 'a1',
          type: ActivityType.income,
          amount: 100000,
          date: now,
          updatedAt: now,
        ),
      );
      expect(state.activities, hasLength(1));

      await state.deleteActivity(activity.id);
      expect(state.activities, isEmpty);

      await state.restoreActivity(activity.id);
      expect(state.activities, hasLength(1));
      // Regression: copyWith carried deletedAt through, so Undo left it deleted.
      expect(state.activities.single.deletedAt, isNull);
    });

    test('undo of a deleted loan restores the person balance', () async {
      final state = await _freshState();
      await state.capture(
        _parsed(ActivityType.loanOut, amount: 100000, personName: 'John'),
      );
      final john = state.people.single;
      expect(state.balanceWith(john.id), 100000);

      final activity = state.activities.single;
      await state.deleteActivity(activity.id);
      expect(state.balanceWith(john.id), 0);

      await state.restoreActivity(activity.id);
      expect(state.balanceWith(john.id), 100000);
    });

    test('a restored activity survives a reload', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final state = AppState(storage);
      final now = DateTime.now();
      final activity = await state.addActivity(
        Activity(
          id: 'a1',
          type: ActivityType.income,
          amount: 5000,
          date: now,
          updatedAt: now,
        ),
      );
      await state.deleteActivity(activity.id);
      await state.restoreActivity(activity.id);

      // A fresh state reading the same storage should see the live record.
      final reloaded = AppState(storage);
      expect(reloaded.activities, hasLength(1));
    });
  });
}
