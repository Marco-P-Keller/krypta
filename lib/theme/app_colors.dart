import 'package:flutter/material.dart';

abstract final class AppColors {
  // Primary palette
  static const Color primary = Color(0xFF5B7FFF);
  static const Color primaryLight = Color(0xFF8BA4FF);
  static const Color primaryDark = Color(0xFF3A5AE0);
  static const Color accent = Color(0xFF7C5CFC);

  // Surfaces
  static const Color backgroundDark = Color(0xFF0A0A0F);
  static const Color surfaceDark = Color(0xFF12121A);
  static const Color surfaceElevatedDark = Color(0xFF1C1C28);
  static const Color cardDark = Color(0xFF181822);

  static const Color backgroundLight = Color(0xFFF6F7FB);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFEEF0F6);
  static const Color cardLight = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimaryDark = Color(0xFFF0F0F5);
  static const Color textSecondaryDark = Color(0xFF8A8A9A);
  static const Color textTertiaryDark = Color(0xFF55556A);

  static const Color textPrimaryLight = Color(0xFF1A1A2E);
  static const Color textSecondaryLight = Color(0xFF6B6B80);
  static const Color textTertiaryLight = Color(0xFF9999AD);

  // Calculator specific
  static const Color calculatorBg = Color(0xFF000000);
  static const Color calculatorDisplay = Color(0xFFFFFFFF);
  static const Color calculatorButtonDark = Color(0xFF333333);
  static const Color calculatorButtonLight = Color(0xFFA5A5A5);
  static const Color calculatorButtonAccent = Color(0xFFFF9F0A);
  static const Color calculatorButtonAccentPressed = Color(0xFFFFCC80);

  // Status
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFFD54F);
  static const Color error = Color(0xFFFF4757);
  static const Color destructive = Color(0xFFFF3B4A);

  // Messenger bubbles
  static const Color messageSentStart = Color(0xFF5B7FFF);
  static const Color messageSentEnd = Color(0xFF7C5CFC);
  static const Color messageSent = Color(0xFF5B7FFF);
  static const Color messageReceived = Color(0xFF1E1E2D);
  static const Color messageReceivedLight = Color(0xFFE8EAF2);
  static const Color online = Color(0xFF34C759);

  // Borders & Dividers
  static const Color dividerDark = Color(0xFF2A2A3A);
  static const Color dividerLight = Color(0xFFE0E2EA);
}
