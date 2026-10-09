/// Time-zone conversion: "3pm pst in ist", "what time is it in tokyo".
/// Ported from Shapeshift's timezone parser. Dart has no IANA zone database
/// offline, so each zone carries a fixed standard-time offset — conversions can
/// be an hour off during the other zone's daylight-saving period.
class Zone {
  const Zone(this.label, this.offsetMinutes);
  final String label;
  final int offsetMinutes;
}

class TimezoneData {
  const TimezoneData({required this.instant, required this.isNow, required this.from, this.to});

  /// The instant being converted, as UTC (now when no time was given).
  final DateTime instant;
  final bool isNow;
  final Zone from;
  final Zone? to;
}

/// Abbreviations and cities → zones. Offsets are standard time (see note above).
const Map<String, Zone> zones = {
  'pst': Zone('PT', -480), 'pdt': Zone('PT', -480), 'pt': Zone('PT', -480),
  'san francisco': Zone('San Francisco', -480), 'sf': Zone('San Francisco', -480),
  'los angeles': Zone('Los Angeles', -480), 'la': Zone('Los Angeles', -480),
  'seattle': Zone('Seattle', -480),
  'mst': Zone('MT', -420), 'denver': Zone('Denver', -420),
  'cst': Zone('CT', -360), 'chicago': Zone('Chicago', -360),
  'est': Zone('ET', -300), 'edt': Zone('ET', -300), 'et': Zone('ET', -300),
  'new york': Zone('New York', -300), 'nyc': Zone('New York', -300),
  'toronto': Zone('Toronto', -300),
  'utc': Zone('UTC', 0), 'gmt': Zone('GMT', 0), 'london': Zone('London', 0), 'bst': Zone('London', 0),
  'cet': Zone('CET', 60), 'paris': Zone('Paris', 60), 'berlin': Zone('Berlin', 60), 'amsterdam': Zone('Amsterdam', 60),
  'dubai': Zone('Dubai', 240),
  'ist': Zone('IST', 330), 'india': Zone('India', 330), 'mumbai': Zone('Mumbai', 330),
  'delhi': Zone('Delhi', 330), 'bangalore': Zone('Bangalore', 330), 'bengaluru': Zone('Bengaluru', 330),
  'singapore': Zone('Singapore', 480), 'sgt': Zone('Singapore', 480), 'hong kong': Zone('Hong Kong', 480),
  'tokyo': Zone('Tokyo', 540), 'jst': Zone('Tokyo', 540), 'seoul': Zone('Seoul', 540),
  'sydney': Zone('Sydney', 600), 'aest': Zone('Sydney', 600),
  'auckland': Zone('Auckland', 720),
};

final RegExp _zoneRe = RegExp(
  '\\b(${(zones.keys.toList()..sort((a, b) => b.length.compareTo(a.length))).join('|')})\\b',
  caseSensitive: false,
);

Zone localZone() => Zone('Local', DateTime.now().timeZoneOffset.inMinutes);

/// The instant (UTC) when the wall clock in [zone] reads [h]:[m] on the zone's
/// current date.
DateTime wallTimeToInstant(Zone zone, int h, int m, DateTime ref) {
  final zoneNow = ref.toUtc().add(Duration(minutes: zone.offsetMinutes));
  final wall = DateTime.utc(zoneNow.year, zoneNow.month, zoneNow.day, h, m);
  return wall.subtract(Duration(minutes: zone.offsetMinutes));
}

String formatIn(Zone zone, DateTime instant) {
  final wall = instant.toUtc().add(Duration(minutes: zone.offsetMinutes));
  final hour24 = wall.hour;
  final ampm = hour24 < 12 ? 'AM' : 'PM';
  var h = hour24 % 12;
  if (h == 0) h = 12;
  final mm = wall.minute.toString().padLeft(2, '0');
  return '$h:$mm $ampm';
}

/// −1, 0 or +1: which day the target sees relative to the source.
int dayShift(Zone from, Zone to, DateTime instant) {
  final a = instant.toUtc().add(Duration(minutes: from.offsetMinutes));
  final b = instant.toUtc().add(Duration(minutes: to.offsetMinutes));
  final da = DateTime.utc(a.year, a.month, a.day);
  final db = DateTime.utc(b.year, b.month, b.day);
  return db.compareTo(da).sign;
}

TimezoneData parseTimezone(String text, [DateTime? ref]) {
  final now = ref ?? DateTime.now();
  final t = text.toLowerCase();
  final hits = _zoneRe
      .allMatches(t)
      .map((m) => (zone: zones[m.group(1)!]!, index: m.start))
      .toList();

  final time = RegExp(
    r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b|\b(\d{1,2}):(\d{2})\b|\b(noon|midnight)\b',
  ).firstMatch(t);
  List<int>? hm;
  if (time != null) {
    if (time.group(6) != null) {
      hm = time.group(6) == 'noon' ? [12, 0] : [0, 0];
    } else if (time.group(3) != null) {
      var h = int.parse(time.group(1)!) % 12;
      if (time.group(3) == 'pm') h += 12;
      hm = [h, int.parse(time.group(2) ?? '0')];
    } else {
      hm = [int.parse(time.group(4)!), int.parse(time.group(5)!)];
    }
  }

  Zone from;
  Zone? to;
  if (hits.length >= 2) {
    from = hits[0].zone;
    to = hits[1].zone;
  } else if (hits.length == 1) {
    final before = t.substring(0, hits[0].index).trimRight();
    final isTarget = RegExp(r'\b(?:in|to|into|for|at)$').hasMatch(before) || hm == null;
    from = isTarget ? localZone() : hits[0].zone;
    to = isTarget ? hits[0].zone : localZone();
  } else {
    from = localZone();
    to = null;
  }

  final instant = hm != null ? wallTimeToInstant(from, hm[0], hm[1], now) : now.toUtc();
  return TimezoneData(instant: instant, isNow: hm == null, from: from, to: to);
}

double completeTimezone(TimezoneData d) => (d.to != null ? 0.7 : 0) + (d.isNow ? 0.1 : 0.3);

String summaryTimezone(TimezoneData d) => d.to != null
    ? '${formatIn(d.from, d.instant)} ${d.from.label} → ${formatIn(d.to!, d.instant)} ${d.to!.label}'
    : 'Time zones';
