/// Category-specific metadata fields (spec §18).
///
/// These enrich an expense but must never block the initial recording (spec
/// §19: "capture first, enrich later"). A fuel expense is saved the moment the
/// amount is known; litres and odometer can be filled in afterwards.
///
/// Keyed by the *seeded* category id, which is stable even if the user renames
/// the category. User-created categories simply have no schema, which is fine —
/// they save as plain expenses.
library;

enum FieldKind { number, integer, text }

/// One optional field a category can carry.
class CategoryField {
  const CategoryField(
    this.key,
    this.label,
    this.kind, {
    this.unit,
    this.hint,
  });

  /// Stable key used in the metadata map.
  final String key;

  final String label;
  final FieldKind kind;

  /// A trailing unit shown in the input (e.g. "L", "km").
  final String? unit;

  final String? hint;

  bool get isNumeric => kind == FieldKind.number || kind == FieldKind.integer;
}

/// The schema registry.
class CategoryFields {
  const CategoryFields._();

  static const Map<String, List<CategoryField>> _byCategory = {
    'fuel': [
      CategoryField('litres', 'Litres', FieldKind.number, unit: 'L'),
      CategoryField('pricePerLitre', 'Price / litre', FieldKind.number,
          unit: 'TSh'),
      CategoryField('station', 'Station', FieldKind.text, hint: 'TotalEnergies'),
      CategoryField('vehicle', 'Vehicle', FieldKind.text),
      CategoryField('odometer', 'Odometer', FieldKind.number, unit: 'km'),
    ],
    'eating_out': [
      CategoryField('restaurant', 'Restaurant', FieldKind.text),
      CategoryField('mealType', 'Meal', FieldKind.text, hint: 'Lunch'),
      CategoryField('people', 'People', FieldKind.integer),
    ],
    'groceries': [
      CategoryField('store', 'Store', FieldKind.text),
    ],
    'bills': [
      CategoryField('provider', 'Provider', FieldKind.text),
      CategoryField('units', 'Units used', FieldKind.number, unit: 'kWh / GB'),
    ],
    'transport': [
      CategoryField('distance', 'Distance', FieldKind.number, unit: 'km'),
    ],
  };

  static List<CategoryField> forCategory(String? categoryId) =>
      _byCategory[categoryId] ?? const [];

  static bool has(String? categoryId) => forCategory(categoryId).isNotEmpty;

  /// A short prompt for the enrich-later nudge, e.g. "Add fuel details".
  static String promptFor(String categoryName) =>
      'Add ${categoryName.toLowerCase()} details';
}
