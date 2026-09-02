import 'package:flutter/material.dart';

import '../sync/merge.dart';
import 'palette.dart';
import 'phosphor.dart';

/// Where money actually sits — cash on hand, a bank account, a mobile-money
/// wallet. Accounts turn the app from a flow tracker ("spent this month") into
/// a ledger that can answer "how much do I have, and where".
///
/// Every [Expense] and [Activity] is attributed to an account, so a balance is
/// derived, never guessed: `balance = openingBalance + everything in − out`.
/// The [openingBalance] captures money that already existed when the account
/// was created, before any of it was tracked.
///
/// Not a const class — sync metadata carries a [DateTime]. See [Profile].
enum AccountType {
  cash('Cash'),
  mobileMoney('Mobile Money'),
  bank('Bank'),
  card('Card'),
  other('Other');

  const AccountType(this.label);

  final String label;

  IconData get icon => switch (this) {
    AccountType.cash => PhosphorR.money,
    AccountType.mobileMoney => PhosphorR.deviceMobile,
    AccountType.bank => PhosphorR.bank,
    AccountType.card => PhosphorR.creditCard,
    AccountType.other => PhosphorR.wallet,
  };

  static AccountType fromName(String? name) => values.firstWhere(
    (t) => t.name == name,
    orElse: () => AccountType.cash,
  );
}

class Account implements SyncFields {
  Account({
    required this.id,
    required this.name,
    required this.type,
    this.openingBalance = 0,
    this.colorSlot,
    DateTime? updatedAt,
    this.deletedAt,
  }) : updatedAt = updatedAt ?? _epoch;

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Account',
      type: AccountType.fromName(json['type'] as String?),
      openingBalance: (json['openingBalance'] as num?)?.toDouble() ?? 0,
      colorSlot: (json['colorSlot'] as num?)?.toInt(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? _epoch,
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
    );
  }

  /// Ancient default so a real edit on any device always wins over the seed.
  static final DateTime _epoch = DateTime.utc(2000);

  @override
  final String id;

  final String name;
  final AccountType type;

  /// The balance when the account was created — money that existed before
  /// tracking began, so the derived balance starts from reality rather than 0.
  final double openingBalance;

  final int? colorSlot;

  @override
  final DateTime updatedAt;

  @override
  final DateTime? deletedAt;

  IconData get icon => type.icon;

  Color of(BuildContext context) =>
      Palette.color(colorSlot, Theme.of(context).brightness);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'openingBalance': openingBalance,
    'colorSlot': colorSlot,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  Account copyWith({
    String? name,
    AccountType? type,
    double? openingBalance,
    int? colorSlot,
    DateTime? updatedAt,
  }) {
    return Account(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      openingBalance: openingBalance ?? this.openingBalance,
      colorSlot: colorSlot ?? this.colorSlot,
      updatedAt: updatedAt ?? DateTime.now(),
      deletedAt: deletedAt,
    );
  }

  /// Marks the account deleted without discarding it, so the delete can
  /// replicate. See `sync/merge.dart`.
  Account tombstone() {
    final now = DateTime.now();
    return Account(
      id: id,
      name: name,
      type: type,
      openingBalance: openingBalance,
      colorSlot: colorSlot,
      updatedAt: now,
      deletedAt: now,
    );
  }

  /// The account every record lands in until the user makes another. Seeded on
  /// first launch and used as the fallback for records written before accounts
  /// existed.
  static const String defaultId = 'cash';

  static final List<Account> seed = [
    Account(id: defaultId, name: 'Cash', type: AccountType.cash, colorSlot: 4),
  ];
}

/// An account paired with its derived current balance — one card in the deck.
class AccountBalance {
  const AccountBalance({required this.account, required this.balance});

  final Account account;
  final double balance;
}
