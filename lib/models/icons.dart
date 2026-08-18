import 'package:flutter/material.dart';

/// The icons a user can choose from when creating a category or profile.
///
/// Icons are stored on disk by [name], never by code point. Building an
/// `IconData` from a stored integer would defeat Flutter's icon tree-shaking
/// and force `--no-tree-shake-icons` on every release build; a fixed registry
/// of const icons keeps the font subset small and the choice explicit.
class IconChoice {
  const IconChoice(this.name, this.icon);

  /// Stable key written to storage.
  final String name;

  final IconData icon;

  static const List<IconChoice> all = [
    IconChoice('restaurant', Icons.restaurant_rounded),
    IconChoice('basket', Icons.shopping_basket_rounded),
    IconChoice('cart', Icons.shopping_cart_rounded),
    IconChoice('bus', Icons.directions_bus_rounded),
    IconChoice('car', Icons.directions_car_rounded),
    IconChoice('fuel', Icons.local_gas_station_rounded),
    IconChoice('home', Icons.home_rounded),
    IconChoice('bolt', Icons.bolt_rounded),
    IconChoice('water', Icons.water_drop_rounded),
    IconChoice('wifi', Icons.wifi_rounded),
    IconChoice('phone', Icons.smartphone_rounded),
    IconChoice('signal', Icons.signal_cellular_alt_rounded),
    IconChoice('subscription', Icons.autorenew_rounded),
    IconChoice('heart', Icons.favorite_rounded),
    IconChoice('school', Icons.school_rounded),
    IconChoice('people', Icons.people_rounded),
    IconChoice('store', Icons.storefront_rounded),
    IconChoice('megaphone', Icons.campaign_rounded),
    IconChoice('laptop', Icons.laptop_mac_rounded),
    IconChoice('cloud', Icons.cloud_rounded),
    IconChoice('briefcase', Icons.work_rounded),
    IconChoice('gift', Icons.card_giftcard_rounded),
    IconChoice('plane', Icons.flight_rounded),
    IconChoice('tools', Icons.build_rounded),
    IconChoice('sport', Icons.fitness_center_rounded),
    IconChoice('movie', Icons.movie_rounded),
    IconChoice('pet', Icons.pets_rounded),
    IconChoice('bank', Icons.account_balance_rounded),
    IconChoice('receipt', Icons.receipt_long_rounded),
    // Everyday personal buckets — each new const glyph adds only itself to the
    // font subset, so tree-shaking stays on.
    IconChoice('coffee', Icons.local_cafe_rounded),
    IconChoice('groceries', Icons.local_grocery_store_rounded),
    IconChoice('health', Icons.medical_services_rounded),
    IconChoice('games', Icons.sports_esports_rounded),
    IconChoice('clothing', Icons.checkroom_rounded),
    IconChoice('spa', Icons.spa_rounded),
    IconChoice('kids', Icons.child_care_rounded),
    IconChoice('savings', Icons.savings_rounded),
    IconChoice('insurance', Icons.health_and_safety_rounded),
    IconChoice('taxi', Icons.local_taxi_rounded),
    IconChoice('parking', Icons.local_parking_rounded),
    IconChoice('apartment', Icons.apartment_rounded),
    IconChoice('salary', Icons.payments_rounded),
    IconChoice('card', Icons.credit_card_rounded),
    IconChoice('more', Icons.more_horiz_rounded),
  ];

  static const IconChoice fallback = IconChoice(
    'more',
    Icons.more_horiz_rounded,
  );

  /// Resolves a stored name, falling back rather than throwing so a category
  /// written by a newer version still renders.
  static IconData resolve(String? name) {
    for (final choice in all) {
      if (choice.name == name) return choice.icon;
    }
    return fallback.icon;
  }
}
