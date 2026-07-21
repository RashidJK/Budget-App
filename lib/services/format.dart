import 'package:intl/intl.dart';

/// Currency and number formatting for Tanzanian Shillings.
///
/// TSh has no practically-used subunit, so amounts are always whole numbers —
/// showing ".00" everywhere would be noise.
class Money {
  const Money._();

  static final NumberFormat _plain = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _oneDecimal = NumberFormat('#,##0.0', 'en_US');

  static const String symbol = 'TSh';

  /// Full precision with a thousands separator: `TSh 1,825,000`.
  static String format(double amount) {
    if (!amount.isFinite) return '$symbol 0';
    return '$symbol ${_plain.format(amount.round())}';
  }

  /// Bare number, no currency symbol.
  static String number(double amount) {
    if (!amount.isFinite) return '0';
    return _plain.format(amount.round());
  }

  /// Abbreviated for headlines and chart axes: `TSh 1.8M`.
  ///
  /// Long-range projections reach eight or nine digits, which overflows a
  /// phone-width card and is harder to read than "9.1M" anyway.
  static String compact(double amount) {
    if (!amount.isFinite) return '$symbol 0';

    final value = amount.abs();
    final sign = amount < 0 ? '-' : '';

    if (value >= 1000000000) {
      return '$sign$symbol ${_trim(value / 1000000000)}B';
    }
    if (value >= 1000000) {
      return '$sign$symbol ${_trim(value / 1000000)}M';
    }
    if (value >= 100000) {
      return '$sign$symbol ${_trim(value / 1000)}K';
    }
    return '$sign$symbol ${_plain.format(value.round())}';
  }

  /// Abbreviated with no currency symbol: `1.8M`.
  ///
  /// For chart axes, where repeating "TSh" on every tick is redundant ink —
  /// the card title and the tooltip already establish the unit.
  static String compactNumber(double amount) {
    if (!amount.isFinite) return '0';

    final value = amount.abs();
    final sign = amount < 0 ? '-' : '';

    if (value >= 1000000000) return '$sign${_trim(value / 1000000000)}B';
    if (value >= 1000000) return '$sign${_trim(value / 1000000)}M';
    if (value >= 10000) return '$sign${_trim(value / 1000)}K';
    return '$sign${_plain.format(value.round())}';
  }

  /// Compact form written out in words, for insight sentences where
  /// "1.8 million" reads more naturally than "1.8M".
  static String spoken(double amount) {
    final value = amount.abs();
    if (value >= 1000000000) {
      return '$symbol ${_trim(value / 1000000000)} billion';
    }
    if (value >= 1000000) {
      return '$symbol ${_trim(value / 1000000)} million';
    }
    return format(amount);
  }

  /// Litres, to one decimal place.
  static String litres(double value) {
    if (!value.isFinite) return '0 L';
    return '${_oneDecimal.format(value)} L';
  }

  static String percent(double fraction) {
    if (!fraction.isFinite) return '0%';
    return '${(fraction * 100).round()}%';
  }

  /// Drops a trailing ".0" so "5.0M" reads as "5M".
  static String _trim(double value) {
    final text = _oneDecimal.format(value);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }
}

/// Date formatting used across the tracker and the subscription planner.
class Dates {
  const Dates._();

  static final DateFormat _day = DateFormat('d MMM yyyy');
  static final DateFormat _shortDay = DateFormat('d MMM');
  static final DateFormat _month = DateFormat('MMMM yyyy');

  static String full(DateTime date) => _day.format(date);
  static String short(DateTime date) => _shortDay.format(date);
  static String month(DateTime date) => _month.format(date);

  /// "Today" / "Yesterday" / "in 3 days" — friendlier than a bare date for
  /// the things the user is looking at most often.
  static String relative(DateTime date, {DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    final target = _dateOnly(date);
    final days = target.difference(today).inDays;

    return switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      > 1 && <= 30 => 'in $days days',
      < -1 && >= -30 => '${-days} days ago',
      _ => _day.format(date),
    };
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
