import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/category.dart';
import '../planner/engine.dart';
import '../services/format.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Shared mark specs, applied to every chart so they read as one system.
///
/// Bars stay thin and never fill their slot, lines are 2px, end markers are at
/// least 8px across, and gridlines are a solid hairline one step off the
/// surface. The data is the only thing allowed to be loud.
class _Marks {
  static const double barWidth = 18;
  static const double lineWidth = 2;
  static const double markerRadius = 4.5;
  static const Radius barCap = Radius.circular(4);
}

/// Daily spending over the last fortnight.
///
/// A single series, so there is no legend — the card title says what is
/// plotted. The peak is reported as text in the card header rather than as a
/// pinned tooltip: fl_chart draws tooltips in an overlay that ignores the
/// card's bounds, so a pinned one on a tall bar rides up over the title.
/// Per-value labels stay off; the axis and the touch tooltip carry the rest.
class DailySpendChart extends StatelessWidget {
  const DailySpendChart({super.key, required this.days});

  final List<DayTotal> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    final maxValue = days
        .map((day) => day.total)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final headroom = maxValue <= 0 ? 1000.0 : maxValue * 1.25;
    final color = context.scheme.primary;

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: headroom,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => context.isDark
                  ? const Color(0xFF33332F)
                  : const Color(0xFF1A1A19),
              tooltipBorderRadius: BorderRadius.circular(10),
              getTooltipItem: (group, _, rod, _) {
                final day = days[group.x];
                return BarTooltipItem(
                  '${Dates.short(day.day)}\n',
                  TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    TextSpan(
                      text: Money.format(day.total),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: headroom / 3,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: context.hairline, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, _) {
                  final index = value.toInt();
                  if (index < 0 || index >= days.length) {
                    return const SizedBox.shrink();
                  }
                  // Label every third day, counted back from the most recent
                  // one. Anchoring at the end keeps today labelled and the
                  // gaps even; counting forward and then forcing the last
                  // label can leave two ticks adjacent, and they overprint.
                  if ((days.length - 1 - index) % 3 != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      Dates.short(days[index].day),
                      style: TextStyle(color: context.muted, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var index = 0; index < days.length; index++)
              BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: days[index].total,
                    width: _Marks.barWidth,
                    color: days[index].total > 0
                        ? color
                        : color.withValues(alpha: 0.16),
                    borderRadius: const BorderRadius.vertical(
                      top: _Marks.barCap,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Spend per month over the last several months.
///
/// A single series with the current month highlighted, so "how am I tracking
/// versus recent months" reads at a glance. Labels stay off the bars; the
/// current month is called out by colour and the axis carries the months.
class MonthlyTrendChart extends StatelessWidget {
  const MonthlyTrendChart({super.key, required this.months});

  final List<MonthTotal> months;

  static final DateFormat _short = DateFormat('MMM');

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) return const SizedBox.shrink();

    final maxValue = months
        .map((month) => month.total)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final headroom = maxValue <= 0 ? 1000.0 : maxValue * 1.25;
    final color = context.scheme.primary;

    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          maxY: headroom,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => context.isDark
                  ? const Color(0xFF33332F)
                  : const Color(0xFF1A1A19),
              tooltipBorderRadius: BorderRadius.circular(10),
              getTooltipItem: (group, _, rod, _) {
                final month = months[group.x];
                return BarTooltipItem(
                  '${_short.format(month.month)}\n',
                  TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    TextSpan(
                      text: Money.format(month.total),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: headroom / 3,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: context.hairline, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, _) {
                  final index = value.toInt();
                  if (index < 0 || index >= months.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _short.format(months[index].month),
                      style: TextStyle(color: context.muted, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var index = 0; index < months.length; index++)
              BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: months[index].total,
                    width: 22,
                    // The latest month is the one you're influencing now, so
                    // it stays full-strength; earlier months recede.
                    color: index == months.length - 1
                        ? color
                        : color.withValues(alpha: context.isDark ? 0.5 : 0.32),
                    borderRadius: const BorderRadius.vertical(
                      top: _Marks.barCap,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Category breakdown as direct-labelled proportional bars.
///
/// Chosen over a pie or donut deliberately: every row carries its category
/// name and amount as text, so identity never rests on colour alone. Three of
/// the eight category hues sit below 3:1 contrast on a light surface, and
/// visible labels are exactly the relief that requires.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({super.key, required this.totals, this.maxRows = 6});

  final List<CategoryTotal> totals;

  /// Rows beyond this fold into a single "Other" row, so the chart never
  /// exceeds the palette's capacity.
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const SizedBox.shrink();

    final rows = _folded(context);
    final largest = rows.first.total;
    final grandTotal = rows.fold<double>(0, (sum, row) => sum + row.total);

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _BreakdownRow(
              total: row,
              share: grandTotal <= 0 ? 0 : row.total / grandTotal,
              fill: largest <= 0 ? 0 : row.total / largest,
            ),
          ),
      ],
    );
  }

  /// Keeps the top [maxRows] categories and merges the tail into "Other".
  List<CategoryTotal> _folded(BuildContext context) {
    if (totals.length <= maxRows) return totals;

    final kept = totals.take(maxRows - 1).toList();
    final tail = totals.skip(maxRows - 1);
    final tailTotal = tail.fold<double>(0, (sum, row) => sum + row.total);

    return [
      ...kept,
      CategoryTotal(category: ExpenseCategory.unknown, total: tailTotal),
    ];
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.total,
    required this.share,
    required this.fill,
  });

  final CategoryTotal total;
  final double share;
  final double fill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = total.category.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(total.category.icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                total.category.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              Money.format(total.total),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 38,
              child: Text(
                Money.percent(share),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fill.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: context.hairline,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cumulative spend across a projection horizon.
///
/// One series: a 2px line over a 10% wash, with the endpoint marked and
/// labelled. Intermediate years stay unlabelled and are carried by the axis
/// and the tooltip.
class ProjectionChart extends StatelessWidget {
  const ProjectionChart({super.key, required this.points, required this.color});

  final List<ProjectionPoint> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();

    final maxValue = points.last.cumulative;
    final surface = context.isDark ? const Color(0xFF232322) : Colors.white;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: points.first.years,
          maxX: points.last.years,
          minY: 0,
          maxY: maxValue <= 0 ? 1000 : maxValue * 1.15,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => context.isDark
                  ? const Color(0xFF33332F)
                  : const Color(0xFF1A1A19),
              tooltipBorderRadius: BorderRadius.circular(10),
              getTooltipItems: (spots) => spots.map((spot) {
                final years = spot.x.round();
                return LineTooltipItem(
                  '$years ${years == 1 ? 'year' : 'years'}\n',
                  TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    TextSpan(
                      text: Money.format(spot.y),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxValue <= 0 ? 1000 : maxValue / 3,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: context.hairline, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                interval: maxValue <= 0 ? 1000 : maxValue / 3,
                // Bare numbers, no currency symbol: repeating "TSh" on every
                // tick wraps the label onto two lines and adds nothing the
                // card title doesn't already say.
                getTitlesWidget: (value, _) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    Money.compactNumber(value),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: TextStyle(color: context.muted, fontSize: 10),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (value, _) {
                  final years = value.round();
                  if (years == 0 || years % 2 != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${years}y',
                      style: TextStyle(color: context.muted, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final point in points)
                  FlSpot(point.years, point.cumulative),
              ],
              isCurved: true,
              curveSmoothness: 0.2,
              preventCurveOverShooting: true,
              color: color,
              barWidth: _Marks.lineWidth,
              isStrokeCapRound: true,
              dotData: FlDotData(
                // Only the endpoint carries a marker — the figure the user is
                // actually reading. It gets a ring in the surface colour so it
                // stays legible where it crosses the line and the grid.
                show: true,
                checkToShowDot: (spot, _) => spot.x == points.last.years,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: _Marks.markerRadius,
                  color: color,
                  strokeWidth: 2,
                  strokeColor: surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two-series comparison used by the Savings Simulator.
///
/// Two series means a legend is mandatory, and each bar is also labelled with
/// its value — identity is carried by text as well as hue.
class ComparisonBars extends StatelessWidget {
  const ComparisonBars({
    super.key,
    required this.currentLabel,
    required this.currentValue,
    required this.alternativeLabel,
    required this.alternativeValue,
  });

  final String currentLabel;
  final double currentValue;
  final String alternativeLabel;
  final double alternativeValue;

  @override
  Widget build(BuildContext context) {
    final largest = currentValue > alternativeValue
        ? currentValue
        : alternativeValue;

    return Column(
      children: [
        _ComparisonBar(
          label: currentLabel,
          value: currentValue,
          fill: largest <= 0 ? 0 : currentValue / largest,
          color: context.warn,
        ),
        const SizedBox(height: 16),
        _ComparisonBar(
          label: alternativeLabel,
          value: alternativeValue,
          fill: largest <= 0 ? 0 : alternativeValue / largest,
          color: context.good,
        ),
      ],
    );
  }
}

class _ComparisonBar extends StatelessWidget {
  const _ComparisonBar({
    required this.label,
    required this.value,
    required this.fill,
    required this.color,
  });

  final String label;
  final double value;
  final double fill;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              Money.format(value),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fill.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, animated, _) => LinearProgressIndicator(
              value: animated,
              minHeight: 10,
              backgroundColor: context.hairline,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}
