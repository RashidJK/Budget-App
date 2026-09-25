import 'package:budget/models/brain_item.dart';
import 'package:budget/services/storage.dart';
import 'package:budget/state/brain_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Storage> _storage() async {
  SharedPreferences.setMockInitialValues({});
  return Storage.open();
}

void main() {
  test('captures land newest-first and filter by kind', () async {
    final brain = BrainState(await _storage());

    await brain.capture(BrainKind.note, 'first note');
    await brain.capture(BrainKind.task, 'buy milk');
    await brain.capture(BrainKind.note, 'second note');

    // Newest capture is first.
    expect(brain.items.first.text, 'second note');
    expect(brain.items.length, 3);

    // Filtering narrows to one kind, keeping newest-first order.
    final notes = brain.ofKind(BrainKind.note);
    expect(notes.map((i) => i.text), ['second note', 'first note']);
    expect(brain.ofKind(BrainKind.task).single.text, 'buy milk');
    expect(brain.countOf(BrainKind.note), 2);
  });

  test('pinned items sort above the rest', () async {
    final brain = BrainState(await _storage());
    await brain.capture(BrainKind.note, 'old');
    final pin = await brain.capture(BrainKind.note, 'pin me');
    await brain.capture(BrainKind.note, 'newest');

    await brain.togglePinned(pin.id);

    // Pinned first, then the remaining two newest-first.
    expect(brain.items.map((i) => i.text), ['pin me', 'newest', 'old']);
  });

  test('toggleDone flips a task and it survives a reload', () async {
    final storage = await _storage();
    final brain = BrainState(storage);
    final task = await brain.capture(BrainKind.task, 'ship it');
    expect(task.done, isFalse);

    await brain.toggleDone(task.id);
    expect(brain.items.single.done, isTrue);

    // A fresh state reading the same storage sees the persisted change.
    final reloaded = BrainState(storage);
    expect(reloaded.items.single.done, isTrue);
  });

  test('resurfaced surfaces aged notes/links, not tasks, pinned or recent', () async {
    final brain = BrainState(await _storage());
    await brain.capture(BrainKind.note, 'old idea');
    await brain.capture(BrainKind.task, 'a task'); // excluded: task
    await brain.capture(BrainKind.link, 'https://a.co');
    final pinned = await brain.capture(BrainKind.note, 'pinned one');
    await brain.togglePinned(pinned.id); // excluded: pinned

    // Ten days on, the notes/links have aged into resurface candidates.
    final future = DateTime.now().add(const Duration(days: 10));
    final surfaced = brain.resurfaced(now: future).map((i) => i.text).toList();
    expect(surfaced, containsAll(['old idea', 'https://a.co']));
    expect(surfaced, isNot(contains('a task')));
    expect(surfaced, isNot(contains('pinned one')));

    // Freshly captured items are too recent to resurface.
    expect(brain.resurfaced().isEmpty, isTrue);
  });

  test('dismissResurface hides an item for the day', () async {
    final brain = BrainState(await _storage());
    final note = await brain.capture(BrainKind.note, 'surface me');
    final future = DateTime.now().add(const Duration(days: 10));
    expect(brain.resurfaced(now: future).single.id, note.id);

    await brain.dismissResurface(note.id);
    expect(brain.resurfaced(now: future).isEmpty, isTrue);
  });

  test('snooze hides an item until it wakes, then it resurfaces', () async {
    final brain = BrainState(await _storage());
    final note = await brain.capture(BrainKind.note, 'later idea');
    expect(brain.items.length, 1);

    // Snoozed three days out: gone from the feed and the counts.
    await brain.snooze(note.id, DateTime.now().add(const Duration(days: 3)));
    expect(brain.items, isEmpty);
    expect(brain.countOf(BrainKind.note), 0);
    // Still asleep a day in — not resurfaced yet.
    final dayIn = DateTime.now().add(const Duration(days: 1));
    expect(brain.resurfaced(now: dayIn), isEmpty);

    // Once its time passes it floats into the resurface strip.
    final after = DateTime.now().add(const Duration(days: 4));
    expect(brain.resurfaced(now: after).single.id, note.id);
  });

  test('wake un-snoozes an item back into the feed', () async {
    final brain = BrainState(await _storage());
    final note = await brain.capture(BrainKind.note, 'wake me');
    await brain.snooze(note.id, DateTime.now().add(const Duration(days: 3)));
    expect(brain.items, isEmpty);

    await brain.wake(note.id);
    expect(brain.items.single.id, note.id);
  });

  test('remove tombstones, restore brings it back', () async {
    final brain = BrainState(await _storage());
    final item = await brain.capture(BrainKind.link, 'https://example.com');
    expect(brain.isEmpty, isFalse);

    await brain.remove(item.id);
    expect(brain.isEmpty, isTrue);

    await brain.restore(item.id);
    expect(brain.items.single.text, 'https://example.com');
  });
}
