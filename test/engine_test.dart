import 'package:budget/planner/engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every "spec example" test below pins a figure quoted in the Planner
/// specification, so a change to the time constants can't silently move the
/// numbers the feature was signed off against.
void main() {
  group('daily habit breakdown', () {
    test('spec example: TSh 5,000/day every day', () {
      final result = breakdownFor(
        amount: 5000,
        frequency: Frequency.everyDay,
      );

      expect(result.daily, 5000);
      expect(result.weekly, 35000);
      expect(result.monthly, 150000);
      expect(result.yearly, 1825000);
    });

    test('yearly comes from the daily rate, not monthly x 12', () {
      final result = breakdownFor(
        amount: 5000,
        frequency: Frequency.everyDay,
      );

      // 12 x 30-day months is 360 days and would lose five days of spending.
      expect(result.yearly, isNot(result.monthly * 12));
      expect(result.yearly - result.monthly * 12, 25000);
    });

    test('weekdays only bills five days in seven', () {
      final result = breakdownFor(
        amount: 5000,
        frequency: Frequency.weekdaysOnly,
      );

      expect(result.weekly, 25000);
      expect(result.yearly, closeTo(1303571, 1));
      // The daily figure is averaged across all seven days.
      expect(result.daily, closeTo(3571.43, 0.01));
    });

    test('weekends only bills two days in seven', () {
      final result = breakdownFor(
        amount: 5000,
        frequency: Frequency.weekendsOnly,
      );

      expect(result.weekly, 10000);
      expect(result.yearly, closeTo(521428, 1));
    });

    test('custom days per month scales to twelve months', () {
      final result = breakdownFor(
        amount: 5000,
        frequency: Frequency.customPerMonth,
        customDaysPerMonth: 10,
      );

      expect(result.monthly, 50000);
      expect(result.yearly, 600000);
    });

    test('custom days per month is clamped to a real month', () {
      final result = breakdownFor(
        amount: 1000,
        frequency: Frequency.customPerMonth,
        customDaysPerMonth: 90,
      );

      expect(result.monthly, 31000);
    });

    test('a zero or negative amount produces no cost', () {
      expect(breakdownFor(amount: 0, frequency: Frequency.everyDay).yearly, 0);
      expect(breakdownFor(amount: -5, frequency: Frequency.everyDay).yearly, 0);
    });
  });

  group('fuel', () {
    test('spec example: 60 km/day at 12 km/L and TSh 3,200/L', () {
      final result = estimateFuel(
        distancePerDay: 60,
        efficiency: 12,
        pricePerLitre: 3200,
      );

      expect(result.litresPerMonth, 150);
      expect(result.litresPerDay, 5);
      expect(result.cost.monthly, 480000);
      // The spec quotes 5,760,000 here, which is monthly x 12 = 360 days.
      // Charging all 365 days is 5,840,000.
      expect(result.cost.yearly, 5840000);
    });

    test('weekday-only driving costs less than every day', () {
      final everyDay = estimateFuel(
        distancePerDay: 60,
        efficiency: 12,
        pricePerLitre: 3200,
      );
      final commute = estimateFuel(
        distancePerDay: 60,
        efficiency: 12,
        pricePerLitre: 3200,
        frequency: Frequency.weekdaysOnly,
      );

      expect(commute.cost.yearly, lessThan(everyDay.cost.yearly));
      expect(commute.cost.yearly, closeTo(everyDay.cost.yearly * 5 / 7, 1));
    });

    test('zero efficiency does not divide by zero', () {
      final result = estimateFuel(
        distancePerDay: 60,
        efficiency: 0,
        pricePerLitre: 3200,
      );

      expect(result.cost.yearly, 0);
      expect(result.litresPerMonth, 0);
    });
  });

  group('subscriptions', () {
    test('a monthly charge annualises to twelve payments', () {
      final result = subscriptionBreakdown(
        amount: 25000,
        cycle: BillingCycle.monthly,
      );

      expect(result.monthly, 25000);
      expect(result.yearly, 300000);
    });

    test('a yearly charge spreads back over twelve months', () {
      final result = subscriptionBreakdown(
        amount: 120000,
        cycle: BillingCycle.yearly,
      );

      expect(result.yearly, 120000);
      expect(result.monthly, 10000);
    });

    test('quarterly bills four times a year', () {
      final result = subscriptionBreakdown(
        amount: 30000,
        cycle: BillingCycle.quarterly,
      );

      expect(result.yearly, 120000);
    });

    test('next payment steps forward past today', () {
      final next = nextPaymentDate(
        start: DateTime(2026, 1, 10),
        cycle: BillingCycle.monthly,
        from: DateTime(2026, 7, 20),
      );

      expect(next, DateTime(2026, 8, 10));
    });

    test('a future start date is returned untouched', () {
      final next = nextPaymentDate(
        start: DateTime(2026, 9, 1),
        cycle: BillingCycle.monthly,
        from: DateTime(2026, 7, 20),
      );

      expect(next, DateTime(2026, 9, 1));
    });

    test('a 31st anchor clamps in short months without drifting', () {
      final next = nextPaymentDate(
        start: DateTime(2026, 1, 31),
        cycle: BillingCycle.monthly,
        from: DateTime(2026, 2, 1),
      );

      // February clamps to the 28th rather than spilling into March.
      expect(next, DateTime(2026, 2, 28));

      final after = nextPaymentDate(
        start: DateTime(2026, 1, 31),
        cycle: BillingCycle.monthly,
        from: DateTime(2026, 3, 1),
      );

      // ...and the anchor is restored the following month.
      expect(after, DateTime(2026, 3, 31));
    });
  });

  group('business costs', () {
    test('totals line items and targets a 30% margin by default', () {
      final result = estimateBusiness(
        monthlyCosts: [500000, 200000, 300000],
      );

      expect(result.monthlyCost, 1000000);
      expect(result.yearlyCost, 12000000);
      // 1,000,000 / 0.7 leaves 30% of revenue as profit.
      expect(result.recommendedMonthlyRevenue, closeTo(1428571.43, 0.01));
      expect(result.monthlyProfit, closeTo(428571.43, 0.01));
    });

    test('a zero margin recommends exactly break-even revenue', () {
      final result = estimateBusiness(
        monthlyCosts: [400000],
        targetMargin: 0,
      );

      expect(result.recommendedMonthlyRevenue, 400000);
    });

    test('an impossible margin is clamped below 100%', () {
      final result = estimateBusiness(
        monthlyCosts: [400000],
        targetMargin: 1.5,
      );

      expect(result.recommendedMonthlyRevenue.isFinite, isTrue);
    });

    test('blank line items are ignored', () {
      final result = estimateBusiness(monthlyCosts: [100000, 0, -50]);

      expect(result.monthlyCost, 100000);
    });
  });

  group('savings comparison', () {
    test('spec example: TSh 5,000/day against TSh 2,500/day', () {
      final comparison = SavingsComparison(
        current: breakdownFor(amount: 5000, frequency: Frequency.everyDay),
        alternative: breakdownFor(amount: 2500, frequency: Frequency.everyDay),
      );

      expect(comparison.monthlySaving, 75000);
      expect(comparison.yearlySaving, 912500);
      expect(comparison.percentSaved, 0.5);
      expect(comparison.isWorse, isFalse);
    });

    test('a pricier alternative is flagged rather than shown as a saving', () {
      final comparison = SavingsComparison(
        current: breakdownFor(amount: 2000, frequency: Frequency.everyDay),
        alternative: breakdownFor(amount: 3000, frequency: Frequency.everyDay),
      );

      expect(comparison.isWorse, isTrue);
      expect(comparison.yearlySaving, lessThan(0));
    });

    test('comparing against nothing does not produce NaN', () {
      const comparison = SavingsComparison(
        current: CostBreakdown.zero(),
        alternative: CostBreakdown.zero(),
      );

      expect(comparison.percentSaved, 0);
      expect(comparison.percentSaved.isNaN, isFalse);
    });
  });

  group('long-term projection', () {
    test('spec example: TSh 5,000/day reaches ~9.1M over five years', () {
      final points = project(
        breakdown: breakdownFor(amount: 5000, frequency: Frequency.everyDay),
      );
      final fiveYears = points.firstWhere((point) => point.years == 5);

      expect(fiveYears.cumulative, 9125000);
    });

    test('all four horizons are linear when inflation is off', () {
      final points = project(
        breakdown: breakdownFor(amount: 5000, frequency: Frequency.everyDay),
      );

      expect(points.map((point) => point.cumulative), [
        1825000,
        5475000,
        9125000,
        18250000,
      ]);
    });

    test('inflation compounds year on year', () {
      final points = project(
        breakdown: breakdownFor(amount: 5000, frequency: Frequency.everyDay),
        horizons: [2],
        annualIncrease: 0.10,
      );

      // 1,825,000 + (1,825,000 x 1.10)
      expect(points.single.cumulative, closeTo(3832500, 0.01));
    });

    test('the charting series starts at zero and covers every year', () {
      final series = projectSeries(
        breakdown: breakdownFor(amount: 5000, frequency: Frequency.everyDay),
        years: 10,
      );

      expect(series.length, 11);
      expect(series.first.cumulative, 0);
      expect(series.last.cumulative, 18250000);
    });
  });
}
