import '../sync/merge.dart';

/// Someone the user lends money to or borrows from (spec §7–§11).
///
/// A person carries no balance of their own — the balance is always *derived*
/// from the loan activities that reference them, so it can never drift out of
/// sync with the ledger. See [AppState.balanceWith].
class Person implements SyncFields {
  const Person({
    required this.id,
    required this.name,
    required this.updatedAt,
    this.deletedAt,
  });

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Someone',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
    );
  }

  @override
  final String id;

  final String name;

  @override
  final DateTime updatedAt;

  @override
  final DateTime? deletedAt;

  /// Normalised key for matching a name typed in a command against existing
  /// people — "john", "John", "  JOHN " all collapse to the same key.
  String get matchKey => name.trim().toLowerCase();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  Person tombstone() {
    final now = DateTime.now();
    return Person(id: id, name: name, updatedAt: now, deletedAt: now);
  }
}

/// A person's net standing with the user, derived from their loan activities.
class LoanBalance {
  const LoanBalance({required this.person, required this.net});

  final Person person;

  /// Positive: the person owes the user this much (a receivable).
  /// Negative: the user owes the person (a liability).
  /// Zero: settled.
  final double net;

  bool get theyOweUser => net > 0;
  bool get weOweThem => net < 0;
  bool get isSettled => net == 0;

  double get magnitude => net.abs();
}
