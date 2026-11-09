import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFEDF0D9);
  static const card = Color(0xFFFAF7EB);
  static const forest = Color(0xFF163F2E);
  static const sage = Color(0xFFF1F3E2);
  static const terracotta = Color(0xFFB7483E);
  static const ink = Color(0xFF163F2E);
  static const muted = Color(0xFF6D796D);
  static const border = Color(0xFFD1DBC6);
  static const delete = Color(0xFFB74657);
  static const separator = card;
  static const homeSensors = [
    Color(0xFF2B9DDD),
    Color(0xFFF0B735),
    Color(0xFFE9824B),
    Color(0xFF68B978),
  ];
  static const detailSensors = [
    Color(0xFF28AEF3),
    Color(0xFFF3BF39),
    Color(0xFFF27B5B),
    Color(0xFF69B878),
  ];
}

class AppTextStyles {
  static const heading = TextStyle(
    fontFamily: 'Pixelify Sans',
    fontWeight: FontWeight.w700,
    fontSize: 25,
    color: AppColors.ink,
  );
  static const plantName = TextStyle(
    fontFamily: 'Pixelify Sans',
    fontWeight: FontWeight.w700,
    fontSize: 22,
    color: Color(0xFF092C25),
  );
  static const readingLabel = TextStyle(
    fontFamily: 'Pixelify Sans',
    fontWeight: FontWeight.w700,
    fontSize: 19,
    color: AppColors.ink,
  );
  static const readingValue = TextStyle(
    fontFamily: 'Pixelify Sans',
    fontWeight: FontWeight.w700,
    fontSize: 24,
    color: AppColors.ink,
  );
  static const body = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    color: AppColors.ink,
  );
  static const caption = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    color: AppColors.muted,
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.forest,
      surface: AppColors.card,
      primary: AppColors.forest,
      error: AppColors.terracotta,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: base.textTheme.copyWith(
      headlineLarge: AppTextStyles.heading,
      headlineMedium: AppTextStyles.heading,
      titleLarge: AppTextStyles.plantName,
      bodyMedium: AppTextStyles.body,
      bodySmall: AppTextStyles.caption,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.card,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Pixelify Sans',
        fontWeight: FontWeight.w700,
        fontSize: 28,
        color: AppColors.ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.forest,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 61),
        textStyle: AppTextStyles.heading,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(fontFamily: 'Inter', color: Color(0xFF7D8578)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
  );
}
