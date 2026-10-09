import 'package:flutter/material.dart';

/// Every shape the capture bar can morph into. One text box becomes the right
/// card as you type — this is the full set of card types it recognises, ported
/// from the Shapeshift project's intent registry.
///
/// [none] is the "still just text" state (not a card). Everything else is a
/// [CardIntent]; `isCard` tells them apart.
enum ShiftIntent {
  event('Event', 'dinner with priya friday 8pm', Icons.event_rounded, Color(0xFF3B82D6)),
  reminder('Reminder', 'remind me to call mom tomorrow', Icons.notifications_none_rounded, Color(0xFFCC8A2E)),
  todo('Checklist', 'buy milk, eggs, bread and coffee', Icons.checklist_rounded, Color(0xFF2AA783)),
  timer('Timer', '25 min focus', Icons.timer_outlined, Color(0xFFE8590C)),
  habit('Habit', 'meditate every morning', Icons.wb_sunny_outlined, Color(0xFFF59F00)),
  color('Color', '#ff6b35', Icons.palette_outlined, Color(0xFF9B59B6)),
  split('Split', 'split 2400 between 3', Icons.groups_outlined, Color(0xFF12B886)),
  expense('Expense', 'spent 450 on uber', Icons.account_balance_wallet_outlined, Color(0xFF4FBE93)),
  convert('Convert', '5 miles in km', Icons.straighten_rounded, Color(0xFF0C8599)),
  calc('Calculate', '18% of 3450', Icons.calculate_outlined, Color(0xFF4C6EF5)),
  travel('Trip', 'flight to goa next weekend', Icons.flight_takeoff_rounded, Color(0xFF1C7ED6)),
  poll('Poll', 'pizza or burgers for friday?', Icons.how_to_vote_outlined, Color(0xFFBE4BDB)),
  contact('Contact', 'rahul 98200 12345 rahul@mail.com', Icons.person_outline_rounded, Color(0xFFE64980)),
  link('Bookmark', 'vercel.com/blog check later', Icons.bookmark_outline_rounded, Color(0xFF3B82D6)),
  countdown('Countdown', 'days until christmas', Icons.event_available_outlined, Color(0xFFF03E3E)),
  timezone('Time zone', '3pm pst in ist', Icons.public_rounded, Color(0xFF1098AD)),
  random('Random', 'roll 2d6', Icons.casino_outlined, Color(0xFF7048E8)),
  goal('Goal', 'read 12 books this year, 4 done', Icons.track_changes_rounded, Color(0xFF2F9E44)),
  note('Note', 'the city felt so quiet this morning', Icons.sticky_note_2_outlined, Color(0xFF6D5DF6)),
  none('Text', '', Icons.auto_awesome, Color(0xFF6D5DF6));

  const ShiftIntent(this.label, this.example, this.icon, this.accent);

  /// Shown on the kind pill and in the command palette.
  final String label;

  /// A one-line example of text that resolves to this card — the palette hint.
  final String example;

  final IconData icon;

  /// The card's signature colour.
  final Color accent;

  /// True for everything the registry can render a card for (i.e. not [none]).
  bool get isCard => this != ShiftIntent.none;

  static ShiftIntent fromName(String? name) => ShiftIntent.values.firstWhere(
    (i) => i.name == name,
    orElse: () => ShiftIntent.none,
  );

  /// The card intents, in registry order (everything but [none]).
  static List<ShiftIntent> get cards =>
      ShiftIntent.values.where((i) => i.isCard).toList();
}
