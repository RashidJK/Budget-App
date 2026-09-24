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
