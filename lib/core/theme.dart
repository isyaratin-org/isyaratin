import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF146C74);
  static const background = Color(0xFFF4F8FA);
  static const text = Color(0xFF1F2937);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFEAF2F4);
  static const pale = Color(0xFFE6F3F5);
}

ThemeData buildTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Inter',
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: AppColors.background,
  textTheme: const TextTheme(
    headlineMedium: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      color: AppColors.text,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
    ),
    bodyLarge: TextStyle(fontSize: 14, height: 1.5, color: AppColors.text),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: AppColors.text),
    bodySmall: TextStyle(fontSize: 12, height: 1.5, color: AppColors.muted),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: AppColors.text,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: TextStyle(
      fontFamily: 'Inter',
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      foregroundColor: AppColors.primary,
      side: const BorderSide(color: AppColors.primary, width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
  ),
);
