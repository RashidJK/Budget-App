import 'package:flutter/widgets.dart';

import 'cards/shift_cards.dart';
import 'shift_classifier.dart';
import 'shift_intent.dart';
import 'shift_registry.dart';
import 'shift_signals.dart';

/// Which captured cards can be re-rendered from their source text alone.
///
/// A card's parsed data and its signals are both pure functions of the text, so
/// re-running the classifier and parser reproduces exactly what was captured —
/// no per-card serialisation needed. The one exception is [ShiftIntent.random],
/// which re-rolls on every build, so it's never stored as a live card (it's
/// kept as a plain note with its rolled result in the text).
bool shiftRenderable(ShiftIntent intent) =>
    intent.isCard && intent != ShiftIntent.random;

/// The computed-card intents the capture bar persists as live cards — the ones
/// that would otherwise flatten to a one-line note. The date/link/task-shaped
/// intents keep their richer native tiles instead.
const Set<ShiftIntent> richCardIntents = {
  ShiftIntent.timer,
  ShiftIntent.color,
  ShiftIntent.split,
  ShiftIntent.expense,
  ShiftIntent.convert,
  ShiftIntent.calc,
  ShiftIntent.poll,
  ShiftIntent.contact,
  ShiftIntent.timezone,
  ShiftIntent.goal,
};

/// Rebuild a saved Shapeshift card from just its [intentName] + [source] text.
/// Returns null when there's nothing to rebuild (no source, or an intent that
/// can't be re-rendered), so the caller can fall back to the plain tile.
Widget? buildSavedShiftCard(
  BuildContext context,
  String? intentName,
  String? source, {
  bool interactive = false,
  DateTime? now,
}) {
  if (source == null || source.trim().isEmpty) return null;
  final intent = ShiftIntent.fromName(intentName);
  if (!shiftRenderable(intent)) return null;
  final ref = now ?? DateTime.now();
  final result = classify(source);
  final gated = gateSignals(
    const GatedSignals(),
    result.signals,
    shiftUsedSignals(intent),
  );
  final data = shiftParse(intent, source, ref: ref, colorMood: gated.colorMood);
  return buildShiftCard(
    context,
    intent,
    data,
    gated,
    interactive: interactive,
    now: ref,
  );
}
