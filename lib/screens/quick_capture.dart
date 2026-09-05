import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';

import '../command/command_bar.dart';
import '../command/command_parser.dart';
import '../models/activity.dart';
import '../services/format.dart';
import '../state/app_state.dart';

/// Capture the nav bar's inline prompt. Parses [text] with the same NL parser
/// as the command bar and records it straight away, with an Undo snackbar —
/// capture-first (spec §4), without leaving the bar.
///
/// Anything that isn't a plain record (a question, a plan) hands off to the full
/// command bar so those flows still work. Returns true when handled, so the bar
/// can close its prompt.
Future<bool> captureFromText(BuildContext context, String text) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;

  final state = context.read<AppState>();
  final parsed = CommandParser(state.parseContext()).parse(trimmed);
  final activity = parsed.activity;

  if (parsed.kind != CommandKind.create || activity == null) {
    // Not a straight record — let the full command bar handle it.
    CommandBar.show(context, initialText: trimmed);
    return true;
  }

  final result = await state.capture(
    activity,
    source: ActivitySource.command,
    confidence: parsed.confidence,
  );
  if (!context.mounted) return true;

  HapticFeedback.lightImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(_summaryFor(activity)),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => state.undoCapture(result),
        ),
      ),
    );
  return true;
}

/// A one-line confirmation of what just landed, e.g. "Added Lunch · −TSh 5,000".
String _summaryFor(ParsedActivity activity) {
  final money = Money.format(activity.amount);
  final label = activity.description.isNotEmpty
      ? activity.description
      : activity.type.label;
  return switch (activity.type) {
    ActivityType.income ||
    ActivityType.loanIn ||
    ActivityType.receivableRepayment => 'Added $label · +$money',
    ActivityType.transfer => 'Transferred $money',
    _ => 'Added $label · −$money',
  };
}
