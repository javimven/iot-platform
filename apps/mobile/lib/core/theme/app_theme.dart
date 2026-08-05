import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Tema de la plataforma (Etapa 14 — primer diseño real, 2026-08-04).
///
/// Sora para títulos (display/headline/title) + Manrope para cuerpo de
/// texto (body/label) — misma familia geométrica, buena legibilidad de
/// números (importante con tantas lecturas de sensores en pantalla).
abstract final class AppTheme {
  static ThemeData get light => _build(brightness: Brightness.light);
  static ThemeData get dark => _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AppColors.brandDark : AppColors.brand,
      onPrimary: isDark ? AppColors.paperDark : AppColors.paperRaised,
      secondary: isDark ? AppColors.brandStrongDark : AppColors.brandStrong,
      onSecondary: isDark ? AppColors.paperDark : AppColors.paperRaised,
      error: isDark ? AppColors.criticalDark : AppColors.critical,
      onError: isDark ? AppColors.paperDark : AppColors.paperRaised,
      surface: isDark ? AppColors.paperRaisedDark : AppColors.paperRaised,
      onSurface: isDark ? AppColors.inkDark : AppColors.ink,
      onSurfaceVariant: isDark ? AppColors.inkSoftDark : AppColors.inkSoft,
      surfaceContainerHighest: isDark ? AppColors.lineDark : AppColors.line,
      outline: isDark ? AppColors.lineDark : AppColors.line,
    );

    final baseTextTheme = ThemeData(brightness: brightness).textTheme;
    final bodyTextTheme = GoogleFonts.manropeTextTheme(baseTextTheme);
    final displayTextTheme = GoogleFonts.soraTextTheme(baseTextTheme);

    final textTheme = bodyTextTheme.copyWith(
      displayLarge: displayTextTheme.displayLarge,
      displayMedium: displayTextTheme.displayMedium,
      displaySmall: displayTextTheme.displaySmall,
      headlineLarge: displayTextTheme.headlineLarge,
      headlineMedium: displayTextTheme.headlineMedium,
      headlineSmall: displayTextTheme.headlineSmall,
      titleLarge: displayTextTheme.titleLarge,
      titleMedium: displayTextTheme.titleMedium,
      titleSmall: displayTextTheme.titleSmall,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? AppColors.paperDark : AppColors.paper,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: isDark ? AppColors.paperRaisedDark : AppColors.paperRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: isDark ? AppColors.lineDark : AppColors.line),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.paperDark : AppColors.paper,
        foregroundColor: isDark ? AppColors.inkDark : AppColors.ink,
        elevation: 0,
        titleTextStyle: displayTextTheme.titleLarge?.copyWith(
          color: isDark ? AppColors.inkDark : AppColors.ink,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.lineDark : AppColors.line,
        space: 1,
      ),
    );
  }
}
