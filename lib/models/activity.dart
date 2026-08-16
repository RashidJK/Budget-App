import '../sync/merge.dart';
import 'profile.dart';

/// The kinds of financial activity the app records.
///
/// Expenses keep their own dedicated [Expense] model and storage — they were
/// here first and every screen already understands them. This enum covers the
/// *other* money movements the Smart Capture spec adds, which an ordinary
/// expense record cannot represent because they involve a second party, a
/// second account, or a running balance rather than a one-way spend.
///
/// The distinction matters for accounting (spec §34): only [expense] and
/// [income] move the headline totals. Transfers move money between the user's
/// own accounts, and loans create receivables/liabilities — none of those are
/// spending or earning, and folding them in would make every report lie.
enum ActivityType {
  /// Kept for completeness and history rendering. Expenses are normally stored
  /// as [Expense]; an activity is only tagged `expense` when something outside
  /// the tracker (a scan, a paste) produced one that hasn't been converted.
  expense('Expense', isOutflow: true),

  /// Money received as earnings — salary, a client payment, a sale.
  income('Income', isInflow: true),

  /// Money moved between the user's own accounts. Neither spend nor earnings.
  transfer('Transfer'),

  /// Money the user lent out. Reduces available cash, creates a receivable.
  loanOut('Lent out', isOutflow: true),

  /// Money the user borrowed. Increases available cash, creates a liability.
  loanIn('Borrowed', isInflow: true),

  /// The user paying back money they borrowed. Reduces a liability.
  loanRepayment('Loan repayment', isOutflow: true),

  /// Someone paying back money they were lent. Reduces a receivable.
  receivableRepayment('Repayment received', isInflow: true);

  const ActivityType(
    this.label, {
    this.isInflow = false,
    this.isOutflow = false,
  });

  final String label;

  /// True when the activity brings money in (shown with a leading `+`).
  final bool isInflow;

  /// True when it takes money out (shown with a leading `−`).
  final bool isOutflow;

  /// Involves another person and a running balance the app must track.
  bool get isLoanRelated =>
      this == loanOut ||
      this == loanIn ||
      this == loanRepayment ||
      this == receivableRepayment;

  /// Repayments settle an existing balance rather than opening a new one.
  bool get isRepayment =>
      this == loanRepayment || this == receivableRepayment;

  static ActivityType fromName(String? name) {
    return ActivityType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => ActivityType.expense,
    );
  }
}

/// How money moved. Distinct from [ActivityType]: an expense *type* can be paid
/// by any of these *methods* (spec §17).
enum PaymentMethod {
  cash('Cash'),
  mobileMoney('Mobile Money'),
  bank('Bank'),
  card('Card'),
  other('Other');

  const PaymentMethod(this.label);
  final String label;

  static PaymentMethod? fromName(String? name) {
    if (name == null) return null;
    for (final method in PaymentMethod.values) {
      if (method.name == name) return method;
    }
    return null;
  }
}

/// How confident the app is that a captured activity is correct (spec §20).
///
/// A capture from a clean manual command is [verified]; one parsed from a
/// receipt or SMS where a field was uncertain is [needsReview] until the user
/// confirms it. Nothing is ever blocked from saving on account of this —
/// "capture first, enrich later".
enum ActivityStatus {
  recorded('Recorded'),
  needsReview('Needs review'),
  verified('Verified');

  const ActivityStatus(this.label);
  final String label;

  static ActivityStatus fromName(String? name) {
    return ActivityStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => ActivityStatus.recorded,
    );
  }
}

/// How an activity came to be recorded, for later analytics and debugging
/// (spec §28).
enum ActivitySource {
  manual,
  command,
  pastedTransaction,
  receiptScan,
  import_,
  recurring;

  static ActivitySource fromName(String? name) {
    return ActivitySource.values.firstWhere(
      (source) => source.name == name,
      orElse: () => ActivitySource.manual,
    );
  }
}

/// A non-expense financial activity: income, transfer, loan or repayment.
///
/// Deliberately a superset of what an [Expense] carries — it adds the second
/// party ([personId]), the two account endpoints a transfer needs, a
/// [PaymentMethod], a [status] and [confidence] for uncertain captures, and a
/// free-form [metadata] map for category-specific enrichment added later.
///
/// Implements [SyncFields] so it replicates like everything else.
class Activity implements SyncFields {
  const Activity({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.updatedAt,
    this.description = '',
    this.categoryId,
    this.profileId,
    this.paymentMethod,
    this.sourceAccount,
    this.destinationAccount,
    this.merchant,
    this.personId,
    this.status = ActivityStatus.recorded,
    this.confidence,
    this.source = ActivitySource.manual,
    this.note = '',
    this.metadata = const {},
    this.deletedAt,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    final date = DateTime.parse(json['date'] as String);
    return Activity(
      id: json['id'] as String,
      type: ActivityType.fromName(json['type'] as String?),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      date: date,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? date,
      description: json['description'] as String? ?? '',
      categoryId: json['categoryId'] as String?,
      profileId: json['profileId'] as String? ?? Profile.personalId,
      paymentMethod: PaymentMethod.fromName(json['paymentMethod'] as String?),
      sourceAccount: json['sourceAccount'] as String?,
      destinationAccount: json['destinationAccount'] as String?,
      merchant: json['merchant'] as String?,
      personId: json['personId'] as String?,
      status: ActivityStatus.fromName(json['status'] as String?),
      confidence: (json['confidence'] as num?)?.toDouble(),
      source: ActivitySource.fromName(json['source'] as String?),
      note: json['note'] as String? ?? '',
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
    );
  }

  @override
  final String id;

  final ActivityType type;
  final double amount;

  /// When the activity happened (user data, not sync metadata).
  final DateTime date;

  @override
  final DateTime updatedAt;

  @override
  final DateTime? deletedAt;

  final String description;
  final String? categoryId;
  final String? profileId;
  final PaymentMethod? paymentMethod;

  /// For transfers: where money came from / went to (e.g. "bank", "M-Pesa").
  final String? sourceAccount;
  final String? destinationAccount;

  final String? merchant;

  /// The other party, for loans and repayments.
  final String? personId;

  final ActivityStatus status;

  /// Parser confidence 0..1, when this was auto-captured.
  final double? confidence;

  final ActivitySource source;
  final String note;

  /// Category-specific enrichment added later (litres, odometer, …). Never
  /// required at capture time.
  final Map<String, dynamic> metadata;

  /// Signed effect on the person's balance for loan-type activities.
  ///
  /// Positive means the person owes the user more (a receivable grew);
  /// negative means the user owes the person more (a liability grew), or the
  /// respective balance was paid down. Returns 0 for non-loan activities.
  ///
  /// - lent out → they owe you: +amount
  /// - they repay you → they owe you less: −amount
  /// - you borrow → you owe them (a receivable *against* you): −amount
  /// - you repay them → you owe them less: +amount
  double get receivableDelta {
    switch (type) {
      case ActivityType.loanOut:
        return amount;
      case ActivityType.receivableRepayment:
        return -amount;
      case ActivityType.loanIn:
        return -amount;
      case ActivityType.loanRepayment:
        return amount;
      case ActivityType.expense:
      case ActivityType.income:
      case ActivityType.transfer:
        return 0;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'amount': amount,
    'date': date.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
    'description': description,
    'categoryId': categoryId,
    'profileId': profileId,
    'paymentMethod': paymentMethod?.name,
    'sourceAccount': sourceAccount,
    'destinationAccount': destinationAccount,
    'merchant': merchant,
    'personId': personId,
    'status': status.name,
    'confidence': confidence,
    'source': source.name,
    'note': note,
    'metadata': metadata,
  };

  Activity copyWith({
    ActivityType? type,
    double? amount,
    DateTime? date,
    String? description,
    String? categoryId,
    String? profileId,
    PaymentMethod? paymentMethod,
    String? sourceAccount,
    String? destinationAccount,
    String? merchant,
    String? personId,
    ActivityStatus? status,
    double? confidence,
    ActivitySource? source,
    String? note,
    Map<String, dynamic>? metadata,
    DateTime? updatedAt,
  }) {
    return Activity(
      id: id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      updatedAt: updatedAt ?? DateTime.now(),
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      profileId: profileId ?? this.profileId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      sourceAccount: sourceAccount ?? this.sourceAccount,
      destinationAccount: destinationAccount ?? this.destinationAccount,
      merchant: merchant ?? this.merchant,
      personId: personId ?? this.personId,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      note: note ?? this.note,
      metadata: metadata ?? this.metadata,
      deletedAt: deletedAt,
    );
  }

  /// Marks the activity deleted without discarding it, so the delete can
  /// replicate. See `sync/merge.dart`. [copyWith] deliberately can't set
  /// [deletedAt] (it carries through unchanged), so the deleted twin is built
  /// directly here.
  Activity tombstone() {
    final now = DateTime.now();
    return Activity(
      id: id,
      type: type,
      amount: amount,
      date: date,
      updatedAt: now,
      description: description,
      categoryId: categoryId,
      profileId: profileId,
      paymentMethod: paymentMethod,
      sourceAccount: sourceAccount,
      destinationAccount: destinationAccount,
      merchant: merchant,
      personId: personId,
      status: status,
      confidence: confidence,
      source: source,
      note: note,
      metadata: metadata,
      deletedAt: now,
    );
  }

  /// Clears the tombstone, for Undo. [copyWith] can't do this — it carries
  /// [deletedAt] through unchanged — so the revived twin is built directly,
  /// with a fresh [updatedAt] so it wins over the tombstone during merge.
  Activity revive() {
    return Activity(
      id: id,
      type: type,
      amount: amount,
      date: date,
      updatedAt: DateTime.now(),
      description: description,
      categoryId: categoryId,
      profileId: profileId,
      paymentMethod: paymentMethod,
      sourceAccount: sourceAccount,
      destinationAccount: destinationAccount,
      merchant: merchant,
      personId: personId,
      status: status,
      confidence: confidence,
      source: source,
      note: note,
      metadata: metadata,
    );
  }
}
