import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFFF7F9FC);
  static const Color primary = Color(0xFF1F4E79);
  static const Color primarySoft = Color(0xFFE8F0F7);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color border = Color(0xFFE5E7EB);
  static const Color inputBorder = Color(0xFFD1D5DB);
  static const Color success = Color(0xFF047857);
  static const Color warning = Color(0xFFB45309);
  static const Color danger = Color(0xFFB91C1C);

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Arial',
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        surface: Colors.white,
      ),
    );
  }
}
