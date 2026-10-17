import 'package:flutter/material.dart';

// Paleta minimalista: grafite + um único acento prata.
const Color kAccent = Color(0xFFD8D9DE);
const Color kMuted = Color(0xFF8A8B92);
const Color kBg = Color(0xFF0B0B0C);
const Color kCard = Color(0xFF18181B);
const Color kCardTop = Color(0xFF1F1F23);
const Color kBorder = Color(0xFF2B2B30);
const Color kOk = Color(0xFF4ADE80);
const Color kErr = Color(0xFFF87171);

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: kAccent,
    onPrimary: Color(0xFF0B0B0C),
    secondary: kAccent,
    surface: kBg,
    onSurface: Color(0xFFEDEDEF),
    error: kErr,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 44,
      titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF0F0F11),
      height: 52,
      indicatorColor: Colors.white.withValues(alpha: 0.10),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: const Color(0xFF0F0F11),
      indicatorColor: Colors.white.withValues(alpha: 0.10),
      minWidth: 56,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF26262B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
