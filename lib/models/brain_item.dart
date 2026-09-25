import '../sync/merge.dart';

/// The kinds of thing the second brain captures. One model covers them all —
/// they share far more than they differ (a bit of text, a timestamp), and a
/// single feed that interleaves every kind is the whole point of an inbox.
enum BrainKind {
  note('Note'),
  task('Task'),
  journal('Journal'),
  link('Link');

  const BrainKind(this.label);

  final String label;

  static BrainKind fromName(String? name) =>
      BrainKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => BrainKind.note,
      );
}

/// One captured thought: a note, a task, a journal entry or a saved link.
///
/// Implements [SyncFields] so it replicates the same way the budget records do,
/// leaving room to fold the second brain into the existing sync engine later.
class BrainItem implements SyncFields {
  const BrainItem({
    required this.id,
    required this.kind,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.done = false,
    this.dueDate,
    this.url,
    this.pinned = false,
    this.tags = const [],
    this.surfaceAt,
    this.deletedAt,
  });

  factory BrainItem.fromJson(Map<String, dynamic> json) {
    final created =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime(2000);
    return BrainItem(
      id: json['id'] as String,
      kind: BrainKind.fromName(json['kind'] as String?),
      text: json['text'] as String? ?? '',
      createdAt: created,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? created,
      done: json['done'] as bool? ?? false,
      dueDate: DateTime.tryParse(json['dueDate'] as String? ?? ''),
      url: json['url'] as String?,
      pinned: json['pinned'] as bool? ?? false,
      tags: (json['tags'] as List?)?.map((e) => '$e').toList() ?? const [],
      surfaceAt: DateTime.tryParse(json['surfaceAt'] as String? ?? ''),
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
    );
  }

  @override
  final String id;

  final BrainKind kind;

  /// The body of a note, the title of a task, the entry of a journal, or the
  /// user's label for a link.
  final String text;

  final DateTime createdAt;

  @override
  final DateTime updatedAt;

  @override
  final DateTime? deletedAt;

  /// Tasks only: whether it's checked off.
  final bool done;

  /// Tasks only: an optional due date.
  final DateTime? dueDate;

  /// Links only: the destination.
  final String? url;

  final bool pinned;
  final List<String> tags;

  /// When set to a future time, the item is snoozed — hidden from the feed
  /// until then, when it floats back up via the resurface strip.
  final DateTime? surfaceAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
    'done': done,
    'dueDate': dueDate?.toIso8601String(),
    'url': url,
    'pinned': pinned,
    'tags': tags,
    'surfaceAt': surfaceAt?.toIso8601String(),
  };

  BrainItem copyWith({
    BrainKind? kind,
    String? text,
    bool? done,
    DateTime? dueDate,
    String? url,
    bool? pinned,
    List<String>? tags,
    DateTime? surfaceAt,
    DateTime? updatedAt,
  }) {
    return BrainItem(
      id: id,
      kind: kind ?? this.kind,
      text: text ?? this.text,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      done: done ?? this.done,
      dueDate: dueDate ?? this.dueDate,
      url: url ?? this.url,
      pinned: pinned ?? this.pinned,
      tags: tags ?? this.tags,
      surfaceAt: surfaceAt ?? this.surfaceAt,
      deletedAt: deletedAt,
    );
  }

  /// Marks the item deleted without discarding it, so the delete can replicate.
  /// [copyWith] deliberately carries [deletedAt] through unchanged, so the
  /// deleted twin is built directly here.
  BrainItem tombstone() => BrainItem(
    id: id,
    kind: kind,
    text: text,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    done: done,
    dueDate: dueDate,
    url: url,
    pinned: pinned,
    tags: tags,
    surfaceAt: surfaceAt,
    deletedAt: DateTime.now(),
  );

  /// Clears the tombstone, for Undo, with a fresh [updatedAt] so it wins the
  /// merge over its deleted twin.
  BrainItem revive() => BrainItem(
    id: id,
    kind: kind,
    text: text,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    done: done,
    dueDate: dueDate,
    url: url,
    pinned: pinned,
    tags: tags,
    surfaceAt: surfaceAt,
  );
}
