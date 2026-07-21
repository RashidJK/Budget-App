import 'package:flutter/material.dart';

import '../sync/merge.dart';
import 'icons.dart';
import 'palette.dart';

/// A wallet the user keeps separate — Personal, a business, a side project.
///
/// Profiles partition expenses rather than tagging them: the dashboard,
/// reports and budgets all scope to one profile at a time, which is what makes
/// "how much does each of my businesses cost to operate" answerable.
///
/// Not a const class — sync metadata carries a [DateTime]. See
/// [ExpenseCategory] for the same note.
class Profile implements SyncFields {
  Profile({
    required this.id,
    required this.name,
    required this.iconName,
    required this.colorSlot,
    this.isBusiness = false,
    DateTime? updatedAt,
    this.deletedAt,
  }) : updatedAt = updatedAt ?? _epoch;

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled',
      iconName: json['iconName'] as String? ?? 'people',
      colorSlot: (json['colorSlot'] as num?)?.toInt(),
      isBusiness: json['isBusiness'] as bool? ?? false,
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
  final String iconName;
  final int? colorSlot;

  /// Marks the profile as a business, which is what surfaces operating-cost
  /// framing rather than personal-spending framing.
  final bool isBusiness;

  @override
  final DateTime updatedAt;

  @override
  final DateTime? deletedAt;

  IconData get icon => IconChoice.resolve(iconName);

  Color of(BuildContext context) =>
      Palette.color(colorSlot, Theme.of(context).brightness);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'iconName': iconName,
    'colorSlot': colorSlot,
    'isBusiness': isBusiness,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  Profile copyWith({
    String? name,
    String? iconName,
    int? colorSlot,
    bool? isBusiness,
    DateTime? updatedAt,
  }) {
    return Profile(
      id: id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      colorSlot: colorSlot ?? this.colorSlot,
      isBusiness: isBusiness ?? this.isBusiness,
      updatedAt: updatedAt ?? DateTime.now(),
      deletedAt: deletedAt,
    );
  }

  /// Marks the profile deleted without discarding it, so the delete can
  /// replicate. See `sync/merge.dart`.
  Profile tombstone() {
    final now = DateTime.now();
    return Profile(
      id: id,
      name: name,
      iconName: iconName,
      colorSlot: colorSlot,
      isBusiness: isBusiness,
      updatedAt: now,
      deletedAt: now,
    );
  }

  /// The profile every expense lands in until the user makes another.
  static const String personalId = 'personal';

  static final List<Profile> seed = [
    Profile(
      id: personalId,
      name: 'Personal',
      iconName: 'people',
      colorSlot: 0,
    ),
    Profile(
      id: 'business',
      name: 'Business',
      iconName: 'store',
      colorSlot: 6,
      isBusiness: true,
    ),
  ];

  static final Profile unknown = Profile(
    id: personalId,
    name: 'Personal',
    iconName: 'people',
    colorSlot: null,
  );
}
