import 'package:budget/command/command_parser.dart';
import 'package:budget/models/account.dart';
import 'package:budget/models/activity.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The ledger: accounts and their derived balances — "where the money is".
Future<AppState> _freshState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await Storage.open());
}

Activity _income(double amount, {String? account}) => Activity(
  id: 'inc-${amount.toInt()}-${account ?? ''}',
  type: ActivityType.income,
  amount: amount,
  date: DateTime.now(),
  updatedAt: DateTime.now(),
  accountId: account,
);

void main() {
  test('a fresh state seeds one default Cash account at zero', () async {
    final state = await _freshState();

    expect(state.accounts, hasLength(1));
    expect(state.accounts.single.id, Account.defaultId);
    expect(state.accounts.single.type, AccountType.cash);
    expect(state.totalBalance, 0);
  });

  test('balance is opening + income − expenses', () async {
    final state = await _freshState();
    final cash = state.accounts.single;
    await state.updateAccount(cash.copyWith(openingBalance: 100000));

    await state.addActivity(_income(50000));
    await state.addExpense(
      title: 'Lunch',
      amount: 30000,
      categoryId: 'eating_out',
      date: DateTime.now(),
    );

    expect(state.accountBalance(cash.id), 120000);
    expect(state.totalBalance, 120000);
  });

  test('a transfer moves money between accounts but not the total', () async {
    final state = await _freshState();
    final cash = state.accounts.single;
    await state.updateAccount(cash.copyWith(openingBalance: 100000));
    await state.addAccount(name: 'M-Pesa', type: AccountType.mobileMoney);
    final mpesa = state.accounts.firstWhere((a) => a.name == 'M-Pesa');

    await state.addActivity(
      Activity(
        id: 't1',
        type: ActivityType.transfer,
        amount: 40000,
        date: DateTime.now(),
        updatedAt: DateTime.now(),
        accountId: cash.id,
        toAccountId: mpesa.id,
      ),
    );

    expect(state.accountBalance(cash.id), 60000);
    expect(state.accountBalance(mpesa.id), 40000);
    expect(state.totalBalance, 100000); // unchanged by a transfer
  });

  test('lending reduces cash; borrowing adds it', () async {
    final state = await _freshState();
    final cash = state.accounts.single;
    await state.updateAccount(cash.copyWith(openingBalance: 100000));

    await state.addActivity(
      Activity(
        id: 'lend',
        type: ActivityType.loanOut,
        amount: 20000,
        date: DateTime.now(),
        updatedAt: DateTime.now(),
        accountId: cash.id,
      ),
    );
    expect(state.accountBalance(cash.id), 80000);

    await state.addActivity(
      Activity(
        id: 'borrow',
        type: ActivityType.loanIn,
        amount: 5000,
        date: DateTime.now(),
        updatedAt: DateTime.now(),
        accountId: cash.id,
      ),
    );
    expect(state.accountBalance(cash.id), 85000);
  });

  test('records with no account resolve to the default account', () async {
    final state = await _freshState();
    final cash = state.accounts.single;

    // An activity written with a null accountId (e.g. before accounts existed)
    // still counts against the default account.
    await state.addActivity(_income(15000)); // accountId null
    await state.addExpense(
      title: 'X',
      amount: 10000,
      categoryId: 'other',
      date: DateTime.now(),
    );

    expect(state.accountBalance(cash.id), 5000);
  });

  test('accountBalances lists every account largest-first', () async {
    final state = await _freshState();
    final cash = state.accounts.single;
    await state.updateAccount(cash.copyWith(openingBalance: 30000));
    await state.addAccount(
      name: 'Bank',
      type: AccountType.bank,
      openingBalance: 500000,
    );

    final ranked = state.accountBalances;
    expect(ranked.first.account.name, 'Bank');
    expect(ranked.first.balance, 500000);
    expect(state.totalBalance, 530000);
  });

  group('command-bar account attribution', () {
    test('"spent 50000 on fuel from M-Pesa" leaves M-Pesa', () async {
      final state = await _freshState();
      await state.addAccount(
        name: 'M-Pesa',
        type: AccountType.mobileMoney,
        openingBalance: 100000,
      );
      final mpesa = state.accounts.firstWhere((a) => a.name == 'M-Pesa');

      final result = CommandParser(
        state.parseContext(),
      ).parse('spent 50000 on fuel from M-Pesa');
      expect(result.kind, CommandKind.create);
      expect(result.activity!.type, ActivityType.expense);
      expect(result.activity!.accountId, mpesa.id);

      await state.capture(result.activity!);
      expect(state.accountBalance(mpesa.id), 50000);
    });

    test('"move 200000 from CRDB to M-Pesa" moves, total unchanged', () async {
      final state = await _freshState();
      await state.addAccount(
        name: 'CRDB',
        type: AccountType.bank,
        openingBalance: 1000000,
      );
      await state.addAccount(
        name: 'M-Pesa',
        type: AccountType.mobileMoney,
        openingBalance: 100000,
      );
      final crdb = state.accounts.firstWhere((a) => a.name == 'CRDB');
      final mpesa = state.accounts.firstWhere((a) => a.name == 'M-Pesa');

      final result = CommandParser(
        state.parseContext(),
      ).parse('move 200000 from CRDB to M-Pesa');
      expect(result.activity!.type, ActivityType.transfer);
      expect(result.activity!.accountId, crdb.id);
      expect(result.activity!.toAccountId, mpesa.id);

      await state.capture(result.activity!);
      expect(state.accountBalance(crdb.id), 800000);
      expect(state.accountBalance(mpesa.id), 300000);
      expect(state.totalBalance, 1100000);
    });

    test('"received 500000 salary to bank" lands in the bank', () async {
      final state = await _freshState();
      await state.addAccount(name: 'NMB', type: AccountType.bank);
      final nmb = state.accounts.firstWhere((a) => a.name == 'NMB');

      final result = CommandParser(
        state.parseContext(),
      ).parse('received 500000 salary to bank');
      expect(result.activity!.type, ActivityType.income);
      expect(result.activity!.accountId, nmb.id);

      await state.capture(result.activity!);
      expect(state.accountBalance(nmb.id), 500000);
    });

    test('"I lent John 100000 from cash" leaves cash, John owes', () async {
      final state = await _freshState();
      final cash = state.accounts.single;
      await state.updateAccount(cash.copyWith(openingBalance: 200000));

      final result = CommandParser(
        state.parseContext(),
      ).parse('I lent John 100000 from cash');
      expect(result.activity!.type, ActivityType.loanOut);
      expect(result.activity!.accountId, cash.id);

      await state.capture(result.activity!);
      expect(state.accountBalance(cash.id), 100000);
      expect(state.balanceWith(state.people.single.id), 100000);
    });

    test('an amount with no account lands in the default account', () async {
      final state = await _freshState();
      final cash = state.accounts.single;

      final result = CommandParser(state.parseContext()).parse('5000 lunch');
      expect(result.activity!.accountId, isNull);

      await state.capture(result.activity!);
      expect(state.accountBalance(cash.id), -5000);
    });
  });
}
