import 'package:flutter/material.dart';

import '../sync/merge.dart';
import 'icons.dart';
import 'palette.dart';

/// A spending category.
///
/// User data: categories can be created, renamed, recoloured and deleted. The
/// app seeds a starter set on first launch, but nothing here is fixed — the
/// product needs categories as specific as "Business Advertising" or
/// "Electricity", which no fixed list can anticipate.
///
/// [colorSlot] indexes [Palette] and is persisted, so a category's colour is
/// tied to its identity for good. See [Palette] for why it is a slot rather
/// than a free colour, and why exceeding the palette is allowed to go neutral.
/// Note: not a const class. Sync metadata means carrying a [DateTime], which
/// has no const constructor, so the seed set below is `final` rather than
/// `const`.
class ExpenseCategory implements SyncFields {
  ExpenseCategory({
    required this.id,
    required this.name,
    required this.iconName,
    required this.colorSlot,
    this.isSeeded = false,
    this.monthlyBudget,
    DateTime? updatedAt,
    this.deletedAt,
  }) : updatedAt = updatedAt ?? _epoch;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled',
      iconName: json['iconName'] as String? ?? IconChoice.fallback.name,
      colorSlot: (json['colorSlot'] as num?)?.toInt(),
      isSeeded: json['isSeeded'] as bool? ?? false,
      monthlyBudget: (json['monthlyBudget'] as num?)?.toDouble(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? _epoch,
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
    );
  }

  /// Default timestamp for seeded and pre-sync records.
  ///
  /// Deliberately ancient so any real edit on any device wins over it. The
  /// seed set is identical everywhere, so it never matters which copy is kept,
  /// but a user's rename must always beat the factory default.
  static final DateTime _epoch = DateTime.utc(2000);

  @override
  final String id;

  final String name;
  final String iconName;

  @override
  final DateTime updatedAt;

  @override
  final DateTime? deletedAt;

  /// Index into [Palette], or null for a neutral category.
  final int? colorSlot;

  /// True for the categories shipped on first launch. Purely informational —
  /// seeded categories are as deletable as any other.
  final bool isSeeded;

  /// Optional spending limit for the month. Null means "no budget" — the
  /// category is still tracked, it just has no target to fill toward.
  final double? monthlyBudget;

  bool get hasBudget => monthlyBudget != null && monthlyBudget! > 0;

  IconData get icon => IconChoice.resolve(iconName);

  Color colorFor(Brightness brightness) => Palette.color(colorSlot, brightness);

  Color of(BuildContext context) => colorFor(Theme.of(context).brightness);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'iconName': iconName,
    'colorSlot': colorSlot,
    'isSeeded': isSeeded,
    'monthlyBudget': monthlyBudget,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  /// Every edit stamps [updatedAt], so a change always beats the version it
  /// replaces when the two meet on another device.
  ///
  /// [clearBudget] removes the budget; passing a new [monthlyBudget] sets it.
  ExpenseCategory copyWith({
    String? name,
    String? iconName,
    int? colorSlot,
    bool clearColorSlot = false,
    double? monthlyBudget,
    bool clearBudget = false,
    DateTime? updatedAt,
  }) {
    return ExpenseCategory(
      id: id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      colorSlot: clearColorSlot ? null : (colorSlot ?? this.colorSlot),
      isSeeded: isSeeded,
      monthlyBudget: clearBudget ? null : (monthlyBudget ?? this.monthlyBudget),
      updatedAt: updatedAt ?? DateTime.now(),
      deletedAt: deletedAt,
    );
  }

  /// Marks the category deleted without discarding it, so the delete can
  /// replicate. See `sync/merge.dart`.
  ExpenseCategory tombstone() {
    final now = DateTime.now();
    return ExpenseCategory(
      id: id,
      name: name,
      iconName: iconName,
      colorSlot: colorSlot,
      isSeeded: isSeeded,
      monthlyBudget: monthlyBudget,
      updatedAt: now,
      deletedAt: now,
    );
  }

  /// Stand-in for a category that no longer exists, and the "Other" bucket in
  /// charts. Deliberately neutral so it never competes with a real hue.
  static final ExpenseCategory unknown = ExpenseCategory(
    id: 'other',
    name: 'Other',
    iconName: 'more',
    colorSlot: null,
  );

  /// The starter set, written to storage on first launch.
  ///
  /// Slots are assigned in palette order, so the eight most common categories
  /// each get a distinct validated hue out of the box.
  static final List<ExpenseCategory> seed = [
    ExpenseCategory(
      id: 'eating_out',
      name: 'Eating Out',
      iconName: 'restaurant',
      colorSlot: 0,
      isSeeded: true,
    ),
    ExpenseCategory(
      id: 'groceries',
      name: 'Groceries',
      iconName: 'basket',
      colorSlot: 1,
      isSeeded: true,
    ),
    ExpenseCategory(
      id: 'transport',
      name: 'Transport',
      iconName: 'bus',
      colorSlot: 2,
      isSeeded: true,
    ),
    ExpenseCategory(
      id: 'fuel',
      name: 'Fuel',
      iconName: 'fuel',
      colorSlot: 3,
      isSeeded: true,
    ),
    ExpenseCategory(
      id: 'housing',
      name: 'Housing',
      iconName: 'home',
      colorSlot: 4,
      isSeeded: true,
    ),
    ExpenseCategory(
      id: 'bills',
      name: 'Bills & Utilities',
      iconName: 'bolt',
      colorSlot: 5,
      isSeeded: true,
    ),
    ExpenseCategory(
      id: 'subscriptions',
      name: 'Subscriptions',
      iconName: 'subscription',
      colorSlot: 6,
      isSeeded: true,
    ),
    ExpenseCategory(
      id: 'family',
      name: 'Family & Health',
      iconName: 'heart',
      colorSlot: 7,
      isSeeded: true,
    ),
    ExpenseCategory(
      id: 'other',
      name: 'Other',
      iconName: 'more',
      colorSlot: null,
      isSeeded: true,
    ),
  ];
}
