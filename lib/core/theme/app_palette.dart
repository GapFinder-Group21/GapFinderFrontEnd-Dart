import 'package:flutter/material.dart';

// Colors that change between light and dark mode.
// The brand colors that never change (accents, dark headers) stay in AppColors.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  // Screen background
  final Color background;
  // Cards, sheets, dialogs and text fields (white in light mode)
  final Color surface;
  // Texts, icons and borders drawn over background and surface
  final Color contrast;
  // Fill of disabled buttons
  final Color disabled;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.contrast,
    required this.disabled,
  });

  // Same values the app always had
  static const light = AppPalette(
    background: Color(0xFFF6F7F8),
    surface: Colors.white,
    contrast: Color(0xFF011627),
    disabled: Color(0xFFE0E0E0),
  );

  static const dark = AppPalette(
    background: Color(0xFF0E1A25),
    surface: Color(0xFF182836),
    contrast: Color(0xFFF1F4F6),
    disabled: Color(0xFF2B3C4A),
  );

  @override
  AppPalette copyWith({Color? background, Color? surface, Color? contrast, Color? disabled}) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      contrast: contrast ?? this.contrast,
      disabled: disabled ?? this.disabled,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      contrast: Color.lerp(contrast, other.contrast, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
    );
  }
}

// Short way to read the palette: context.palette.surface
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
