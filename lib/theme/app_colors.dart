import 'package:flutter/material.dart';

/// Extra color tokens beyond the Material [ColorScheme], mirroring Twine's
/// design system:
///
///  * [backdrop] — the app's background surface. A near-white neutral in
///    light mode (tone 95) and near-black in dark mode (tone 5), instead of
///    plain white/black.
///  * [bottomSheet], [bottomSheetInverse] — bottom-sheet surfaces tinted with
///    the *primary* palette (very dark tones), Twine's signature look.
///  * [bottomSheetBorder] — outline used for the sheet's top edge.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color backdrop;
  final Color bottomSheet;
  final Color bottomSheetInverse;
  final Color bottomSheetBorder;

  const AppColors({
    required this.backdrop,
    required this.bottomSheet,
    required this.bottomSheetInverse,
    required this.bottomSheetBorder,
  });

  /// Sensible fallback built from a plain [ColorScheme] (used in tests or
  /// when the app theme isn't applied).
  factory AppColors.fromScheme(ColorScheme scheme) {
    return AppColors(
      backdrop: scheme.surface,
      bottomSheet: scheme.surfaceContainerHigh,
      bottomSheetInverse: scheme.surfaceContainerLow,
      bottomSheetBorder: scheme.outlineVariant,
    );
  }

  /// A subtle translucent fill, as used for image placeholders.
  Color translucentFill(ColorScheme scheme) =>
      scheme.onSurface.withValues(alpha: 0.08);

  @override
  AppColors copyWith({
    Color? backdrop,
    Color? bottomSheet,
    Color? bottomSheetInverse,
    Color? bottomSheetBorder,
  }) {
    return AppColors(
      backdrop: backdrop ?? this.backdrop,
      bottomSheet: bottomSheet ?? this.bottomSheet,
      bottomSheetInverse: bottomSheetInverse ?? this.bottomSheetInverse,
      bottomSheetBorder: bottomSheetBorder ?? this.bottomSheetBorder,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      backdrop: Color.lerp(backdrop, other.backdrop, t)!,
      bottomSheet: Color.lerp(bottomSheet, other.bottomSheet, t)!,
      bottomSheetInverse:
          Color.lerp(bottomSheetInverse, other.bottomSheetInverse, t)!,
      bottomSheetBorder:
          Color.lerp(bottomSheetBorder, other.bottomSheetBorder, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>() ??
      AppColors.fromScheme(Theme.of(this).colorScheme);
}
