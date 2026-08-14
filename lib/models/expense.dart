import '../sync/merge.dart';
import 'profile.dart';

/// A transaction that has already happened.
///
/// The tracker's unit of record — the Planner never writes these.
///
/// Implements [SyncFields] so it can replicate: [updatedAt] drives conflict
/// resolution and [deletedAt] marks a tombstone. See `sync/merge.dart` for why
/// deletes cannot simply remove the row.
class Expense implements SyncFields {
  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.categoryId,
    required this.profileId,
    required this.date,
    required this.updatedAt,
    this.note = '',
    this.attachments = const [],
    this.metadata = const {},
    this.deletedAt,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    final date = DateTime.parse(json['date'] as String);
    return Expense(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      categoryId: json['categoryId'] as String? ?? 'other',
      // Expenses written before profiles existed belong to Personal.
      profileId: json['profileId'] as String? ?? Profile.personalId,
      date: date,
      // Records written before sync existed are treated as last touched when
      // they were logged, which is the best available guess and keeps them
      // losing to any genuine later edit.
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? date,
      note: json['note'] as String? ?? '',
      attachments:
          (json['attachments'] as List?)?.whereType<String>().toList() ??
          const [],
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
    );
  }

  @override
  final String id;

  final String title;
  final double amount;
  final String categoryId;
  final String profileId;

  /// When the money was spent — user data, not sync metadata.
  final DateTime date;

  @override
  final DateTime updatedAt;

  @override
  final DateTime? deletedAt;

  final String note;

  /// Absolute paths to receipt images copied into the app's documents
  /// directory. Paths rather than bytes: a photo is large, and holding several
  /// in memory for every expense in a long list would be wasteful.
  ///
  /// These are device-local. Syncing the images themselves needs file storage
  /// rather than a document database, so a receipt taken on one phone is not
  /// visible on another.
  final List<String> attachments;

  /// Category-specific enrichment (litres, odometer, restaurant, …). Optional
  /// and added whenever the user gets to it — never required at capture time
  /// (spec §18, §19). See `CategoryFields` for the per-category schema.
  final Map<String, dynamic> metadata;

  bool get hasAttachments => attachments.isNotEmpty;

  bool get hasMetadata => metadata.values.any((v) => v != null && v != '');

  /// Text the search box matches against.
  String get searchable => '$title $note'.toLowerCase();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'categoryId': categoryId,
    'profileId': profileId,
    'date': date.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
    'note': note,
    'attachments': attachments,
    'metadata': metadata,
  };

  /// Every mutation stamps [updatedAt], so a caller cannot accidentally write
  /// a change that loses to the version it just replaced.
  Expense copyWith({
    String? title,
    double? amount,
    String? categoryId,
    String? profileId,
    DateTime? date,
    String? note,
    List<String>? attachments,
    Map<String, dynamic>? metadata,
    DateTime? updatedAt,
  }) {
    return Expense(
      id: id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      profileId: profileId ?? this.profileId,
      date: date ?? this.date,
      updatedAt: updatedAt ?? DateTime.now(),
      note: note ?? this.note,
      attachments: attachments ?? this.attachments,
      metadata: metadata ?? this.metadata,
      deletedAt: deletedAt,
    );
  }

  /// Marks the record deleted without discarding it.
  Expense tombstone() {
    final now = DateTime.now();
    return Expense(
      id: id,
      title: title,
      amount: amount,
      categoryId: categoryId,
      profileId: profileId,
      date: date,
      updatedAt: now,
      note: note,
      attachments: attachments,
      metadata: metadata,
      deletedAt: now,
    );
  }

  /// Clears the tombstone, for Undo.
  Expense revive() {
    return Expense(
      id: id,
      title: title,
      amount: amount,
      categoryId: categoryId,
      profileId: profileId,
      date: date,
      updatedAt: DateTime.now(),
      note: note,
      attachments: attachments,
      metadata: metadata,
    );
  }
}

/// The criteria the expense list filters by.
///
/// A value type so the filter sheet can hand back one object, and so
/// "is anything filtered" is a single question rather than four.
class ExpenseFilter {
  const ExpenseFilter({
    this.query = '',
    this.categoryIds = const {},
    this.profileId,
    this.from,
    this.to,
  });

  final String query;
  final Set<String> categoryIds;

  /// Null means every profile.
  final String? profileId;

  final DateTime? from;
  final DateTime? to;

  bool get isActive =>
      query.isNotEmpty ||
      categoryIds.isNotEmpty ||
      profileId != null ||
      from != null ||
      to != null;

  /// Number of active constraints, for the filter button's badge. The text
  /// query is excluded — it has its own visible field.
  int get activeCount =>
      (categoryIds.isEmpty ? 0 : 1) +
      (profileId == null ? 0 : 1) +
      (from == null && to == null ? 0 : 1);

  bool matches(Expense expense) {
    if (query.isNotEmpty && !expense.searchable.contains(query.toLowerCase())) {
      return false;
    }
    if (categoryIds.isNotEmpty && !categoryIds.contains(expense.categoryId)) {
      return false;
    }
    if (profileId != null && expense.profileId != profileId) return false;

    // Bounds are inclusive whole days, so an expense logged at 18:00 on the
    // end date still counts.
    if (from != null && expense.date.isBefore(_startOfDay(from!))) return false;
    if (to != null && expense.date.isAfter(_endOfDay(to!))) return false;

    return true;
  }

  ExpenseFilter copyWith({
    String? query,
    Set<String>? categoryIds,
    String? profileId,
    DateTime? from,
    DateTime? to,
    bool clearProfile = false,
    bool clearDates = false,
  }) {
    return ExpenseFilter(
      query: query ?? this.query,
      categoryIds: categoryIds ?? this.categoryIds,
      profileId: clearProfile ? null : (profileId ?? this.profileId),
      from: clearDates ? null : (from ?? this.from),
      to: clearDates ? null : (to ?? this.to),
    );
  }

  static DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
}
