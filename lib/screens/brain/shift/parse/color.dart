import 'package:flutter/painting.dart';

/// Colour parsing: hex, rgb(), named colours, pop-culture/brand/gem references
/// ("minecraft diamond", "tiffany blue"), and evocative words ("ocean", "lava").
/// Ported from Shapeshift's color parser; the light/dark/vivid/muted modifiers
/// use Flutter's HSLColor in place of the original's OKLCH maths.
enum ColorSource { hex, rgb, named, mood }

class ColorData {
  const ColorData({this.hex, this.name, this.source});
  final String? hex;
  final String? name;
  final ColorSource? source;
}

const Map<String, String> namedColors = {
  'red': '#e03131', 'crimson': '#c2255c', 'scarlet': '#f03e3e', 'maroon': '#862e2e',
  'burgundy': '#7a1f3d', 'pink': '#f06595', 'rose': '#e64980', 'coral': '#ff7f6b',
  'salmon': '#fa8072', 'peach': '#ffb38a', 'orange': '#ff7a1a', 'tangerine': '#ff8c2b',
  'amber': '#f59f00', 'gold': '#e8b000', 'yellow': '#fcc419', 'mustard': '#d4a017',
  'lemon': '#fff06a', 'cream': '#f7f0dc', 'beige': '#e8dcc4', 'sand': '#d8c49c',
  'tan': '#c9a77c', 'brown': '#8b5a2b', 'chocolate': '#5d3a1a', 'olive': '#808a2f',
  'lime': '#82c91e', 'green': '#2f9e44', 'sage': '#9caf88', 'mint': '#96f2d7',
  'emerald': '#0ca678', 'forest': '#2b5c34', 'teal': '#0c8599', 'turquoise': '#22b8cf',
  'cyan': '#15aabf', 'sky': '#74c0fc', 'blue': '#1c7ed6', 'navy': '#1b2a5c',
  'cobalt': '#2451b7', 'indigo': '#4c6ef5', 'violet': '#7950f2', 'purple': '#7048e8',
  'lavender': '#b197fc', 'lilac': '#c8a2c8', 'magenta': '#d6336c', 'plum': '#8e4585',
  'grey': '#868e96', 'gray': '#868e96', 'slate': '#5c6b7a', 'charcoal': '#343a40',
  'black': '#141414', 'white': '#fafaf9', 'ivory': '#fffff0',
};

const Map<String, String> referenceColors = {
  'minecraft diamond': '#4aedd9', 'minecraft grass': '#7cbd6b',
  'minecraft emerald': '#17dd62', 'minecraft gold': '#fcee4b',
  'minecraft redstone': '#ff0000', 'tiffany blue': '#0abab5', 'tiffany': '#0abab5',
  'barbie pink': '#e0218a', 'barbie': '#e0218a', 'spotify green': '#1db954',
  'coca cola red': '#f40009', 'coke red': '#f40009', 'netflix red': '#e50914',
  'facebook blue': '#1877f2', 'twitter blue': '#1da1f2', 'instagram pink': '#e1306c',
  'discord blurple': '#5865f2', 'blurple': '#5865f2', 'starbucks green': '#00704a',
  'ferrari red': '#ff2800', 'ikea blue': '#0058a3', 'ikea yellow': '#ffda1a',
  'mcdonalds yellow': '#ffc72c', 'hermes orange': '#f37021', 'klein blue': '#002fa7',
  'millennial pink': '#f3cfc6', 'matrix green': '#00ff41', 'shrek green': '#b5c91f',
  'minion yellow': '#fce029', 'pikachu yellow': '#f6d02f', 'pikachu': '#f6d02f',
  'hulk green': '#5ba331', 'smurf blue': '#3d8ed9', 'barney purple': '#7a3fa0',
  'diamond': '#b9f2ff', 'ruby': '#e0115f', 'sapphire': '#0f52ba', 'amethyst': '#9966cc',
  'jade': '#00a86b', 'topaz': '#ffc87c', 'pearl': '#eae0c8', 'onyx': '#353839',
  'sky blue': '#87ceeb', 'baby blue': '#89cff0', 'baby pink': '#f4c2c2',
  'hot pink': '#ff69b4', 'neon green': '#39ff14', 'electric blue': '#7df9ff',
  'midnight blue': '#191970', 'forest green': '#228b22', 'blood red': '#8a0303',
  'brick red': '#b22222', 'royal blue': '#4169e1', 'powder blue': '#b0e0e6',
  'army green': '#4b5320', 'hunter green': '#355e3b', 'burnt orange': '#cc5500',
  'rose gold': '#b76e79', 'dusty rose': '#c4a4a7', 'off white': '#f5f5f0',
  'off-white': '#f5f5f0', 'terracotta': '#e2725b', 'denim': '#1560bd',
  'champagne': '#f7e7ce', 'copper': '#b87333', 'bronze': '#cd7f32',
  'silver': '#c0c0c0', 'blush': '#de5d83',
};

const Map<String, String> evocativeColors = {
  'ocean': '#1f6f8b', 'sea': '#2e8bc0', 'grass': '#5fa641', 'lava': '#cf1020',
  'sunset': '#fd5e53', 'sunflower': '#ffc512', 'cherry': '#d2042d', 'wine': '#722f37',
  'coffee': '#6f4e37', 'mocha': '#967969', 'latte': '#c5a582', 'rust': '#b7410e',
  'eggplant': '#614051', 'avocado': '#568203', 'pistachio': '#93c572',
  'flamingo': '#fc8eac', 'bubblegum': '#ffc1cc', 'snow': '#fffafa', 'fire': '#e25822',
  'blood': '#8a0303', 'sky': '#87ceeb',
};

const Map<String, String> _moodBase = {
  'warm': '#f76707', 'cool': '#3b5bdb', 'neutral': '#b8b2a7',
  'vivid': '#f2206c', 'pastel': '#a5d8ff', 'dark': '#1f2a44',
};

String _escapeKey(String k) {
  final escaped = k.replaceAllMapped(
    RegExp(r'[.*+?^${}()|[\]\\]'),
    (m) => '\\${m[0]}',
  );
  return escaped.replaceAll(RegExp(r'[ -]'), r'[\s-]?');
}

RegExp _phraseRe(Map<String, String> table) {
  final keys = table.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  return RegExp('\\b(${keys.map(_escapeKey).join('|')})\\b', caseSensitive: false);
}

/// Specific references that only ever mean a colour — also read by the
/// classifier as a strong colour signal.
final RegExp referenceColorRe = _phraseRe(referenceColors);
final RegExp _evocativeRe = _phraseRe(evocativeColors);

String _normalizeKey(String m) => m.toLowerCase().replaceAll(RegExp(r'[\s-]+'), ' ');

String? _lastPhrase(String text, RegExp re, Map<String, String> table) {
  String? found;
  for (final m in re.allMatches(text)) {
    final key = _normalizeKey(m.group(1)!);
    final hit = table.containsKey(key)
        ? key
        : (table.containsKey(key.replaceAll(' ', '-')) ? key.replaceAll(' ', '-') : null);
    if (hit != null) found = hit;
  }
  return found;
}

String _toHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

Color _fromHex(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

String rgbToHex(int r, int g, int b) {
  int clamp(int v) => v.clamp(0, 255);
  return '#${clamp(r).toRadixString(16).padLeft(2, '0')}'
      '${clamp(g).toRadixString(16).padLeft(2, '0')}'
      '${clamp(b).toRadixString(16).padLeft(2, '0')}';
}

String _modifiers(String text, String hex) {
  final hsl = HSLColor.fromColor(_fromHex(hex));
  HSLColor out = hsl;
  if (RegExp(r'\b(light|pale|soft|pastel|baby)\b', caseSensitive: false).hasMatch(text)) {
    out = hsl.withLightness((hsl.lightness).clamp(0.86, 1.0)).withSaturation((hsl.saturation * 0.55).clamp(0.0, 1.0));
  } else if (RegExp(r'\b(dark|deep|midnight)\b', caseSensitive: false).hasMatch(text)) {
    out = hsl.withLightness(hsl.lightness < 0.38 ? hsl.lightness : 0.30).withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0));
  } else if (RegExp(r'\b(bright|neon|vivid|electric)\b', caseSensitive: false).hasMatch(text)) {
    out = hsl.withSaturation((hsl.saturation * 1.25).clamp(0.0, 1.0));
  } else if (RegExp(r'\b(muted|dusty|faded)\b', caseSensitive: false).hasMatch(text)) {
    out = hsl.withSaturation((hsl.saturation * 0.5).clamp(0.0, 1.0));
  } else {
    return hex;
  }
  return _toHex(out.toColor());
}

ColorData parseColor(String text, [String? mood]) {
  final hex = RegExp(r'#([0-9a-f]{6}|[0-9a-f]{3})\b', caseSensitive: false).firstMatch(text);
  if (hex != null) {
    final g = hex.group(1)!;
    final h = g.length == 3 ? g.split('').map((c) => '$c$c').join() : g;
    return ColorData(hex: '#${h.toLowerCase()}', source: ColorSource.hex);
  }
  final rgb = RegExp(r'rgba?\(\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})', caseSensitive: false).firstMatch(text);
  if (rgb != null) {
    return ColorData(
      hex: rgbToHex(int.parse(rgb.group(1)!), int.parse(rgb.group(2)!), int.parse(rgb.group(3)!)),
      source: ColorSource.rgb,
    );
  }
  final ref = _lastPhrase(text, referenceColorRe, referenceColors);
  if (ref != null) {
    return ColorData(hex: referenceColors[ref], name: ref, source: ColorSource.named);
  }
  final words = RegExp(r'[a-z]+').allMatches(text.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = words.length - 1; i >= 0; i--) {
    final w = words[i];
    final key = namedColors.containsKey(w)
        ? w
        : (w.endsWith('ish') && namedColors.containsKey(w.substring(0, w.length - 3))
            ? w.substring(0, w.length - 3)
            : null);
    if (key != null) {
      return ColorData(hex: _modifiers(text, namedColors[key]!), name: key, source: ColorSource.named);
    }
  }
  final evocative = _lastPhrase(text, _evocativeRe, evocativeColors);
  if (evocative != null) {
    return ColorData(hex: _modifiers(text, evocativeColors[evocative]!), name: evocative, source: ColorSource.named);
  }
  if (mood != null && _moodBase.containsKey(mood)) {
    return ColorData(hex: _modifiers(text, _moodBase[mood]!), source: ColorSource.mood);
  }
  return const ColorData();
}

double completeColor(ColorData d) => switch (d.source) {
  ColorSource.hex || ColorSource.rgb => 1,
  ColorSource.named => 0.8,
  ColorSource.mood => 0.5,
  null => 0,
};

String summaryColor(ColorData d) => [
  d.name != null ? (d.name![0].toUpperCase() + d.name!.substring(1)) : 'Color',
  d.hex?.toUpperCase(),
].where((e) => e != null && e.isNotEmpty).join(' · ');
