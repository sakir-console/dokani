import 'package:flutter/material.dart';

/// Colours used outside the Material colour scheme.
class AppColors {
  const AppColors._();

  static const brand = Color(0xFF059669);
  static const brandDark = Color(0xFF047857);
  static const surfaceMuted = Color(0xFFF1F5F9);
  static const border = Color(0xFFE2E8F0);
  static const textMuted = Color(0xFF64748B);
  static const warning = Color(0xFFB45309);
  static const warningSurface = Color(0xFFFFFBEB);
  static const danger = Color(0xFFB91C1C);
  static const dangerSurface = Color(0xFFFEF2F2);
}

/// One theme for the whole app: calm, high-contrast, large touch targets.
///
/// Animations are left at Material defaults and nothing decorative is
/// animated, which keeps the app smooth on low-end phones.
class AppTheme {
  const AppTheme._();

  static const _font = 'HindSiliguri';
  static const double touchTarget = 52;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      primary: AppColors.brand,
      surface: Colors.white,
      error: AppColors.danger,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: _font);

    // Bengali glyphs are taller than Latin ones; a little extra line height
    // stops vowel signs from colliding between lines.
    final text = base.textTheme.apply(bodyColor: const Color(0xFF0F172A), displayColor: const Color(0xFF0F172A)).copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.35),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.4),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        );

    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border(AppColors.border),
        enabledBorder: border(AppColors.border),
        focusedBorder: border(AppColors.brand, 2),
        errorBorder: border(AppColors.danger),
        focusedErrorBorder: border(AppColors.danger, 2),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(touchTarget),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(touchTarget),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48), textStyle: text.labelLarge),
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 14),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
