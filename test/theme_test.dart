import 'dart:typed_data';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'package:read_later/theme/app_colors.dart';
import 'package:read_later/theme/app_theme.dart';
import 'package:read_later/theme/theme_variant.dart';

/// Mocks the dynamic_color platform channel, replicating what
/// `dynamic_color_testing`'s `setMockDynamicColors` does (that package is
/// incompatible with the Flutter SDK's pinned material_color_utilities).
///
/// Pass `null` to simulate a platform without dynamic color support
/// (non-Android, or Android < 12), which is also the default in tests.
void _mockCorePalette(CorePalette? corePalette) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(DynamicColorPlugin.channel, (call) async {
    if (call.method == DynamicColorPlugin.methodName) {
      return corePalette == null
          ? null
          : Int64List.fromList(corePalette.asList());
    }
    return null;
  });
}

/// Mirrors the DynamicColorBuilder -> AppTheme wiring in lib/app.dart.
Widget _appHarness({ThemeMode themeMode = ThemeMode.system}) {
  return DynamicColorBuilder(
    builder: (lightDynamic, darkDynamic) => MaterialApp(
      theme: AppTheme.light(ThemeVariant.dynamic, lightDynamic),
      darkTheme: AppTheme.dark(ThemeVariant.dynamic, darkDynamic),
      themeMode: themeMode,
      home: const Scaffold(body: SizedBox()),
    ),
  );
}

/// A CorePalette built from a green seed, used as the "wallpaper" in tests.
final _greenPalette = CorePalette.of(0xFF4CAF50);

void main() {
  // Reset the platform mock before every test so there is no leakage between
  // the dynamic and fallback cases.
  setUp(() => _mockCorePalette(null));

  group('AppTheme fallback (no dynamic color support)', () {
    test('light theme derives from the pocketRed seed', () {
      final theme = AppTheme.light();
      final expected = ColorScheme.fromSeed(
        seedColor: pocketRed,
        brightness: Brightness.light,
      );
      expect(theme.colorScheme.primary, expected.primary);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.useMaterial3, isTrue);
    });

    test('dark theme derives from the pocketRed seed', () {
      final theme = AppTheme.dark();
      final expected = ColorScheme.fromSeed(
        seedColor: pocketRed,
        brightness: Brightness.dark,
      );
      expect(theme.colorScheme.primary, expected.primary);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('fallback primary differs from a green dynamic palette', () {
      final fallback = AppTheme.light().colorScheme.primary;
      final green = ColorScheme.fromSeed(seedColor: Colors.green).primary;
      expect(fallback, isNot(green));
    });

    test('app-level customizations build on the fallback scheme', () {
      final theme = AppTheme.light();
      final appColors = theme.extension<AppColors>()!;
      expect(theme.cardTheme.color, appColors.backdrop);
      expect(theme.appBarTheme.backgroundColor, Colors.transparent);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.scaffoldBackgroundColor, appColors.backdrop);
    });
  });

  group('AppTheme with an explicit dynamic scheme', () {
    test('light theme uses the provided dynamic scheme', () {
      final dynamicScheme = ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: Brightness.light,
      );
      final theme = AppTheme.light(ThemeVariant.dynamic, dynamicScheme);
      expect(theme.colorScheme.primary, dynamicScheme.primary);
      expect(theme.colorScheme.primary,
          isNot(AppTheme.light().colorScheme.primary));
    });

    test('dark theme uses the provided dynamic scheme', () {
      final dynamicScheme = ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: Brightness.dark,
      );
      final theme = AppTheme.dark(ThemeVariant.dynamic, dynamicScheme);
      expect(theme.colorScheme.primary, dynamicScheme.primary);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('harmonized() shifts semantic colors towards the dynamic primary', () {
      final dynamicScheme = ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: Brightness.light,
      );
      final theme = AppTheme.light(ThemeVariant.dynamic, dynamicScheme);
      // error is a fixed red in seeded schemes; harmonization pulls its hue
      // towards the green primary.
      expect(theme.colorScheme.error, isNot(dynamicScheme.error));
      expect(
          theme.colorScheme.errorContainer, isNot(dynamicScheme.errorContainer));
    });
  });

  group('Theme variants', () {
    test('Light, Dark and Dynamic all build a valid scheme', () {
      for (final variant in ThemeVariant.values) {
        final light = AppTheme.light(variant);
        final dark = AppTheme.dark(variant);
        expect(light.extension<AppColors>(), isNotNull);
        expect(dark.extension<AppColors>(), isNotNull);
        expect(light.scaffoldBackgroundColor,
            light.extension<AppColors>()!.backdrop);
        expect(dark.scaffoldBackgroundColor,
            dark.extension<AppColors>()!.backdrop);
      }
    });

    test('without a platform palette, every variant uses the brand seed', () {
      final expected = ColorScheme.fromSeed(
        seedColor: pocketRed,
        brightness: Brightness.light,
      ).primary;
      for (final variant in ThemeVariant.values) {
        expect(AppTheme.light(variant).colorScheme.primary, expected);
      }
    });
  });

  group('Black bold text', () {
    test('every light theme renders text pure black, dark themes white', () {
      for (final variant in ThemeVariant.values) {
        final light = AppTheme.light(variant);
        expect(light.colorScheme.onSurface, Colors.black);
        expect(light.colorScheme.onSurfaceVariant, Colors.black);
        expect(light.colorScheme.outline, Colors.black);

        final dark = AppTheme.dark(variant);
        expect(dark.colorScheme.onSurface, Colors.white);
        expect(dark.colorScheme.onSurfaceVariant, Colors.white);
        expect(dark.colorScheme.outline, Colors.white);
      }
    });

    test('body text is bold across the type scale', () {
      final theme = AppTheme.light();
      expect(theme.textTheme.bodyMedium?.fontWeight, FontWeight.w500);
      expect(theme.textTheme.bodySmall?.fontWeight, FontWeight.w500);
      expect(theme.textTheme.titleMedium?.fontWeight, FontWeight.w700);
      expect(theme.textTheme.titleLarge?.fontWeight, FontWeight.w700);
      expect(theme.textTheme.labelMedium?.fontWeight, FontWeight.w600);
    });
  });

  group('DynamicColorBuilder integration', () {
    testWidgets('uses the wallpaper palette when the platform provides one',
        (tester) async {
      _mockCorePalette(_greenPalette);
      await tester.pumpWidget(_appHarness());
      await tester.pumpAndSettle();

      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      // dynamic_color builds its schemes with Scheme.lightFromCorePalette, so
      // the expected value must come from the same (deprecated) API.
      final expectedPrimary = Color(
        // ignore: deprecated_member_use
        Scheme.lightFromCorePalette(_greenPalette).primary,
      );
      expect(theme.colorScheme.primary, expectedPrimary);
      expect(theme.colorScheme.primary,
          isNot(AppTheme.light().colorScheme.primary));
    });

    testWidgets('falls back to the brand seed without dynamic color support',
        (tester) async {
      await tester.pumpWidget(_appHarness());
      await tester.pumpAndSettle();

      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      final expected = ColorScheme.fromSeed(
        seedColor: pocketRed,
        brightness: Brightness.light,
      );
      expect(theme.colorScheme.primary, expected.primary);
    });

    testWidgets('dark mode receives the dark dynamic scheme', (tester) async {
      _mockCorePalette(_greenPalette);
      await tester.pumpWidget(_appHarness(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.colorScheme.brightness, Brightness.dark);
      final expectedDarkPrimary = Color(
        // ignore: deprecated_member_use
        Scheme.darkFromCorePalette(_greenPalette).primary,
      );
      expect(theme.colorScheme.primary, expectedDarkPrimary);
    });

    testWidgets('app-level customizations follow the dynamic scheme',
        (tester) async {
      _mockCorePalette(_greenPalette);
      await tester.pumpWidget(_appHarness());
      await tester.pumpAndSettle();

      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      final appColors = theme.extension<AppColors>()!;
      expect(theme.cardTheme.color, appColors.backdrop);
      expect(theme.appBarTheme.backgroundColor, Colors.transparent);
    });
  });
}
