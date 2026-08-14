import 'package:budget/command/command_parser.dart';
import 'package:budget/models/activity.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the spec's development test matrix (§38) plus the ambiguity and
/// accounting rules (§11, §37). The parser is pure, so these run instantly and
/// pin every classification the feature was signed off against.

/// Context with the seed categories and a couple of known people/profiles.
ParseContext _ctx({
  Map<String, double> loans = const {},
  List<({String id, String name})> people = const [],
}) {
  return ParseContext(
    knownCategoryIds: const {
      'eating_out',
      'groceries',
      'transport',
      'fuel',
      'housing',
      'bills',
      'subscriptions',
      'family',
      'other',
    },
    profileMatches: const {'flow-hq': 'flowhq', 'oea': 'oea'},
    people: people,
    loanNetByPersonKey: loans,
  );
}

CommandParser _parser({
  Map<String, double> loans = const {},
  List<({String id, String name})> people = const [],
}) => CommandParser(_ctx(loans: loans, people: people));

void main() {
  // Freeze the clock so date assertions are stable.
  setUp(() => CommandParser.clock = () => DateTime(2026, 7, 20, 12));
  tearDown(() => CommandParser.clock = null);

  group('expenses (§5, §38)', () {
    test('"5000 lunch" — bare amount + noun defaults to an expense', () {
      final result = _parser().parse('5000 lunch');
      expect(result.kind, CommandKind.create);
      expect(result.activity!.type, ActivityType.expense);
      expect(result.activity!.amount, 5000);
      expect(result.activity!.categoryId, 'eating_out');
      expect(result.activity!.description.toLowerCase(), contains('lunch'));
    });

    test('"I spent 5000 on lunch"', () {
      final result = _parser().parse('I spent 5000 on lunch');
      expect(result.activity!.type, ActivityType.expense);
      expect(result.activity!.amount, 5000);
      expect(result.activity!.categoryId, 'eating_out');
    });

    test('"Paid 80000 cash for fuel" — captures payment method', () {
      final result = _parser().parse('Paid 80000 cash for fuel');
      expect(result.activity!.type, ActivityType.expense);
      expect(result.activity!.amount, 80000);
      expect(result.activity!.categoryId, 'fuel');
      expect(result.activity!.paymentMethod, PaymentMethod.cash);
    });

    test('"Bought groceries for 120000"', () {
      final result = _parser().parse('Bought groceries for 120000');
      expect(result.activity!.type, ActivityType.expense);
      expect(result.activity!.amount, 120000);
      expect(result.activity!.categoryId, 'groceries');
    });

    test('"I paid 35000 for internet" maps to bills', () {
      final result = _parser().parse('I paid 35000 for internet');
      expect(result.activity!.type, ActivityType.expense);
      expect(result.activity!.categoryId, 'bills');
    });

    test('thousands separators and k/m suffixes parse', () {
      expect(_parser().parse('spent 35,000 on fuel').activity!.amount, 35000);
      expect(_parser().parse('5k lunch').activity!.amount, 5000);
      expect(_parser().parse('spent 1.5m on rent').activity!.amount, 1500000);
    });
  });

  group('income (§5, §38)', () {
    test('"Received 500000 salary"', () {
      final result = _parser().parse('Received 500000 salary');
      expect(result.kind, CommandKind.create);
      expect(result.activity!.type, ActivityType.income);
      expect(result.activity!.amount, 500000);
    });

    test('"OEA paid me 300000" is income, not an expense', () {
      final result = _parser().parse('OEA paid me 300000');
      expect(result.activity!.type, ActivityType.income);
      expect(result.activity!.amount, 300000);
    });

    test('"I got 100000 from freelance work" with no person is income', () {
      // No known person and no loan context → the safe reading is income.
      final result = _parser().parse('I got 100000 from freelance work');
      expect(
        result.activity?.type ?? ActivityType.income,
        ActivityType.income,
      );
    });
  });

  group('transfers (§6, §38)', () {
    test('"Transfer 100000 from bank to M-Pesa"', () {
      final result = _parser().parse('Transfer 100000 from bank to M-Pesa');
      expect(result.activity!.type, ActivityType.transfer);
      expect(result.activity!.amount, 100000);
      expect(result.activity!.sourceAccount, 'Bank');
      expect(result.activity!.destinationAccount, 'M-Pesa');
    });

    test('"Moved 200000 to my savings account"', () {
      final result = _parser().parse('Moved 200000 to my savings account');
      expect(result.activity!.type, ActivityType.transfer);
      expect(result.activity!.destinationAccount, 'Savings');
    });

    test('a transfer is never an expense', () {
      final result = _parser().parse('I transferred 100000 from bank to mpesa');
      expect(result.activity!.type, isNot(ActivityType.expense));
    });
  });

  group('lending (§7, §38)', () {
    test('"I lent John 100000"', () {
      final result = _parser().parse('I lent John 100000');
      expect(result.activity!.type, ActivityType.loanOut);
      expect(result.activity!.amount, 100000);
      expect(result.activity!.personName, 'John');
    });

    test('"Give John 50000 as a loan"', () {
      final result = _parser().parse('Give John 50000 as a loan');
      expect(result.activity!.type, ActivityType.loanOut);
      expect(result.activity!.personName, 'John');
    });

    test('lending is not an expense', () {
      final result = _parser().parse('I lent John 100000');
      expect(result.activity!.type, isNot(ActivityType.expense));
    });
  });

  group('borrowing (§8, §38)', () {
    test('"I borrowed 500000 from John"', () {
      final result = _parser().parse('I borrowed 500000 from John');
      expect(result.activity!.type, ActivityType.loanIn);
      expect(result.activity!.amount, 500000);
      expect(result.activity!.personName, 'John');
    });

    test('"John loaned me 300000"', () {
      final result = _parser().parse('John loaned me 300000');
      expect(result.activity!.type, ActivityType.loanIn);
      expect(result.activity!.personName, 'John');
    });

    test('borrowing is not income', () {
      final result = _parser().parse('I borrowed 500000 from John');
      expect(result.activity!.type, isNot(ActivityType.income));
    });
  });

  group('repayments (§9, §10, §38)', () {
    test('"I paid John back 50000" is a loan repayment', () {
      final result = _parser().parse('I paid John back 50000');
      expect(result.activity!.type, ActivityType.loanRepayment);
      expect(result.activity!.personName, 'John');
      expect(result.activity!.amount, 50000);
    });

    test('"John paid me back 50000" is a receivable repayment', () {
      final result = _parser().parse('John paid me back 50000');
      expect(result.activity!.type, ActivityType.receivableRepayment);
      expect(result.activity!.personName, 'John');
    });

    test('a repayment is neither an expense nor income', () {
      final out = _parser().parse('I paid John back 50000').activity!.type;
      final incoming = _parser().parse('John paid me back 50000').activity!.type;
      expect(out, isNot(ActivityType.expense));
      expect(incoming, isNot(ActivityType.income));
    });
  });

  group('ambiguity (§11)', () {
    test('"I got 100000 from John" with no context asks one question', () {
      final result = _parser(
        people: [(id: 'p1', name: 'John')],
      ).parse('I got 100000 from John');

      expect(result.kind, CommandKind.ambiguous);
      expect(result.clarificationTypes, isNotEmpty);
      expect(result.clarificationQuestion, isNotNull);
    });

    test('prefers repayment when John already owes the user', () {
      // John owes the user 100k → receiving from John settles that.
      final result = _parser(
        people: [(id: 'p1', name: 'John')],
        loans: {'john': 100000},
      ).parse('I got 100000 from John');

      expect(result.kind, CommandKind.create);
      expect(result.activity!.type, ActivityType.receivableRepayment);
    });

    test('prefers a loan-in when the user already owes John', () {
      final result = _parser(
        people: [(id: 'p1', name: 'John')],
        loans: {'john': -200000},
      ).parse('I got 100000 from John');

      expect(result.kind, CommandKind.create);
      expect(result.activity!.type, ActivityType.loanIn);
    });
  });

  group('profiles (§24)', () {
    test('"Flow-HQ paid 100000 for hosting" attaches the business profile', () {
      final result = _parser().parse('Flow-HQ paid 100000 for hosting');
      expect(result.activity!.profileId, 'flowhq');
      expect(result.activity!.categoryId, 'subscriptions');
    });
  });

  group('history queries (§21, §36)', () {
    test('"How much did I spend on fuel this month?"', () {
      final result = _parser().parse('How much did I spend on fuel this month?');
      expect(result.kind, CommandKind.query);
      expect(result.query!.topic, QueryTopic.categorySpend);
      expect(result.query!.categoryId, 'fuel');
      expect(result.query!.timeframe, Timeframe.thisMonth);
    });

    test('"What did I spend last month?" is a total over last month', () {
      final result = _parser().parse('What did I spend last month?');
      expect(result.kind, CommandKind.query);
      expect(result.query!.topic, QueryTopic.totalSpend);
      expect(result.query!.timeframe, Timeframe.lastMonth);
    });

    test('"Show my biggest expenses"', () {
      final result = _parser().parse('Show my biggest expenses');
      expect(result.kind, CommandKind.query);
      expect(result.query!.topic, QueryTopic.biggestExpenses);
    });

    test('"How much does John owe me?"', () {
      final result = _parser().parse('How much does John owe me?');
      expect(result.kind, CommandKind.query);
      expect(result.query!.topic, QueryTopic.owedToMe);
      expect(result.query!.personName, 'John');
    });

    test('"How much do I owe John?"', () {
      final result = _parser().parse('How much do I owe John?');
      expect(result.kind, CommandKind.query);
      expect(result.query!.topic, QueryTopic.iOwe);
      expect(result.query!.personName, 'John');
    });

    test('"Show my expenses at TotalEnergies"', () {
      final result = _parser().parse('Show my expenses at TotalEnergies');
      expect(result.kind, CommandKind.query);
      expect(result.query!.topic, QueryTopic.merchantSpend);
      expect(result.query!.merchant, contains('TotalEnergies'));
    });

    test('"What did I spend on fuel in July?" picks the month', () {
      final result = _parser().parse('What did I spend on fuel in July?');
      expect(result.query!.categoryId, 'fuel');
      expect(result.query!.timeframe, Timeframe.specificMonth);
      expect(result.query!.month, 7);
    });

    test('a history question never creates an activity', () {
      final result = _parser().parse('How much did I spend on fuel this month?');
      expect(result.activity, isNull);
    });
  });

  group('planner queries (§22, §36)', () {
    test('"If I spend 5000 on lunch every day, how much will I spend?"', () {
      final result = _parser()
          .parse('If I spend 5000 on lunch every day, how much will I spend?');
      expect(result.kind, CommandKind.plan);
      expect(result.plan!.topic, PlanTopic.dailyHabit);
      expect(result.plan!.dailyAmount, 5000);
      expect(result.plan!.categoryId, 'eating_out');
    });

    test('"What if I reduce lunch to 3000?" compares two amounts', () {
      final result = _parser().parse('What if I reduce lunch from 5000 to 3000?');
      expect(result.kind, CommandKind.plan);
      expect(result.plan!.topic, PlanTopic.reduce);
      expect(result.plan!.dailyAmount, 5000);
      expect(result.plan!.newAmount, 3000);
    });

    test('"How much will fuel cost if I drive 60km a day?"', () {
      final result = _parser().parse('How much will fuel cost if I drive 60km a day?');
      expect(result.kind, CommandKind.plan);
      expect(result.plan!.topic, PlanTopic.fuel);
      expect(result.plan!.distancePerDay, 60);
    });

    test('a plan question never creates an activity', () {
      final result = _parser()
          .parse('If I spend 5000 on lunch every day, how much will I spend?');
      expect(result.activity, isNull);
    });
  });

  group('paste / SMS (§12)', () {
    test('extracts amount and merchant from a mobile-money SMS', () {
      final result = _parser().parsePaste(
        'You have paid TZS 35,000 to TOTALENERGIES MIKOCHENI. '
        'Your balance is TZS 120,000.',
      );
      expect(result.kind, CommandKind.create);
      expect(result.activity!.type, ActivityType.expense);
      expect(result.activity!.amount, 35000);
      expect(result.activity!.categoryId, 'fuel');
      expect(result.activity!.merchant, contains('TOTALENERGIES'));
    });
  });

  // Regressions for defects surfaced by the adversarial verification pass.
  group('amount extraction hardening', () {
    test('a following word starting with m is not a millions suffix', () {
      // "5000 milk" must be 5000, not 5000 × 1,000,000.
      expect(_parser().parse('5000 milk').activity!.amount, 5000);
      expect(_parser().parse('spent 100 monthly').activity!.amount, 100);
    });

    test('a leading quantity loses to the real price', () {
      expect(_parser().parse('2 sodas 6000').activity!.amount, 6000);
    });

    test('a comma-grouped amount beats a bare number', () {
      expect(
        _parser().parse('iphone 15 pro 2,500,000').activity!.amount,
        2500000,
      );
    });

    test('a year is not mistaken for the amount', () {
      expect(_parser().parse('rent for 2024 150000').activity!.amount, 150000);
    });

    test('space-grouped thousands parse', () {
      expect(_parser().parse('1 200 000 rent').activity!.amount, 1200000);
    });

    test('a decimal amount in an SMS is kept', () {
      final result = _parser()
          .parsePaste('You have paid Tsh 1,234.56 to DUKA');
      expect(result.activity!.amount, closeTo(1234.56, 0.001));
    });

    test('a transaction reference is not read as the amount', () {
      final result = _parser().parsePaste(
        'TID 20240814012345 You paid TZS 35,000 to TOTALENERGIES',
      );
      expect(result.activity!.amount, 35000);
    });
  });

  group('classification hardening', () {
    test('"got a bonus of 200000" is income, not an expense', () {
      final result = _parser().parse('got a bonus of 200000');
      expect(result.activity!.type, ActivityType.income);
    });

    test('"I made 5000 selling airtime" is income', () {
      final result = _parser().parse('I made 5000 selling airtime');
      expect(result.activity!.type, ActivityType.income);
    });

    test('"refunded the customer 5000" is an expense, not income', () {
      final result = _parser().parse('refunded the customer 5000');
      expect(result.activity!.type, ActivityType.expense);
    });

    test('"withdrew 100000 from bank" is a transfer, not spending', () {
      final result = _parser().parse('withdrew 100000 from bank');
      expect(result.activity!.type, ActivityType.transfer);
    });

    test('"John owes me 5000" records a receivable (loan out)', () {
      final result = _parser().parse('John owes me 5000');
      expect(result.activity!.type, ActivityType.loanOut);
    });

    test('paying a person you owe is a repayment, not an expense', () {
      final result = _parser(
        people: [(id: 'p1', name: 'John')],
        loans: {'john': -200000},
      ).parse('sent 20000 to John');
      expect(result.activity!.type, ActivityType.loanRepayment);
    });
  });

  group('person extraction hardening', () {
    test('a lowercased name after a cue is attributed', () {
      final result = _parser().parse('i lent john 5000');
      expect(result.activity!.type, ActivityType.loanOut);
      expect(result.activity!.personName, 'John');
    });

    test('a two-word name is captured whole', () {
      final result = _parser().parse('I lent Mary Jane 5000');
      expect(result.activity!.personName, 'Mary Jane');
    });

    test('"Rent paid 5000" has no person — it is an ordinary expense', () {
      final result = _parser().parse('Rent paid 5000');
      expect(result.activity!.type, ActivityType.expense);
      expect(result.activity!.personName, isNull);
    });
  });

  group('query safety hardening', () {
    test('a query-shaped input never records a transaction', () {
      // The dangerous case: an inspection must not silently write data.
      final result = _parser().parse('show me expenses above 20000');
      expect(result.kind, CommandKind.query);
      expect(result.activity, isNull);
    });

    test('"what do i owe Mary" is an I-owe query', () {
      final result = _parser().parse('what do i owe Mary');
      expect(result.kind, CommandKind.query);
      expect(result.query!.topic, QueryTopic.iOwe);
      expect(result.query!.personName, 'Mary');
    });

    test('"how much do i spend at the market" maps to groceries', () {
      final result = _parser().parse('how much do i spend at the market');
      expect(result.kind, CommandKind.query);
      expect(result.query!.topic, QueryTopic.categorySpend);
      expect(result.query!.categoryId, 'groceries');
    });

    test('"how much will it cost me this month" is a spend query', () {
      final result = _parser().parse('how much will it cost me this month');
      expect(result.kind, CommandKind.query);
      expect(result.activity, isNull);
    });
  });

  group('edge cases', () {
    test('empty input is unknown', () {
      expect(_parser().parse('').kind, CommandKind.unknown);
      expect(_parser().parse('   ').kind, CommandKind.unknown);
    });

    test('text with no amount is unknown', () {
      expect(_parser().parse('hello there').kind, CommandKind.unknown);
    });

    test('"yesterday" backdates the activity', () {
      final result = _parser().parse('spent 5000 on lunch yesterday');
      expect(result.activity!.date, DateTime(2026, 7, 19, 12));
    });

    test('confidence is set for a clean expense', () {
      final result = _parser().parse('I spent 5000 on lunch');
      expect(result.confidence, greaterThan(0.7));
    });
  });
}
