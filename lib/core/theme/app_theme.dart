import 'package:flutter/material.dart';

abstract final class AppColors {
  static const navy = Color(0xFF153A5B);
  static const blue = Color(0xFF176B9D);
  static const sky = Color(0xFF38A3C5);
  static const teal = Color(0xFF159A8C);
  static const background = Color(0xFFF3F7FA);
  static const present = Color(0xFF168A5B);
  static const absent = Color(0xFFD54848);
  static const excused = Color(0xFFE09B26);
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      brightness: Brightness.light,
      primary: AppColors.blue,
      secondary: AppColors.teal,
      surface: Colors.white,
      error: AppColors.absent,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'NotoSansArabic',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.navy,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE1E9EF)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD8E2E9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD8E2E9)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        indicatorColor: Color(0xFFDCEEF6),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'NotoSansArabic',
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
