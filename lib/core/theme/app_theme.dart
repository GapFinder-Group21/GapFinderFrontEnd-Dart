import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';

class AppTheme {
  // Flutter's default theme plus the palette, so light mode looks exactly as before
  static ThemeData get light => ThemeData(extensions: const [AppPalette.light]);

  static ThemeData get dark {
    const palette = AppPalette.dark;
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: palette.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4), // same seed as the default light theme
        brightness: Brightness.dark,
        surface: palette.surface,
      ),
      extensions: const [palette],
    );
  }
}
