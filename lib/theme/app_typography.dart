import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTypography {
  static TextTheme get textTheme {
    return GoogleFonts.interTextTheme().copyWith(
      // Hero numbers / large display (e.g., calculator digits)
      displayLarge: GoogleFonts.inter(
        fontSize: 80,
        fontWeight: FontWeight.w200,
        letterSpacing: -3.0,
        height: 1.0,
      ),
      // Section large display
      displayMedium: GoogleFonts.inter(
        fontSize: 48,
        fontWeight: FontWeight.w300,
        letterSpacing: -1.5,
        height: 1.05,
      ),
      // Large title (e.g., "Messages", onboarding headline)
      headlineLarge: GoogleFonts.inter(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.1,
      ),
      // Section headlines
      headlineMedium: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      // Card/dialog headings
      headlineSmall: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.25,
      ),
      // Navigation bar title
      titleLarge: GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      // List item primary
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        height: 1.35,
      ),
      // Body copy
      bodyLarge: GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
        height: 1.5,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
      ),
      // Captions / metadata
      bodySmall: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
        letterSpacing: 0.0,
      ),
      // Button labels
      labelLarge: GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
    );
  }

  // Calculator
  static TextStyle get calculatorDisplay => GoogleFonts.inter(
        fontSize: 80,
        fontWeight: FontWeight.w200,
        letterSpacing: -2.0,
        height: 1.0,
      );

  static TextStyle get calculatorButton => GoogleFonts.inter(
        fontSize: 30,
        fontWeight: FontWeight.w400,
        height: 1.0,
      );

  // Chat input
  static TextStyle get messageInput => GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
        height: 1.4,
      );
}
