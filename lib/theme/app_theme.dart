import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'app_colors.dart';
import 'theme_variant.dart';

/// Pocket's signature red, used as the seed for the brand scheme.
const Color pocketRed = Color(0xFFEF4056);

/// Serif style used for article body text (maps to Noto Serif on Android).
const TextStyle readerTextStyle = TextStyle(
  fontFamily: 'serif',
  fontSize: 18,
  height: 1.7,
  letterSpacing: 0.1,
  fontWeight: FontWeight.w500,
);

/// App theme.
///
/// Two palettes, both Material 3:
///  * the **brand** scheme seeded by [pocketRed], and
///  * the platform's **dynamic** (Material You) palette from
///    [DynamicColorBuilder] when available.
///
/// Light/dark follow the [ThemeVariant] (fixed, or system via
/// [ThemeVariant.dynamic]). Every variant shares the extra [AppColors] tokens,
/// and text always renders pure black in light mode / pure white in dark mode.
class AppTheme {
  /// Builds the light theme for [variant].
  static ThemeData light([
    ThemeVariant variant = ThemeVariant.dynamic,
    ColorScheme? systemDynamic,
  ]) =>
      _build(Brightness.light, variant, systemDynamic);

  /// Builds the dark theme for [variant].
  static ThemeData dark([
    ThemeVariant variant = ThemeVariant.dynamic,
    ColorScheme? systemDynamic,
  ]) =>
      _build(Brightness.dark, variant, systemDynamic);

  static ThemeData _build(
    Brightness brightness,
    ThemeVariant variant,
    ColorScheme? systemDynamic,
  ) {
    final isDark = brightness == Brightness.dark;
    final (rawScheme, appColors) =
        schemeFor(variant, isDark, systemDynamic: systemDynamic);
    // Pure black (light) / pure white (dark) text everywhere: the scheme's
    // grey secondary tones (onSurfaceVariant) and outline are forced to match
    // so no text (or border) renders grey in any theme.
    final scheme = rawScheme.copyWith(
      onSurface: isDark ? Colors.white : Colors.black,
      onSurfaceVariant: isDark ? Colors.white : Colors.black,
      outline: isDark ? Colors.white : Colors.black,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: appColors.backdrop,
      textTheme: _outfitTextTheme(),
    );
    return base.copyWith(
      extensions: [appColors],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        // Transparent by default: the app bar sits on the backdrop and lets
        // screens draw their own background/gradient.
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: appColors.backdrop,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }

  /// Resolves the (ColorScheme, AppColors) pair for a variant, ignoring any
  /// platform dynamic palette (used for preview swatches).
  static (ColorScheme, AppColors) schemeFor(
    ThemeVariant variant,
    bool isDark, {
    ColorScheme? systemDynamic,
  }) {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    switch (variant) {
      case ThemeVariant.dynamic:
        final scheme = (systemDynamic ??
                ColorScheme.fromSeed(
                  seedColor: pocketRed,
                  brightness: brightness,
                ))
            .harmonized();
        // The dynamic palette's primary is a good proxy for its seed.
        return (scheme, _extrasForSeed(scheme.primary, isDark));
      case ThemeVariant.light:
      case ThemeVariant.dark:
        final scheme = ColorScheme.fromSeed(
          seedColor: pocketRed,
          brightness: brightness,
        );
        return (scheme, _extrasForSeed(pocketRed, isDark));
    }
  }

  /// Extra tokens derived from the seed's tonal palettes: backdrop sits on
  /// the neutral palette (tone 95 light / 5 dark), the bottom sheets use the
  /// primary palette at near-black tones.
  static AppColors _extrasForSeed(Color seed, bool isDark) {
    final palette = CorePalette.of(seed.toARGB32());
    return AppColors(
      backdrop: Color(palette.neutral.get(isDark ? 5 : 95)),
      bottomSheet: Color(palette.primary.get(isDark ? 0 : 5)),
      bottomSheetInverse: Color(palette.primary.get(isDark ? 5 : 0)),
      bottomSheetBorder: Color(palette.neutral.get(20)),
    );
  }

  /// Outfit type scale, deliberately heavy: body text sits at medium (500)
  /// and titles at bold (700+), so everything reads boldly in every theme.
  static TextTheme _outfitTextTheme() {
    const family = 'Outfit';
    const theme = TextTheme(
      displayLarge: TextStyle(
          fontFamily: family,
          fontSize: 57,
          height: 64 / 57,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25),
      displayMedium: TextStyle(
          fontFamily: family, fontSize: 45, height: 52 / 45, fontWeight: FontWeight.w600),
      displaySmall: TextStyle(
          fontFamily: family, fontSize: 36, height: 44 / 36, fontWeight: FontWeight.w600),
      headlineLarge: TextStyle(
          fontFamily: family,
          fontSize: 32,
          height: 40 / 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.64),
      headlineMedium: TextStyle(
          fontFamily: family,
          fontSize: 28,
          height: 32 / 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.56),
      headlineSmall: TextStyle(
          fontFamily: family,
          fontSize: 24,
          height: 32 / 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.48),
      titleLarge: TextStyle(
          fontFamily: family, fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(
          fontFamily: family, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w700),
      titleSmall: TextStyle(
          fontFamily: family, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(
          fontFamily: family, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w500),
      bodyMedium: TextStyle(
          fontFamily: family, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500),
      bodySmall: TextStyle(
          fontFamily: family,
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.24),
      labelLarge: TextStyle(
          fontFamily: family, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700),
      labelMedium: TextStyle(
          fontFamily: family,
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.24),
      labelSmall: TextStyle(
          fontFamily: family,
          fontSize: 10,
          height: 12 / 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4),
    );
    return theme;
  }
}
