import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const seedColor = Color(0xFFE66A2C);
  const surface = Color(0xFF15110F);
  const surfaceContainer = Color(0xFF211917);
  const background = Color(0xFF0B0807);
  const outline = Color(0xFF4A3832);
  const textOnDark = Color(0xFFF6E9DE);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.dark,
  ).copyWith(
    surface: surface,
    surfaceContainerHighest: surfaceContainer,
    outline: outline,
    onSurface: textOnDark,
    onPrimaryContainer: textOnDark,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xCC120E0D),
      foregroundColor: textOnDark,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A1412),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: seedColor, width: 1.4),
      ),
      labelStyle: const TextStyle(color: Color(0xFFD4C2B6)),
      prefixIconColor: const Color(0xFFD4C2B6),
      suffixIconColor: const Color(0xFFD4C2B6),
    ),
    cardTheme: const CardThemeData(
      elevation: 2,
      margin: EdgeInsets.zero,
      color: Color(0xE61A1513),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        side: BorderSide(color: Color(0x523C2B25)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: seedColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: textOnDark,
        side: const BorderSide(color: outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF201816),
      contentTextStyle: TextStyle(color: textOnDark),
    ),
  );
}
