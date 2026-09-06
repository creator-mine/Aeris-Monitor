import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const List<Color> accentColors = [
    Color(0xFF2196F3), // Синий
    Color(0xFF009688), // Бирюзовый
    Color(0xFF4CAF50), // Зелёный
    Color(0xFF9C27B0), // Фиолетовый
    Color(0xFFFF9800), // Оранжевый
    Color(0xFFF44336), // Красный
  ];

  static const List<String> accentColorNames = [
    'Синий',
    'Бирюзовый',
    'Зелёный',
    'Фиолетовый',
    'Оранжевый',
    'Красный',
  ];

  static const Color primaryColor = Color(0xFF2196F3);
  static const Color secondaryColor = Color(0xFF4CAF50);
  static const Color accentColor = Color(0xFFFF9800);
  static const Color errorColor = Color(0xFFF44336);
  static const Color successColor = Color(0xFF4CAF50);
  static const Color warningColor = Color(0xFFFF9800);
  static const Color infoColor = Color(0xFF2196F3);

  static ThemeData getTheme(int colorIndex, bool darkMode) {
    final color = accentColors[colorIndex.clamp(0, accentColors.length - 1)];
    final brightness = darkMode ? Brightness.dark : Brightness.light;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: color,
      brightness: brightness,
    );

    final textTheme = darkMode
        ? GoogleFonts.nunitoTextTheme(ThemeData.dark().textTheme)
        : GoogleFonts.nunitoTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: color,
      colorScheme: colorScheme,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: darkMode ? Colors.white : Colors.black87,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  static BoxDecoration cardDecoration({bool darkMode = false}) => BoxDecoration(
        color: darkMode ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      );

  static BoxDecoration get gradientDecoration => BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryColor.withOpacity(0.8),
            primaryColor.withOpacity(0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      );
}
