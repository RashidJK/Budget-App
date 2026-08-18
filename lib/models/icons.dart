import 'package:flutter/material.dart';
import 'phosphor.dart';

/// The icons a user can choose from when creating a category or profile.
///
/// Icons are stored on disk by [name], never by code point. Building an
/// `IconData` from a stored integer would defeat Flutter's icon tree-shaking
/// and force `--no-tree-shake-icons` on every release build; a fixed registry
/// of const icons keeps the font subset small and the choice explicit.
///
/// The glyphs are Phosphor (Regular weight) — a fresher, more consistent line
/// than Material's rounded set that sits naturally with the app's squircle
/// badges. They are const [PhosphorFlatIconData] with a static `fontPackage`,
/// so tree-shaking is preserved. Names are stable, so no stored-category
/// migration is needed.
class IconChoice {
  const IconChoice(this.name, this.icon);

  /// Stable key written to storage.
  final String name;

  final IconData icon;

  static const List<IconChoice> all = [
    IconChoice('restaurant', PhosphorR.forkKnife),
    IconChoice('basket', PhosphorR.basket),
    IconChoice('cart', PhosphorR.shoppingCart),
    IconChoice('bus', PhosphorR.bus),
    IconChoice('car', PhosphorR.car),
    IconChoice('fuel', PhosphorR.gasPump),
    IconChoice('home', PhosphorR.house),
    IconChoice('bolt', PhosphorR.lightning),
    IconChoice('water', PhosphorR.drop),
    IconChoice('wifi', PhosphorR.wifiHigh),
    IconChoice('phone', PhosphorR.deviceMobile),
    IconChoice('signal', PhosphorR.cellSignalHigh),
    IconChoice('subscription', PhosphorR.arrowsClockwise),
    IconChoice('heart', PhosphorR.heart),
    IconChoice('school', PhosphorR.graduationCap),
    IconChoice('people', PhosphorR.users),
    IconChoice('store', PhosphorR.storefront),
    IconChoice('megaphone', PhosphorR.megaphone),
    IconChoice('laptop', PhosphorR.laptop),
    IconChoice('cloud', PhosphorR.cloud),
    IconChoice('briefcase', PhosphorR.briefcase),
    IconChoice('gift', PhosphorR.gift),
    IconChoice('plane', PhosphorR.airplane),
    IconChoice('tools', PhosphorR.wrench),
    IconChoice('sport', PhosphorR.barbell),
    IconChoice('movie', PhosphorR.filmSlate),
    IconChoice('pet', PhosphorR.pawPrint),
    IconChoice('bank', PhosphorR.bank),
    IconChoice('receipt', PhosphorR.receipt),
    // Everyday personal buckets.
    IconChoice('coffee', PhosphorR.coffee),
    IconChoice('groceries', PhosphorR.shoppingCart),
    IconChoice('health', PhosphorR.firstAid),
    IconChoice('games', PhosphorR.gameController),
    IconChoice('clothing', PhosphorR.tShirt),
    IconChoice('spa', PhosphorR.flower),
    IconChoice('kids', PhosphorR.baby),
    IconChoice('savings', PhosphorR.piggyBank),
    IconChoice('insurance', PhosphorR.shieldCheck),
    IconChoice('taxi', PhosphorR.taxi),
    IconChoice('parking', PhosphorR.carProfile),
    IconChoice('apartment', PhosphorR.buildings),
    IconChoice('salary', PhosphorR.money),
    IconChoice('card', PhosphorR.creditCard),
    IconChoice('more', PhosphorR.dotsThreeOutline),
  ];

  static const IconChoice fallback = IconChoice(
    'more',
    PhosphorR.dotsThreeOutline,
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
