import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFFAF8F3);
  static const forest = Color(0xFF254F3D);
  static const sage = Color(0xFFE8EEE2);
  static const terracotta = Color(0xFFA45C43);
  static const ink = Color(0xFF253A30);
  static const muted = Color(0xFF617164);
  static const border = Color(0xFFD8DED3);
}

ThemeData buildAppTheme() {
  // Material 3 components + FlexColorScheme keep the whole UI on one design system.
  final base = FlexThemeData.light(
    colors: const FlexSchemeColor(
      primary: AppColors.forest,
      secondary: Color(0xFF52684C),
      tertiary: AppColors.terracotta,
    ),
    useMaterial3: true,
    subThemesData: const FlexSubThemesData(defaultRadius: 18),
  );
  final textTheme = base.textTheme.apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: base.colorScheme.copyWith(
      surface: AppColors.background,
      surfaceContainerLow: Colors.white,
      surfaceContainer: AppColors.sage,
      outlineVariant: AppColors.border,
    ),
    textTheme: textTheme.copyWith(
      headlineLarge: textTheme.headlineLarge?.copyWith(
        fontFamily: 'Georgia',
        fontFamilyFallback: const ['serif'],
        fontSize: 38,
        height: 1.15,
        letterSpacing: -1.2,
      ),
      headlineMedium: textTheme.headlineMedium?.copyWith(
        fontFamily: 'Georgia',
        fontFamilyFallback: const ['serif'],
        fontSize: 30,
        height: 1.2,
        letterSpacing: -.7,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.5),
      bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.5),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.forest,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 20,
        color: AppColors.forest,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
  );
}
