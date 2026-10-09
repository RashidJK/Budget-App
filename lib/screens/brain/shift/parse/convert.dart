/// Unit conversion: "5 miles in km", "72f to c", "3 kg". Ported from
/// Shapeshift's convert parser, with a small hand-rolled factor table standing
/// in for the `convert-units` package (unavailable offline). Length, mass,
/// volume, speed and temperature are covered.
class ConvertData {
  const ConvertData({this.value, this.from, this.to, this.result});
  final double? value;
  final String? from;
  final String? to;
  final double? result;
}

/// Aliases → canonical unit keys.
const Map<String, String> unitAliases = {
  'km': 'km', 'kms': 'km', 'kilometer': 'km', 'kilometers': 'km', 'kilometre': 'km', 'kilometres': 'km',
  'mi': 'mi', 'mile': 'mi', 'miles': 'mi',
  'm': 'm', 'meter': 'm', 'meters': 'm', 'metre': 'm', 'metres': 'm',
  'cm': 'cm', 'centimeter': 'cm', 'centimeters': 'cm', 'centimetre': 'cm', 'centimetres': 'cm',
  'mm': 'mm', 'millimeter': 'mm', 'millimeters': 'mm',
  'ft': 'ft', 'foot': 'ft', 'feet': 'ft',
  'in': 'in', 'inch': 'in', 'inches': 'in',
  'yd': 'yd', 'yard': 'yd', 'yards': 'yd',
  'kg': 'kg', 'kgs': 'kg', 'kilo': 'kg', 'kilos': 'kg', 'kilogram': 'kg', 'kilograms': 'kg',
  'g': 'g', 'gram': 'g', 'grams': 'g',
  'lb': 'lb', 'lbs': 'lb', 'pound': 'lb', 'pounds': 'lb',
  'oz': 'oz', 'ounce': 'oz', 'ounces': 'oz',
  'l': 'l', 'liter': 'l', 'liters': 'l', 'litre': 'l', 'litres': 'l',
  'ml': 'ml', 'milliliter': 'ml', 'milliliters': 'ml', 'millilitre': 'ml', 'millilitres': 'ml',
  'gal': 'gal', 'gallon': 'gal', 'gallons': 'gal',
  'cup': 'cup', 'cups': 'cup',
  'c': 'C', '°c': 'C', 'celsius': 'C', 'centigrade': 'C',
  'f': 'F', '°f': 'F', 'fahrenheit': 'F',
  'k': 'K', 'kelvin': 'K',
  'km/h': 'km/h', 'kmh': 'km/h', 'kph': 'km/h',
  'mph': 'm/h',
};

const Map<String, String> _defaultTarget = {
  'km': 'mi', 'mi': 'km', 'm': 'ft', 'cm': 'in', 'mm': 'in', 'ft': 'm', 'in': 'cm', 'yd': 'm',
  'kg': 'lb', 'g': 'oz', 'lb': 'kg', 'oz': 'g',
  'l': 'gal', 'ml': 'fl-oz', 'gal': 'l', 'cup': 'ml',
  'C': 'F', 'F': 'C', 'K': 'C',
  'km/h': 'm/h', 'm/h': 'km/h',
};

const Map<String, String> unitLabels = {
  'km': 'km', 'mi': 'mi', 'm': 'm', 'cm': 'cm', 'mm': 'mm', 'ft': 'ft', 'in': 'in', 'yd': 'yd',
  'kg': 'kg', 'g': 'g', 'lb': 'lb', 'oz': 'oz',
  'l': 'L', 'ml': 'mL', 'gal': 'gal', 'cup': 'cup', 'fl-oz': 'fl oz',
  'C': '°C', 'F': '°F', 'K': 'K',
  'km/h': 'km/h', 'm/h': 'mph',
};

// measure name + factor to the measure's base unit.
const Map<String, String> _measure = {
  'km': 'length', 'mi': 'length', 'm': 'length', 'cm': 'length', 'mm': 'length',
  'ft': 'length', 'in': 'length', 'yd': 'length',
  'kg': 'mass', 'g': 'mass', 'lb': 'mass', 'oz': 'mass',
  'l': 'volume', 'ml': 'volume', 'gal': 'volume', 'cup': 'volume', 'fl-oz': 'volume',
  'km/h': 'speed', 'm/h': 'speed',
};

const Map<String, double> _factor = {
  'km': 1000, 'mi': 1609.344, 'm': 1, 'cm': 0.01, 'mm': 0.001,
  'ft': 0.3048, 'in': 0.0254, 'yd': 0.9144,
  'kg': 1000, 'g': 1, 'lb': 453.59237, 'oz': 28.349523125,
  'l': 1, 'ml': 0.001, 'gal': 3.785411784, 'cup': 0.2365882365, 'fl-oz': 0.0295735295625,
  'km/h': 0.277777778, 'm/h': 0.44704,
};

double _toCelsius(double v, String u) =>
    u == 'C' ? v : (u == 'F' ? (v - 32) * 5 / 9 : v - 273.15);
double _fromCelsius(double c, String u) =>
    u == 'C' ? c : (u == 'F' ? c * 9 / 5 + 32 : c + 273.15);

const _temperature = {'C', 'F', 'K'};

List<String> unitOptions(String unit) {
  final measure = _measure[unit];
  if (measure == null) return _temperature.contains(unit) ? ['C', 'F', 'K'] : [];
  return _measure.entries
      .where((e) => e.value == measure && unitLabels.containsKey(e.key))
      .map((e) => e.key)
      .toList();
}

double? convertValue(double value, String from, String to) {
  if (_temperature.contains(from) && _temperature.contains(to)) {
    return _fromCelsius(_toCelsius(value, from), to);
  }
  final mf = _measure[from];
  final mt = _measure[to];
  if (mf == null || mt == null || mf != mt) return null;
  return value * _factor[from]! / _factor[to]!;
}

final String _unitPattern = (unitAliases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length)))
    .map((u) => u.replaceAllMapped(RegExp(r'[/.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}'))
    .join('|');

final RegExp _fullRe = RegExp(
  '(-?\\d+(?:\\.\\d+)?)\\s*($_unitPattern)\\s+(?:to|in|into|as|=|->)\\s+($_unitPattern)(?![a-z])',
  caseSensitive: false,
);
final RegExp _partRe = RegExp(
  '(-?\\d+(?:\\.\\d+)?)\\s*($_unitPattern)(?![a-z])',
  caseSensitive: false,
);

ConvertData parseConvert(String text) {
  final t = text
      .toLowerCase()
      .replaceAll(RegExp(r'degrees?\s+'), '°')
      .replaceAll(RegExp(r'°\s+'), '°');
  final full = _fullRe.firstMatch(t);
  if (full != null) {
    final value = double.parse(full.group(1)!);
    final from = unitAliases[full.group(2)!]!;
    final to = unitAliases[full.group(3)!]!;
    final result = convertValue(value, from, to);
    if (result != null) return ConvertData(value: value, from: from, to: to, result: result);
  }
  final part = _partRe.firstMatch(t);
  if (part != null) {
    final value = double.parse(part.group(1)!);
    final from = unitAliases[part.group(2)!]!;
    final to = _defaultTarget[from];
    return ConvertData(
      value: value,
      from: from,
      to: to,
      result: to != null ? convertValue(value, from, to) : null,
    );
  }
  return const ConvertData();
}

double completeConvert(ConvertData d) =>
    (d.value != null ? 0.4 : 0) + (d.from != null ? 0.3 : 0) + (d.result != null ? 0.3 : 0);

String _trim(double n) {
  final r = (n * 100).round() / 100;
  return r == r.truncateToDouble() ? r.toStringAsFixed(0) : '$r';
}

String summaryConvert(ConvertData d) {
  if (d.value != null && d.from != null && d.to != null && d.result != null) {
    return '${_trim(d.value!)} ${unitLabels[d.from] ?? d.from} = '
        '${_trim(d.result!)} ${unitLabels[d.to] ?? d.to}';
  }
  return 'Conversion';
}
