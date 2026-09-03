import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The app's visual language.
///
/// Surfaces match the ones the chart palette was validated against, so a
/// category hue sitting on a card clears the same contrast checks it cleared
/// in the validator.
class AppTheme {
  const AppTheme._();

  static const Color _seed = Color(0xFF2A78D6);

  static const Color lightSurface = Color(0xFFFCFCFB);
  static const Color darkSurface = Color(0xFF1A1A19);

  /// Positive outcomes — money saved, an alternative that costs less.
  /// Reserved: never reused as a series colour.
  static const Color goodLight = Color(0xFF067647);
  static const Color goodDark = Color(0xFF3DBF87);

  /// Negative outcomes — overspending, an "alternative" that costs more.
  static const Color warnLight = Color(0xFFB42318);
  static const Color warnDark = Color(0xFFF07A72);

  /// Caution — nearing a limit, a forward projection. Amber, theme-aware like
  /// [good]/[warn] rather than a raw literal scattered through the widgets.
  static const Color cautionLight = Color(0xFFEDA100);
  static const Color cautionDark = Color(0xFFC98500);

  /// The brand mark's gradient — a light spring green settling into teal, taken
  /// from the app logo. Used on the signature accent surfaces (the capture
  /// button, the FAB) to tie the app to its mark. Kept off the [ColorScheme]
  /// primary on purpose: the chart palette reserves green for "good", so the
  /// seed stays blue and green reads as brand, not data.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF97E29E), Color(0xFF3CA98B)],
  );

  /// A solid mid-tone of [brandGradient], for spots a gradient can't paint.
  static const Color brandGreen = Color(0xFF4FBE93);

  /// The hero card's dark fill as a gradient, for a little depth. A faint green
  /// undertone at the base nods to the brand without lifting off near-black.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF23262D), Color(0xFF121611)],
  );

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? darkSurface : lightSurface;

    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
      surface: surface,
    );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'Inter',
    );

    return base.copyWith(
      scaffoldBackgroundColor: surface,
      textTheme: _textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: _card(scheme, isDark),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _border(scheme, isDark)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _card(scheme, isDark),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: _inputBorder(scheme, isDark),
        enabledBorder: _inputBorder(scheme, isDark),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: _border(scheme, isDark)),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _card(scheme, isDark),
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.28 : 0.14),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dividerTheme: DividerThemeData(
        color: _border(scheme, isDark),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  /// Card fill: a touch lighter than the surface in dark mode, a touch cooler
  /// in light mode, so cards read as raised without a shadow.
  static Color _card(ColorScheme scheme, bool isDark) =>
      isDark ? const Color(0xFF232322) : Colors.white;

  // Light hairline is softened (#ECECE6, was #E7E7E2) so the light-mode card
  // shadow does the lifting without a competing outline-plus-shadow edge.
  static Color _border(ColorScheme scheme, bool isDark) =>
      isDark ? const Color(0xFF33332F) : const Color(0xFFECECE6);

  static OutlineInputBorder _inputBorder(ColorScheme scheme, bool isDark) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _border(scheme, isDark)),
      );

  static TextTheme _textTheme(TextTheme base) => base.copyWith(
    // The single heaviest, tightest token — the one headline figure (the hero
    // balance) sits on this so it out-weighs the surrounding w700 rather than
    // flattening into it.
    displayLarge: base.displayLarge?.copyWith(
      fontSize: 40,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.5,
      height: 1.0,
    ),
    displaySmall: base.displaySmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    // Section titles pick up the same engineered negative tracking the app bar
    // already uses, so headers across tabs read in one voice.
    titleLarge: base.titleLarge?.copyWith(letterSpacing: -0.3),
    titleMedium: base.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
}

/// Theme-aware helpers for colours that aren't part of [ColorScheme].
extension AppColors on BuildContext {
  ColorScheme get scheme => Theme.of(this).colorScheme;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Raised card / surface fill, matching the themed [Card]. Kept here beside
  /// the other surface tokens so the ten-odd hand-rolled cards share one value.
  Color get card => isDark ? const Color(0xFF232322) : Colors.white;

  /// Border/hairline colour matching the card outline.
  Color get hairline =>
      isDark ? const Color(0xFF33332F) : const Color(0xFFE7E7E2);

  /// Recessive ink for axis labels, captions and units.
  Color get muted => scheme.onSurfaceVariant;

  Color get good => isDark ? AppTheme.goodDark : AppTheme.goodLight;

  Color get warn => isDark ? AppTheme.warnDark : AppTheme.warnLight;

  /// Caution — nearing a budget limit, a forward projection.
  Color get caution => isDark ? AppTheme.cautionDark : AppTheme.cautionLight;

  /// A whisper-subtle page wash behind large surfaces — a three-stop graded
  /// canvas so switching tabs feels like moving within one lit space. Near-black
  /// → black in dark, white → warm grey in light ("black to white-ish").
  LinearGradient get surfaceGradient => isDark
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1D1D1C), Color(0xFF161615), Color(0xFF131312)],
          stops: [0.0, 0.5, 1.0],
        )
      : const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFF7F7F3), Color(0xFFF1F1EC)],
          stops: [0.0, 0.5, 1.0],
        );

  /// Light-mode-only soft card float — a wide ambient shadow plus a tight
  /// contact shadow, so cards lift a few millimetres off the wash. Dark mode
  /// stays flat: shadows on near-black read as mud, the fill lift carries it.
  List<BoxShadow> get cardShadow => isDark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0D1A1A19), // #1A1A19 @ 0.05
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
          BoxShadow(
            color: Color(0x081A1A19), // #1A1A19 @ 0.03
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ];

  /// The one canonical content-card decoration — fill, hairline, radius and the
  /// theme-aware float — so every hand-rolled card stays identical.
  BoxDecoration cardDecoration({double radius = 20}) => BoxDecoration(
    color: card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: hairline),
    boxShadow: cardShadow,
  );
}

/// The signature "hero" surface — the dark, softly-lifted gradient card used for
/// the dashboard's headline figure and an account's balance. Top-level (not on
/// the context extension) so it reads the same regardless of the ambient theme:
/// the hero is always dark on purpose.
BoxDecoration heroCardDecoration() => BoxDecoration(
  gradient: AppTheme.heroGradient,
  borderRadius: BorderRadius.circular(26),
  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.22),
      blurRadius: 8,
      offset: const Offset(0, 3),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.16),
      blurRadius: 28,
      offset: const Offset(0, 14),
    ),
    BoxShadow(
      color: AppTheme.brandGreen.withValues(alpha: 0.10),
      blurRadius: 34,
      offset: const Offset(0, 16),
    ),
  ],
);
