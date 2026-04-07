import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme = const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF005D5B),
      onPrimary: Colors.white,
      secondary: Color(0xFF1A7F92),
      onSecondary: Colors.white,
      error: Color(0xFFB3261E),
      onError: Colors.white,
      surface: Color(0xFFF7F9FC),
      onSurface: Color(0xFF1B1E28),
    );
    return _baseTheme(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFFF2F6FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF53D1CD),
      onPrimary: Color(0xFF003634),
      secondary: Color(0xFF72D6EE),
      onSecondary: Color(0xFF003643),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      surface: Color(0xFF10151D),
      onSurface: Color(0xFFE5E8F0),
    );
    return _baseTheme(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0B1017),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  static ThemeData _baseTheme(ColorScheme scheme) {
    final baseTextTheme = ThemeData(brightness: scheme.brightness).textTheme;
    final textTheme = GoogleFonts.spaceGroteskTextTheme(baseTextTheme).copyWith(
      bodyLarge: GoogleFonts.dmSans(
        textStyle: baseTextTheme.bodyLarge,
        fontSize: 16,
        height: 1.4,
      ),
      bodyMedium: GoogleFonts.dmSans(
        textStyle: baseTextTheme.bodyMedium,
        fontSize: 14,
        height: 1.35,
      ),
      labelLarge: GoogleFonts.dmSans(
        textStyle: baseTextTheme.labelLarge,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.spaceGrotesk(
        textStyle: baseTextTheme.titleLarge,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.spaceGrotesk(
        textStyle: baseTextTheme.headlineMedium,
        fontWeight: FontWeight.w700,
      ),
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData.fromDefaults(
        brightness: scheme.brightness,
        secondaryColor: scheme.primaryContainer,
        labelStyle: textTheme.labelLarge!,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.fixed),
    );
  }
}
