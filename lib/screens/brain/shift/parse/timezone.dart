import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Time-zone conversion: "3pm pst in ist", "what time is it in tokyo".
///
/// Ported from Shapeshift's timezone parser, now DST-aware: each named zone maps
/// to an IANA location and conversions use the `timezone` database, so a time is
/// correct year-round rather than pinned to a standard-time offset. The device's
/// own zone stays as `local` — the OS already applies its DST.

bool _tzReady = false;

/// Load the IANA database once. Idempotent and cheap after the first call, so
/// the parser can call it lazily and nothing else has to initialise anything.
void ensureTimeZonesLoaded() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

/// A named zone. [location] is an IANA name (e.g. 'America/Los_Angeles'); null
/// means the device's local zone, whose DST the OS handles.
class Zone {
  const Zone(this.label, this.location);
  final String label;
  final String? location;

  bool get isLocal => location == null;
}

class TimezoneData {
  const TimezoneData({
    required this.instant,
    required this.isNow,
    required this.from,
    this.to,
  });

  /// The instant being converted, as UTC (now when no time was given).
  final DateTime instant;
  final bool isNow;
  final Zone from;
  final Zone? to;
}

/// Abbreviations and cities → zones, now by IANA location (DST handled).
const Map<String, Zone> zones = {
  'pst': Zone('PT', 'America/Los_Angeles'),
  'pdt': Zone('PT', 'America/Los_Angeles'),
  'pt': Zone('PT', 'America/Los_Angeles'),
  'san francisco': Zone('San Francisco', 'America/Los_Angeles'),
  'sf': Zone('San Francisco', 'America/Los_Angeles'),
  'los angeles': Zone('Los Angeles', 'America/Los_Angeles'),
  'la': Zone('Los Angeles', 'America/Los_Angeles'),
  'seattle': Zone('Seattle', 'America/Los_Angeles'),
  'mst': Zone('MT', 'America/Denver'),
  'denver': Zone('Denver', 'America/Denver'),
  'cst': Zone('CT', 'America/Chicago'),
  'chicago': Zone('Chicago', 'America/Chicago'),
  'est': Zone('ET', 'America/New_York'),
  'edt': Zone('ET', 'America/New_York'),
  'et': Zone('ET', 'America/New_York'),
  'new york': Zone('New York', 'America/New_York'),
  'nyc': Zone('New York', 'America/New_York'),
  'toronto': Zone('Toronto', 'America/Toronto'),
  'utc': Zone('UTC', 'UTC'),
  'gmt': Zone('GMT', 'UTC'),
  'london': Zone('London', 'Europe/London'),
  'bst': Zone('London', 'Europe/London'),
  'cet': Zone('CET', 'Europe/Paris'),
  'paris': Zone('Paris', 'Europe/Paris'),
  'berlin': Zone('Berlin', 'Europe/Berlin'),
  'amsterdam': Zone('Amsterdam', 'Europe/Amsterdam'),
  'dubai': Zone('Dubai', 'Asia/Dubai'),
  'ist': Zone('IST', 'Asia/Kolkata'),
  'india': Zone('India', 'Asia/Kolkata'),
  'mumbai': Zone('Mumbai', 'Asia/Kolkata'),
  'delhi': Zone('Delhi', 'Asia/Kolkata'),
  'bangalore': Zone('Bangalore', 'Asia/Kolkata'),
  'bengaluru': Zone('Bengaluru', 'Asia/Kolkata'),
  'singapore': Zone('Singapore', 'Asia/Singapore'),
  'sgt': Zone('Singapore', 'Asia/Singapore'),
  'hong kong': Zone('Hong Kong', 'Asia/Hong_Kong'),
  'tokyo': Zone('Tokyo', 'Asia/Tokyo'),
  'jst': Zone('Tokyo', 'Asia/Tokyo'),
  'seoul': Zone('Seoul', 'Asia/Seoul'),
  'sydney': Zone('Sydney', 'Australia/Sydney'),
  'aest': Zone('Sydney', 'Australia/Sydney'),
  'auckland': Zone('Auckland', 'Pacific/Auckland'),
};

final RegExp _zoneRe = RegExp(
  '\\b(${(zones.keys.toList()..sort((a, b) => b.length.compareTo(a.length))).join('|')})\\b',
  caseSensitive: false,
);

Zone localZone() => const Zone('Local', null);

/// The wall clock in [zone], as a DST-aware DateTime, for [instant].
DateTime _wallClock(Zone zone, DateTime instant) {
  if (zone.isLocal) return instant.toLocal();
  ensureTimeZonesLoaded();
  return tz.TZDateTime.from(instant, tz.getLocation(zone.location!));
}

/// The instant (UTC) when the wall clock in [zone] reads [h]:[m] on the zone's
/// current date — the date resolved in that zone, with its DST offset applied.
DateTime wallTimeToInstant(Zone zone, int h, int m, DateTime ref) {
  if (zone.isLocal) {
    final here = ref.toLocal();
    return DateTime(here.year, here.month, here.day, h, m).toUtc();
  }
  ensureTimeZonesLoaded();
  final loc = tz.getLocation(zone.location!);
  final there = tz.TZDateTime.from(ref, loc);
  return tz.TZDateTime(loc, there.year, there.month, there.day, h, m).toUtc();
}

String formatIn(Zone zone, DateTime instant) {
  final wall = _wallClock(zone, instant);
  final hour24 = wall.hour;
  final ampm = hour24 < 12 ? 'AM' : 'PM';
  var h = hour24 % 12;
  if (h == 0) h = 12;
  final mm = wall.minute.toString().padLeft(2, '0');
  return '$h:$mm $ampm';
}

/// −1, 0 or +1: which day the target sees relative to the source.
int dayShift(Zone from, Zone to, DateTime instant) {
  final a = _wallClock(from, instant);
  final b = _wallClock(to, instant);
  final da = DateTime(a.year, a.month, a.day);
  final db = DateTime(b.year, b.month, b.day);
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
    final isTarget =
        RegExp(r'\b(?:in|to|into|for|at)$').hasMatch(before) || hm == null;
    from = isTarget ? localZone() : hits[0].zone;
    to = isTarget ? hits[0].zone : localZone();
  } else {
    from = localZone();
    to = null;
  }

  final instant = hm != null
      ? wallTimeToInstant(from, hm[0], hm[1], now)
      : now.toUtc();
  return TimezoneData(instant: instant, isNow: hm == null, from: from, to: to);
}

double completeTimezone(TimezoneData d) =>
    (d.to != null ? 0.7 : 0) + (d.isNow ? 0.1 : 0.3);

String summaryTimezone(TimezoneData d) => d.to != null
    ? '${formatIn(d.from, d.instant)} ${d.from.label} → ${formatIn(d.to!, d.instant)} ${d.to!.label}'
    : 'Time zones';
