import 'package:flutter/material.dart';

/// The categorical colour palette, addressed by slot.
///
/// ## Why slots rather than free colour choice
///
/// Category colour is a *categorical* encoding: it carries identity, nothing
/// else. A palette can only hold about eight hues before neighbouring pairs
/// stop being distinguishable — especially for colourblind readers. These
/// eight were validated as a set against both surfaces (lightness band, chroma
/// floor, colour-vision-deficiency separation, normal-vision separation). An
/// earlier hand-picked set of thirteen failed badly: two of its pinks were
/// only ΔE 5.2 apart, indistinguishable even with full colour vision.
///
/// So users pick a *slot*, not an arbitrary colour, and the slot is persisted
/// on the category. Two consequences that matter:
///
///   * Colour follows the category permanently. Sorting, filtering, or adding
///     an expense never repaints an existing category — a chart whose colours
///     shift underneath you is worse than one with no colour at all.
///   * Beyond the palette's capacity a category has no slot and renders
///     neutral. That is deliberate: inventing a ninth hue would produce a pair
///     no reader could separate. Neutral plus a direct label is honest.
class Palette {
  const Palette._();

  static const List<_Slot> _slots = [
    _Slot('Blue', Color(0xFF2A78D6), Color(0xFF3987E5)),
    _Slot('Green', Color(0xFF008300), Color(0xFF008300)),
    _Slot('Pink', Color(0xFFE87BA4), Color(0xFFD55181)),
    _Slot('Yellow', Color(0xFFEDA100), Color(0xFFC98500)),
    _Slot('Teal', Color(0xFF1BAF7A), Color(0xFF199E70)),
    _Slot('Orange', Color(0xFFEB6834), Color(0xFFD95926)),
    _Slot('Violet', Color(0xFF4A3AA7), Color(0xFF9085E9)),
    _Slot('Red', Color(0xFFE34948), Color(0xFFE66767)),
  ];

  /// Neutral, used for "Other" and for any category without a slot.
  static const Color neutralLight = Color(0xFF6B7280);
  static const Color neutralDark = Color(0xFF9AA1AC);

  /// Number of distinct hues available.
  static int get length => _slots.length;

  static Iterable<int> get indices => Iterable<int>.generate(_slots.length);

  /// The hue for [slot] against [brightness], or the neutral when [slot] is
  /// null or out of range.
  static Color color(int? slot, Brightness brightness) {
    if (slot == null || slot < 0 || slot >= _slots.length) {
      return brightness == Brightness.dark ? neutralDark : neutralLight;
    }
    final entry = _slots[slot];
    return brightness == Brightness.dark ? entry.dark : entry.light;
  }

  /// Human-readable name, for the colour picker.
  static String name(int? slot) {
    if (slot == null || slot < 0 || slot >= _slots.length) return 'Neutral';
    return _slots[slot].name;
  }

  /// The lowest slot not present in [taken], or null when all are spoken for.
  ///
  /// Used to assign a colour automatically when a category is created, so the
  /// common case needs no decision from the user.
  static int? firstFree(Iterable<int?> taken) {
    final used = taken.whereType<int>().toSet();
    for (var slot = 0; slot < _slots.length; slot++) {
      if (!used.contains(slot)) return slot;
    }
    return null;
  }
}

class _Slot {
  const _Slot(this.name, this.light, this.dark);

  final String name;
  final Color light;
  final Color dark;
}
