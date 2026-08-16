/// Pure calculation engine for the Planner.
///
/// No Flutter imports — every function here is a deterministic transformation
/// of numbers, which keeps the maths independently testable and lets the UI
/// call it freely on every keystroke.
///
/// ## Time conventions
///
/// Two constants drive everything:
///
///   * a month is **30 days**
///   * a year is **365 days**
///
/// These deliberately disagree (12 x 30 = 360, not 365). Monthly figures use
/// the 30-day month people picture when they budget; yearly figures use the
/// real length of a year so long-range projections don't silently lose five
/// days of spending. A yearly total is therefore always derived from the daily
/// rate, never from `monthly * 12`.
library;

const double daysPerWeek = 7;
const double daysPerMonth = 30;
const double daysPerYear = 365;
const double weeksPerYear = daysPerYear / daysPerWeek;
const double monthsPerYear = 12;

/// How often a recurring cost is actually incurred.
enum Frequency {
  everyDay('Every day'),
  weekdaysOnly('Weekdays only'),
  weekendsOnly('Weekends only'),
  customPerMonth('Custom days / month');

  const Frequency(this.label);
  final String label;

  /// Resolves a stored [name] back to its value, defaulting to [everyDay] for
  /// unknown/legacy strings — matches the convention on activity.dart's enums.
  static Frequency fromName(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => everyDay);
}

/// The number of times a cost occurs per week / month / year for a given
/// frequency.
///
/// [customDaysPerMonth] is only read when [frequency] is
/// [Frequency.customPerMonth].
class Occurrences {
  const Occurrences({
    required this.perWeek,
    required this.perMonth,
    required this.perYear,
  });

  factory Occurrences.of(Frequency frequency, {double customDaysPerMonth = 0}) {
    switch (frequency) {
      case Frequency.everyDay:
        return const Occurrences(
          perWeek: 7,
          perMonth: daysPerMonth,
          perYear: daysPerYear,
        );
      case Frequency.weekdaysOnly:
        return _fromDaysPerWeek(5);
      case Frequency.weekendsOnly:
        return _fromDaysPerWeek(2);
      case Frequency.customPerMonth:
        final perMonth = customDaysPerMonth.clamp(0.0, 31.0);
        return Occurrences(
          perWeek: perMonth * monthsPerYear / weeksPerYear,
          perMonth: perMonth,
          perYear: perMonth * monthsPerYear,
        );
    }
  }

  /// Scales the "every day" baseline down to [days] days out of every seven.
  static Occurrences _fromDaysPerWeek(double days) {
    final share = days / daysPerWeek;
    return Occurrences(
      perWeek: days,
      perMonth: daysPerMonth * share,
      perYear: daysPerYear * share,
    );
  }

  final double perWeek;
  final double perMonth;
  final double perYear;

  /// Average occurrences per day, used to express any frequency as a daily
  /// run rate.
  double get perDay => perYear / daysPerYear;
}

/// The four headline numbers every planner screen reports.
class CostBreakdown {
  const CostBreakdown({
    required this.daily,
    required this.weekly,
    required this.monthly,
    required this.yearly,
  });

  const CostBreakdown.zero() : daily = 0, weekly = 0, monthly = 0, yearly = 0;

  final double daily;
  final double weekly;
  final double monthly;
  final double yearly;

  /// Cumulative spend across [years] years.
  double over(double years) => yearly * years;

  CostBreakdown operator +(CostBreakdown other) => CostBreakdown(
    daily: daily + other.daily,
    weekly: weekly + other.weekly,
    monthly: monthly + other.monthly,
    yearly: yearly + other.yearly,
  );
}

/// Spreads a per-occurrence [amount] across the standard time buckets.
///
/// [amount] is what a single occurrence costs — one lunch, one tank top-up —
/// not a daily total. For frequencies that skip days (weekdays only, say) the
/// `daily` figure is an *average* across all seven days, which is what makes
/// the four numbers internally consistent.
CostBreakdown breakdownFor({
  required double amount,
  required Frequency frequency,
  double customDaysPerMonth = 0,
}) {
  if (amount <= 0) return const CostBreakdown.zero();

  final occurrences = Occurrences.of(
    frequency,
    customDaysPerMonth: customDaysPerMonth,
  );

  return CostBreakdown(
    daily: amount * occurrences.perDay,
    weekly: amount * occurrences.perWeek,
    monthly: amount * occurrences.perMonth,
    yearly: amount * occurrences.perYear,
  );
}

// ---------------------------------------------------------------------------
// Fuel
// ---------------------------------------------------------------------------

/// Fuel consumption and cost for a driving habit.
class FuelEstimate {
  const FuelEstimate({
    required this.litresPerDay,
    required this.litresPerMonth,
    required this.litresPerYear,
    required this.cost,
  });

  const FuelEstimate.zero()
    : litresPerDay = 0,
      litresPerMonth = 0,
      litresPerYear = 0,
      cost = const CostBreakdown.zero();

  /// Averaged across every day, including days not driven.
  final double litresPerDay;
  final double litresPerMonth;
  final double litresPerYear;
  final CostBreakdown cost;
}

/// Estimates fuel burn from distance, efficiency and pump price.
///
/// [efficiency] is km per litre. A non-positive efficiency would divide by
/// zero, so it short-circuits to an empty estimate rather than returning
/// infinity to the UI.
FuelEstimate estimateFuel({
  required double distancePerDay,
  required double efficiency,
  required double pricePerLitre,
  Frequency frequency = Frequency.everyDay,
  double customDaysPerMonth = 0,
}) {
  if (distancePerDay <= 0 || efficiency <= 0 || pricePerLitre <= 0) {
    return const FuelEstimate.zero();
  }

  final litresPerTrip = distancePerDay / efficiency;
  final occurrences = Occurrences.of(
    frequency,
    customDaysPerMonth: customDaysPerMonth,
  );

  return FuelEstimate(
    litresPerDay: litresPerTrip * occurrences.perDay,
    litresPerMonth: litresPerTrip * occurrences.perMonth,
    litresPerYear: litresPerTrip * occurrences.perYear,
    cost: breakdownFor(
      amount: litresPerTrip * pricePerLitre,
      frequency: frequency,
      customDaysPerMonth: customDaysPerMonth,
    ),
  );
}

// ---------------------------------------------------------------------------
// Subscriptions
// ---------------------------------------------------------------------------

/// How often a subscription bills.
enum BillingCycle {
  weekly('Weekly', daysPerYear / daysPerWeek),
  monthly('Monthly', monthsPerYear),
  quarterly('Quarterly', 4),
  yearly('Yearly', 1);

  const BillingCycle(this.label, this.chargesPerYear);
  final String label;

  /// Number of times this cycle bills in a year.
  final double chargesPerYear;

  /// Resolves a stored [name] back to its value, defaulting to [monthly].
  static BillingCycle fromName(String? name) =>
      values.firstWhere((c) => c.name == name, orElse: () => monthly);
}

/// Spreads a subscription charge across the standard time buckets.
CostBreakdown subscriptionBreakdown({
  required double amount,
  required BillingCycle cycle,
}) {
  if (amount <= 0) return const CostBreakdown.zero();

  final yearly = amount * cycle.chargesPerYear;
  return CostBreakdown(
    daily: yearly / daysPerYear,
    weekly: yearly / weeksPerYear,
    monthly: yearly / monthsPerYear,
    yearly: yearly,
  );
}

/// The next billing date on or after [from], stepping forward from [start].
///
/// Walks whole cycles so the day-of-month anchor is preserved rather than
/// drifting. Month arithmetic clamps to the end of short months, so a payment
/// anchored on the 31st bills on the 30th in November and rebounds afterwards.
DateTime nextPaymentDate({
  required DateTime start,
  required BillingCycle cycle,
  DateTime? from,
}) {
  final reference = _dateOnly(from ?? DateTime.now());
  final anchor = _dateOnly(start);
  var steps = 0;
  var next = anchor;

  // A subscription started years ago still needs a *future* date, so advance
  // until we pass the reference. Each candidate is measured from the original
  // anchor rather than the previous result: stepping from a clamped date would
  // turn one short month into a permanent shift (31st -> 28th -> 28th...).
  // The guard stops a pathological input from looping forever.
  while (next.isBefore(reference) && steps < 10000) {
    next = _advance(anchor, cycle, ++steps);
  }
  return next;
}

/// The date [steps] whole billing cycles after [anchor].
DateTime _advance(DateTime anchor, BillingCycle cycle, int steps) {
  switch (cycle) {
    case BillingCycle.weekly:
      return anchor.add(Duration(days: 7 * steps));
    case BillingCycle.monthly:
      return _addMonths(anchor, steps);
    case BillingCycle.quarterly:
      return _addMonths(anchor, 3 * steps);
    case BillingCycle.yearly:
      return _addMonths(anchor, 12 * steps);
  }
}

/// Adds [months] calendar months, clamping the day to the target month's
/// length so 31 Jan + 1 month lands on 28/29 Feb instead of rolling into March.
DateTime _addMonths(DateTime date, int months) {
  final totalMonths = date.month - 1 + months;
  final year = date.year + totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day.clamp(1, lastDay));
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

// ---------------------------------------------------------------------------
// Business costs
// ---------------------------------------------------------------------------

/// Operating-cost totals plus the revenue needed to clear them.
class BusinessEstimate {
  const BusinessEstimate({
    required this.monthlyCost,
    required this.yearlyCost,
    required this.recommendedMonthlyRevenue,
    required this.targetMargin,
  });

  final double monthlyCost;
  final double yearlyCost;

  /// Revenue required for [targetMargin] profit after covering [monthlyCost].
  final double recommendedMonthlyRevenue;

  /// Profit margin the recommendation targets, as a fraction (0.30 = 30%).
  final double targetMargin;

  double get recommendedYearlyRevenue => recommendedMonthlyRevenue * 12;
  double get monthlyProfit => recommendedMonthlyRevenue - monthlyCost;
  double get dailyRevenueTarget => recommendedMonthlyRevenue / daysPerMonth;
}

/// Totals a set of monthly operating costs and works out the revenue needed.
///
/// Revenue is `cost / (1 - margin)` — the standard markup-from-margin formula.
/// A margin of 1.0 or more has no finite solution, so it clamps below 1.
BusinessEstimate estimateBusiness({
  required Iterable<double> monthlyCosts,
  double targetMargin = 0.30,
}) {
  final monthly = monthlyCosts
      .where((cost) => cost > 0)
      .fold<double>(0, (sum, cost) => sum + cost);
  final margin = targetMargin.clamp(0.0, 0.95);

  return BusinessEstimate(
    monthlyCost: monthly,
    yearlyCost: monthly * monthsPerYear,
    recommendedMonthlyRevenue: monthly / (1 - margin),
    targetMargin: margin,
  );
}

// ---------------------------------------------------------------------------
// Savings comparison
// ---------------------------------------------------------------------------

/// The difference between a current habit and a cheaper alternative.
class SavingsComparison {
  const SavingsComparison({required this.current, required this.alternative});

  final CostBreakdown current;
  final CostBreakdown alternative;

  double get monthlySaving => current.monthly - alternative.monthly;
  double get yearlySaving => current.yearly - alternative.yearly;

  /// Share of the current cost saved, as a fraction (0.5 = 50%).
  ///
  /// Zero when there's nothing to compare against — a percentage of nothing
  /// isn't meaningful, and returning NaN would leak into the UI.
  double get percentSaved =>
      current.yearly <= 0 ? 0 : yearlySaving / current.yearly;

  /// True when the "alternative" actually costs more than the status quo.
  bool get isWorse => yearlySaving < 0;

  double savingOver(double years) => yearlySaving * years;
}

// ---------------------------------------------------------------------------
// Long-term projection
// ---------------------------------------------------------------------------

/// Cumulative spend at one point on the projection timeline.
class ProjectionPoint {
  const ProjectionPoint({required this.years, required this.cumulative});

  final double years;
  final double cumulative;
}

/// Default horizons offered by the projection screen.
const List<int> projectionHorizons = [1, 3, 5, 10];

/// Cumulative spend at each of the given [horizons].
///
/// [annualIncrease] compounds year on year (0.05 = 5% inflation). At zero the
/// series is simply linear, which is what the headline "5 years" figure
/// assumes unless the user dials inflation in.
List<ProjectionPoint> project({
  required CostBreakdown breakdown,
  List<int> horizons = projectionHorizons,
  double annualIncrease = 0,
}) {
  return horizons
      .map(
        (years) => ProjectionPoint(
          years: years.toDouble(),
          cumulative: _cumulative(breakdown.yearly, years, annualIncrease),
        ),
      )
      .toList();
}

/// Year-by-year cumulative series, for charting a smooth curve.
List<ProjectionPoint> projectSeries({
  required CostBreakdown breakdown,
  int years = 10,
  double annualIncrease = 0,
}) {
  return List.generate(years + 1, (year) {
    return ProjectionPoint(
      years: year.toDouble(),
      cumulative: _cumulative(breakdown.yearly, year, annualIncrease),
    );
  });
}

/// Sums [years] years of spending, growing the yearly figure by
/// [annualIncrease] each year.
double _cumulative(double yearly, int years, double annualIncrease) {
  if (yearly <= 0 || years <= 0) return 0;
  if (annualIncrease == 0) return yearly * years;

  var total = 0.0;
  var amount = yearly;
  for (var year = 0; year < years; year++) {
    total += amount;
    amount *= 1 + annualIncrease;
  }
  return total;
}
