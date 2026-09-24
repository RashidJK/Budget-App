import 'package:flutter/material.dart';

/// One "app" inside the Spaces shell — the budget tracker, the second brain,
/// and room for more later. [builder] is the full-screen app; the rest
/// describes how it looks as a card on the Spaces home.
class AppSpace {
  const AppSpace({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.accent,
    required this.builder,
  });

  final String id;
  final String name;
  final String tagline;
  final IconData icon;
  final Color accent;
  final WidgetBuilder builder;
}
