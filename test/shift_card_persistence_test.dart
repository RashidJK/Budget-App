import 'dart:convert';

import 'package:budget/models/brain_item.dart';
import 'package:budget/screens/brain/shift/shift_intent.dart';
import 'package:budget/screens/brain/shift/shift_restore.dart';
import 'package:budget/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A computed Shapeshift card is persisted as just `{intent, source}` on the
/// BrainItem; the feed rebuilds the real card from that. These check the two
/// halves: the payload survives storage, and the rebuild is faithful (and
/// refuses the non-deterministic `random` card).

Widget _harness(String? intent, String? source) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: Builder(
      builder: (context) =>
          buildSavedShiftCard(context, intent, source) ?? const Text('NO CARD'),
    ),
  ),
);

void main() {
  group('persistence', () {
    test('a shift payload round-trips through JSON', () {
      final item = BrainItem(
        id: 'x',
        kind: BrainKind.note,
        text: '= 621',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        shift: const {'intent': 'calc', 'source': '18% of 3450'},
      );
      // The real path: encode to a string and back, as Storage does.
      final back = BrainItem.fromJson(
        jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>,
      );
      expect(back.shift, {'intent': 'calc', 'source': '18% of 3450'});
    });

    test('copyWith, tombstone and revive all carry the shift payload', () {
      final item = BrainItem(
        id: 'x',
        kind: BrainKind.note,
        text: '#FF6B35',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        shift: const {'intent': 'color', 'source': '#ff6b35'},
      );
      expect(item.copyWith().shift, item.shift);
      expect(item.tombstone().shift, item.shift);
      expect(item.revive().shift, item.shift);
    });

    test('an ordinary note has no shift payload', () {
      final item = BrainItem(
        id: 'x',
        kind: BrainKind.note,
        text: 'just a thought',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(item.toJson()['shift'], isNull);
      expect(BrainItem.fromJson(item.toJson()).shift, isNull);
    });
  });

  group('renderable rules', () {
    test('computed cards are renderable; random and plain text are not', () {
      expect(shiftRenderable(ShiftIntent.calc), isTrue);
      expect(shiftRenderable(ShiftIntent.color), isTrue);
      expect(shiftRenderable(ShiftIntent.random), isFalse);
      expect(shiftRenderable(ShiftIntent.none), isFalse);
    });

    test('every persisted rich intent is renderable and never random', () {
      for (final intent in richCardIntents) {
        expect(shiftRenderable(intent), isTrue, reason: '$intent');
      }
      expect(richCardIntents.contains(ShiftIntent.random), isFalse);
    });
  });

  group('rebuild from source', () {
    testWidgets('a calc card re-renders its result', (tester) async {
      await tester.pumpWidget(_harness('calc', '18% of 3450'));
      expect(find.text('NO CARD'), findsNothing);
      expect(find.textContaining('621'), findsWidgets); // 18% of 3450
    });

    testWidgets('a colour card re-renders its hex', (tester) async {
      await tester.pumpWidget(_harness('color', '#ff6b35'));
      expect(find.textContaining('FF6B35'), findsWidgets);
    });

    testWidgets('random is refused (it would re-roll on every build)', (
      tester,
    ) async {
      await tester.pumpWidget(_harness('random', 'roll 2d6'));
      expect(find.text('NO CARD'), findsOneWidget);
    });

    testWidgets('a missing source renders nothing', (tester) async {
      await tester.pumpWidget(_harness('calc', null));
      expect(find.text('NO CARD'), findsOneWidget);
    });
  });
}
