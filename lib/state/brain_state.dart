import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/brain_item.dart';
import '../services/storage.dart';
import '../sync/merge.dart';

const _uuid = Uuid();

/// Owns the second brain's captures, kept separate from the budget's [AppState]
/// so the two apps stay independent. Persists to the same JSON-in-preferences
/// [Storage], under its own key.
class BrainState extends ChangeNotifier {
  BrainState(this._storage) {
    _load();
    _loadDismissed();
  }

  final Storage _storage;

  List<BrainItem> _items = [];

  /// Ids the user dismissed from the resurface strip today.
  Set<String> _dismissedToday = {};

  // An item is a resurface candidate once it's at least this old and hasn't
  // been pinned, deleted or dismissed. Tasks are excluded — due dates surface
  // those. Up to [_resurfaceMax] show at once.
  static const _resurfaceMinAgeDays = 5;
  static const _resurfaceMax = 3;

  void _load() {
    _items = _storage.readBrainItems().map(BrainItem.fromJson).toList();
  }

  void _loadDismissed() {
    final raw = _storage.readResurfaceDismissed();
    if (raw['date'] == _dayKey(DateTime.now())) {
      _dismissedToday =
          (raw['ids'] as List?)?.map((e) => '$e').toSet() ?? <String>{};
    } else {
      _dismissedToday = {};
    }
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Every live item, pinned first, then newest capture first.
  List<BrainItem> get items {
    final live = _items.where((i) => !i.isDeleted).toList();
    live.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return live;
  }

  /// Live items of one [kind]; null returns everything.
  List<BrainItem> ofKind(BrainKind? kind) =>
      kind == null ? items : items.where((i) => i.kind == kind).toList();

  int countOf(BrainKind kind) =>
      _items.where((i) => !i.isDeleted && i.kind == kind).length;

  bool get isEmpty => items.isEmpty;

  /// A small, stable-for-the-day set of older captures "worth another look":
  /// on-this-day matches first, then the oldest un-pinned notes, journals and
  /// links. Tasks are left to their due dates. Empty until items age in.
  List<BrainItem> resurfaced({DateTime? now}) {
    final today = now ?? DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    int ageDays(BrainItem i) => start
        .difference(DateTime(i.createdAt.year, i.createdAt.month, i.createdAt.day))
        .inDays;

    final candidates = _items
        .where(
          (i) =>
              !i.isDeleted &&
              !i.pinned &&
              i.kind != BrainKind.task &&
              !_dismissedToday.contains(i.id) &&
              ageDays(i) >= _resurfaceMinAgeDays,
        )
        .toList();
    if (candidates.isEmpty) return const [];

    bool onThisDay(BrainItem i) =>
        (i.createdAt.month == today.month && i.createdAt.day == today.day) ||
        i.createdAt.day == today.day;

    candidates.sort((a, b) {
      final byDay = (onThisDay(b) ? 1 : 0) - (onThisDay(a) ? 1 : 0);
      if (byDay != 0) return byDay;
      return a.createdAt.compareTo(b.createdAt); // oldest first
    });
    return candidates.take(_resurfaceMax).toList();
  }

  /// Hides a resurfaced item for the rest of the day.
  Future<void> dismissResurface(String id) async {
    _dismissedToday.add(id);
    await _storage.writeResurfaceDismissed({
      'date': _dayKey(DateTime.now()),
      'ids': _dismissedToday.toList(),
    });
    notifyListeners();
  }

  /// Records a new capture and returns it.
  Future<BrainItem> capture(
    BrainKind kind,
    String text, {
    String? url,
    DateTime? dueDate,
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final item = BrainItem(
      id: _uuid.v4(),
      kind: kind,
      text: text.trim(),
      createdAt: now,
      updatedAt: now,
      url: url,
      dueDate: dueDate,
      tags: tags,
    );
    _items = [item, ..._items];
    await _persist();
    return item;
  }

  Future<void> update(BrainItem item) async {
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index == -1) return;
    _items = [..._items]..[index] = item;
    await _persist();
  }

  Future<void> toggleDone(String id) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    final item = _items[index];
    _items = [..._items]..[index] = item.copyWith(done: !item.done);
    await _persist();
  }

  Future<void> togglePinned(String id) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    final item = _items[index];
    _items = [..._items]..[index] = item.copyWith(pinned: !item.pinned);
    await _persist();
  }

  Future<void> remove(String id) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    _items = [..._items]..[index] = _items[index].tombstone();
    await _persist();
  }

  /// Undo a delete.
  Future<void> restore(String id) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    _items = [..._items]..[index] = _items[index].revive();
    await _persist();
  }

  Future<void> _persist() async {
    notifyListeners();
    await _storage.writeBrainItems(_items.map((i) => i.toJson()).toList());
  }
}
