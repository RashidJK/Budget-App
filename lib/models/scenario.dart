/// Which planner tool a saved scenario belongs to.
enum ScenarioKind {
  dailyHabit('Daily Habit', 'habit'),
  fuel('Fuel', 'fuel'),
  subscriptions('Subscriptions', 'subscriptions'),
  business('Business Costs', 'business'),
  savings('Savings', 'savings'),
  projection('Projection', 'projection');

  const ScenarioKind(this.label, this.storageKey);

  final String label;

  /// Stable identifier written to disk. Kept separate from the enum name so
  /// the enum can be renamed without orphaning saved scenarios.
  final String storageKey;

  static ScenarioKind fromStorageKey(String? key) {
    return ScenarioKind.values.firstWhere(
      (kind) => kind.storageKey == key,
      orElse: () => ScenarioKind.dailyHabit,
    );
  }
}

/// A named, saved set of planner inputs.
///
/// [data] is a free-form map owned by whichever screen created the scenario.
/// Keeping it untyped is what lets one storage path, one list screen and one
/// set of duplicate/delete actions serve all six calculators — each screen
/// knows how to read its own keys and ignores the rest.
class Scenario {
  const Scenario({
    required this.id,
    required this.name,
    required this.kind,
    required this.data,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Scenario.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['createdAt'] as String);
    return Scenario(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled scenario',
      kind: ScenarioKind.fromStorageKey(json['kind'] as String?),
      data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
      createdAt: createdAt,
      updatedAt: json['updatedAt'] == null
          ? createdAt
          : DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String id;
  final String name;
  final ScenarioKind kind;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The headline yearly figure, cached at save time so the scenario list can
  /// show a number without re-running every calculator.
  double get summaryYearly => (data['_summaryYearly'] as num?)?.toDouble() ?? 0;

  /// A one-line description of the inputs, also cached at save time.
  String get summaryLabel => data['_summaryLabel'] as String? ?? '';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.storageKey,
    'data': data,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  Scenario copyWith({
    String? name,
    Map<String, dynamic>? data,
    DateTime? updatedAt,
  }) {
    return Scenario(
      id: id,
      name: name ?? this.name,
      kind: kind,
      data: data ?? this.data,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Reads a numeric field, tolerating both `int` and `double` on disk.
  double number(String key, [double fallback = 0]) =>
      (data[key] as num?)?.toDouble() ?? fallback;

  String text(String key, [String fallback = '']) =>
      data[key] as String? ?? fallback;

  List<Map<String, dynamic>> rows(String key) {
    final raw = data[key] as List? ?? const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}
