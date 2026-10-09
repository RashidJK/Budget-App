import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme.dart';
import '../parse/calc.dart';
import '../parse/cards.dart';
import '../parse/color.dart';
import '../parse/common.dart';
import '../parse/convert.dart';
import '../parse/random.dart';
import '../parse/timezone.dart';
import '../shift_format.dart';
import '../shift_intent.dart';
import '../shift_signals.dart';
import 'shift_card_kit.dart';

/// Build the live preview card for a committed/ghost [intent] and its parsed
/// [data]. [interactive] is false while it's a faint ghost preview.
Widget buildShiftCard(
  BuildContext context,
  ShiftIntent intent,
  dynamic data,
  GatedSignals g, {
  bool interactive = true,
  DateTime? now,
}) {
  final accent = intent.accent;
  final body = _body(context, intent, data, g, interactive, now ?? DateTime.now());
  return ShiftShell(
    accent: accent,
    icon: _headerIcon(intent, g),
    label: _headerLabel(intent, g),
    badges: _badges(intent, g),
    edge: _edge(context, intent, g),
    child: body,
  );
}

// ---- header variants -------------------------------------------------------

String _toneLabel(String tone) => switch (tone) {
  'positive' => 'Upbeat note',
  'excited' => 'Excited note',
  'stressed' => 'Stressed note',
  'reflective' => 'Reflective note',
  _ => 'Note',
};

String _headerLabel(ShiftIntent i, GatedSignals g) => switch (i) {
  ShiftIntent.todo => g.isShoppingList ? 'Shopping' : 'Checklist',
  ShiftIntent.timer => switch (g.timerKind) {
    'focus' => 'Focus',
    'break' => 'Break',
    'stopwatch' => 'Stopwatch',
    _ => 'Timer',
  },
  ShiftIntent.note => g.tone != null ? _toneLabel(g.tone!) : 'Note',
  _ => i.label,
};

IconData _categoryIcon(String? c) => switch (c) {
  'food' => Icons.restaurant_rounded,
  'transport' => Icons.directions_car_rounded,
  'shopping' => Icons.shopping_bag_outlined,
  'bills' => Icons.receipt_long_outlined,
  'entertainment' => Icons.movie_outlined,
  'health' => Icons.favorite_border_rounded,
  _ => Icons.account_balance_wallet_outlined,
};

IconData _transportIcon(String? t) => switch (t) {
  'train' => Icons.train_rounded,
  'bus' => Icons.directions_bus_rounded,
  'car' => Icons.directions_car_rounded,
  _ => Icons.flight_takeoff_rounded,
};

IconData _headerIcon(ShiftIntent i, GatedSignals g) => switch (i) {
  ShiftIntent.todo => g.isShoppingList ? Icons.shopping_cart_outlined : Icons.checklist_rounded,
  ShiftIntent.timer => switch (g.timerKind) {
    'focus' => Icons.center_focus_strong_outlined,
    'break' => Icons.free_breakfast_outlined,
    _ => Icons.timer_outlined,
  },
  ShiftIntent.expense => _categoryIcon(g.expenseCategory),
  ShiftIntent.travel => _transportIcon(g.transport),
  _ => i.icon,
};

Color? _edge(BuildContext context, ShiftIntent i, GatedSignals g) => switch (i) {
  ShiftIntent.reminder => g.urgent ? context.caution : null,
  ShiftIntent.note => switch (g.tone) {
    'positive' => context.good,
    'excited' => i.accent,
    'stressed' => context.caution,
    'reflective' => context.muted,
    _ => null,
  },
  _ => null,
};

List<ShiftBadge> _badges(ShiftIntent i, GatedSignals g) => switch (i) {
  ShiftIntent.reminder => [
    if (g.urgent) const ShiftBadge(Icons.priority_high_rounded, 'Urgent', caution: true),
    if (g.recurring) const ShiftBadge(Icons.repeat_rounded, 'Repeats'),
  ],
  ShiftIntent.todo => [
    if (g.urgent) const ShiftBadge(Icons.priority_high_rounded, 'Urgent', caution: true),
  ],
  ShiftIntent.event => [
    if (g.recurring) const ShiftBadge(Icons.repeat_rounded, 'Repeats'),
  ],
  ShiftIntent.travel => switch (g.tripType) {
    'work' => [const ShiftBadge(Icons.work_outline_rounded, 'Work')],
    'leisure' => [const ShiftBadge(Icons.wb_sunny_outlined, 'Leisure')],
    _ => const [],
  },
  _ => const [],
};

// ---- bodies ----------------------------------------------------------------

Widget _body(BuildContext context, ShiftIntent intent, dynamic data, GatedSignals g, bool interactive, DateTime now) {
  final accent = intent.accent;
  switch (intent) {
    case ShiftIntent.event:
      final d = data as EventData;
      final extras = [
        for (final p in d.people) ShiftChip(Icons.person_outline_rounded, p),
        if (d.location != null) ShiftChip(Icons.place_outlined, d.location!),
        if (d.link != null) ShiftChip(Icons.videocam_outlined, d.link!, color: accent),
      ];
      return _titled(context, d.title.isEmpty ? 'Untitled event' : d.title, [
        if (d.date != null) ShiftChip(Icons.schedule_rounded, formatWhenLine(d.date!, d.hasTime, now: now), color: accent),
        ...extras,
      ]);

    case ShiftIntent.reminder:
      final d = data as ReminderData;
      return _titled(context, d.task.isEmpty ? 'Reminder' : d.task, [
        if (d.when != null) ShiftChip(Icons.schedule_rounded, formatWhenLine(d.when!, d.hasTime, now: now), color: accent),
      ]);

    case ShiftIntent.todo:
      final d = data as TodoData;
      if (d.items.isEmpty) return _placeholder(context, 'Add items, comma separated…');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final it in d.items.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(Icons.check_box_outline_blank_rounded, size: 18, color: context.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(it, style: const TextStyle(fontSize: 14))),
              ]),
            ),
          if (d.items.length > 6)
            Text('+${d.items.length - 6} more', style: TextStyle(fontSize: 12.5, color: context.muted)),
        ],
      );

    case ShiftIntent.timer:
      final d = data as TimerData;
      return Row(children: [
        Text(
          d.seconds != null ? formatClock(d.seconds!) : '––:––',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: accent, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        const SizedBox(width: 12),
        if (d.label.isNotEmpty)
          Expanded(child: Text(d.label, style: TextStyle(fontSize: 14, color: context.muted))),
      ]);

    case ShiftIntent.habit:
      final d = data as HabitData;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(d.title.isEmpty ? 'Habit' : d.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _WeekStrip(days: d.days, accent: accent),
          if (d.label != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(d.label!, style: TextStyle(fontSize: 12.5, color: context.muted)),
          ),
        ],
      );

    case ShiftIntent.color:
      return _ColorBody(data as ColorData, accent: accent, interactive: interactive);

    case ShiftIntent.split:
      final d = data as SplitData;
      if (d.total == null || d.people == null) return _placeholder(context, 'e.g. split 2400 between 3');
      return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _big(formatAmount(d.total! / d.people!, d.currency), accent),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('each', style: TextStyle(fontSize: 13, color: context.muted)),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('${formatAmount(d.total!, d.currency)} ÷ ${d.people}', style: TextStyle(fontSize: 12.5, color: context.muted)),
        ),
      ]);

    case ShiftIntent.expense:
      final d = data as ExpenseData;
      return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _big(d.amount != null ? formatAmount(d.amount!, d.currency) : '—', accent),
        const SizedBox(width: 12),
        if (d.item.isNotEmpty)
          Expanded(child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(d.item, textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          )),
      ]);

    case ShiftIntent.convert:
      final d = data as ConvertData;
      if (d.result == null) return _placeholder(context, 'e.g. 5 miles in km');
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text('${_trim(d.value!)} ${unitLabels[d.from] ?? d.from}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('=', style: TextStyle(fontSize: 16, color: context.muted))),
        Expanded(child: _big('${_trim(d.result!)} ${unitLabels[d.to] ?? d.to}', accent, size: 22)),
      ]);

    case ShiftIntent.calc:
      final d = data as CalcData;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(d.expression, style: TextStyle(fontSize: 14, color: context.muted)),
        if (d.result != null) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _big('= ${formatPlainNumber(d.result!)}', accent),
        ),
      ]);

    case ShiftIntent.travel:
      final d = data as TravelData;
      return _titled(context, d.destination != null ? 'Trip to ${d.destination}' : 'Trip', [
        if (d.start != null)
          ShiftChip(Icons.event_rounded, d.end != null ? '${dayLabel(d.start!, now: now)} – ${dayLabel(d.end!, now: now)}' : dayLabel(d.start!, now: now), color: accent),
        if (d.origin != null) ShiftChip(Icons.my_location_rounded, 'from ${d.origin}'),
      ]);

    case ShiftIntent.poll:
      final d = data as PollData;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (d.title.isNotEmpty) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(d.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        for (final o in d.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(Icons.radio_button_unchecked_rounded, size: 16, color: accent),
              const SizedBox(width: 8),
              Expanded(child: Text(o, style: const TextStyle(fontSize: 14))),
            ]),
          ),
      ]);

    case ShiftIntent.contact:
      final d = data as ContactData;
      return Row(children: [
        _Avatar(d.initials.isNotEmpty ? d.initials : '?', accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(d.name.isEmpty ? 'Contact' : d.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (d.phone != null) Text(d.phone!, style: TextStyle(fontSize: 13, color: context.muted)),
            if (d.email != null) Text(d.email!, style: TextStyle(fontSize: 13, color: context.muted)),
          ]),
        ),
      ]);

    case ShiftIntent.link:
      final d = data as LinkData;
      return Row(children: [
        _Avatar(d.monogram.isNotEmpty ? d.monogram : '🔗', accent, rounded: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(d.domain ?? 'Link', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (d.note.isNotEmpty) Text(d.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: context.muted)),
          ]),
        ),
      ]);

    case ShiftIntent.countdown:
      final d = data as CountdownData;
      if (d.days == null) return _placeholder(context, 'e.g. days until christmas');
      final abs = d.days!.abs();
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text('$abs', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: accent, height: 1)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(d.days == 0 ? 'today' : 'day${abs == 1 ? '' : 's'} ${d.days! < 0 ? 'since' : 'until'}', style: TextStyle(fontSize: 12.5, color: context.muted)),
            Text(d.title.isEmpty ? 'then' : d.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]);

    case ShiftIntent.timezone:
      final d = data as TimezoneData;
      if (d.to == null) return _placeholder(context, 'e.g. 3pm pst in ist');
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _zoneRow(context, formatIn(d.from, d.instant), d.from.label, accent, from: true),
        Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Icon(Icons.south_rounded, size: 16, color: context.muted)),
        _zoneRow(context, formatIn(d.to!, d.instant), d.to!.label, accent, from: false),
      ]);

    case ShiftIntent.random:
      return _RandomBody(data as RandomData, accent: accent, interactive: interactive);

    case ShiftIntent.goal:
      final d = data as GoalData;
      final pct = d.target != null && d.target! > 0 ? (d.current / d.target!).clamp(0.0, 1.0) : 0.0;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(d.title.isEmpty ? 'Goal' : d.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: pct, minHeight: 8, backgroundColor: context.hairline, color: accent),
        ),
        const SizedBox(height: 6),
        Text(
          d.target != null ? '${_num(d.current)} / ${_num(d.target!)}${d.unit != null ? ' ${d.unit}' : ''}' : 'Set a target',
          style: TextStyle(fontSize: 12.5, color: context.muted),
        ),
      ]);

    case ShiftIntent.note:
      final d = data as NoteData;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(d.title.isEmpty ? 'Note' : d.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.3)),
        if (d.body.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(d.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: context.muted, height: 1.4)),
        ),
      ]);

    case ShiftIntent.none:
      return const SizedBox.shrink();
  }
}

// ---- shared body pieces ----------------------------------------------------

Widget _titled(BuildContext context, String title, List<Widget> chips) {
  final visible = chips.whereType<Widget>().toList();
  return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.3)),
    if (visible.isNotEmpty) Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: visible),
    ),
  ]);
}

Widget _placeholder(BuildContext context, String hint) =>
    Text(hint, style: TextStyle(fontSize: 13.5, color: context.muted, fontStyle: FontStyle.italic));

Widget _big(String text, Color accent, {double size = 26}) =>
    Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: accent, height: 1.1));

String _trim(double n) {
  final r = (n * 100).round() / 100;
  return r == r.truncateToDouble() ? r.toStringAsFixed(0) : '$r';
}

String _num(double n) => n == n.truncateToDouble() ? n.toStringAsFixed(0) : '$n';

Widget _zoneRow(BuildContext context, String time, String label, Color accent, {required bool from}) => Row(children: [
  Text(time, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: from ? context.scheme.onSurface : accent)),
  const SizedBox(width: 8),
  Text(label, style: TextStyle(fontSize: 13, color: context.muted)),
]);

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days, required this.accent});
  final List<int> days; // 0 = Sun … 6 = Sat
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: days.contains(i) ? accent : context.hairline.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: days.contains(i) ? Colors.white : context.muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.text, this.accent, {this.rounded = false});
  final String text;
  final Color accent;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: rounded ? BorderRadius.circular(10) : null,
        shape: rounded ? BoxShape.rectangle : BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: accent)),
    );
  }
}

class _ColorBody extends StatefulWidget {
  const _ColorBody(this.data, {required this.accent, required this.interactive});
  final ColorData data;
  final Color accent;
  final bool interactive;

  @override
  State<_ColorBody> createState() => _ColorBodyState();
}

class _ColorBodyState extends State<_ColorBody> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final hex = widget.data.hex;
    final swatch = shiftHexColor(hex);
    if (swatch == null) return _placeholder(context, 'e.g. #ff6b35, tiffany blue, ocean');
    return Row(children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: swatch,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.hairline),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(hex!.toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
          if (widget.data.name != null) Text(capitalize(widget.data.name!), style: TextStyle(fontSize: 13, color: context.muted)),
        ]),
      ),
      if (widget.interactive)
        IconButton(
          icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18, color: _copied ? context.good : context.muted),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: hex.toUpperCase()));
            if (context.mounted) setState(() => _copied = true);
          },
        ),
    ]);
  }
}

class _RandomBody extends StatefulWidget {
  const _RandomBody(this.data, {required this.accent, required this.interactive});
  final RandomData data;
  final Color accent;
  final bool interactive;

  @override
  State<_RandomBody> createState() => _RandomBodyState();
}

class _RandomBodyState extends State<_RandomBody> {
  List<String>? _result;

  @override
  Widget build(BuildContext context) {
    final result = _result ?? rollRandom(widget.data);
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(result.join('  '), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: widget.accent, height: 1.1)),
          const SizedBox(height: 2),
          Text(describeRandom(widget.data), style: TextStyle(fontSize: 12.5, color: context.muted)),
        ]),
      ),
      if (widget.interactive)
        IconButton(
          icon: Icon(Icons.casino_outlined, color: widget.accent),
          tooltip: 'Roll again',
          onPressed: () => setState(() => _result = rollRandom(widget.data)),
        ),
    ]);
  }
}
