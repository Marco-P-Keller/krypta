import 'package:flutter/material.dart';

abstract final class AppColors {
  // Primary palette
  static const Color primary = Color(0xFF2C7BE5);
  static const Color primaryLight = Color(0xFF5DA4F2);
  static const Color primaryDark = Color(0xFF1A5BBF);

  // Surfaces
  static const Color backgroundDark = Color(0xFF0D0D0F);
  static const Color surfaceDark = Color(0xFF1A1A1E);
  static const Color surfaceElevatedDark = Color(0xFF242429);
  static const Color cardDark = Color(0xFF1E1E23);

  static const Color backgroundLight = Color(0xFFF8F9FA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFF0F2F5);
  static const Color cardLight = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimaryDark = Color(0xFFF5F5F7);
  static const Color textSecondaryDark = Color(0xFF8E8E93);
  static const Color textTertiaryDark = Color(0xFF636366);

  static const Color textPrimaryLight = Color(0xFF1C1C1E);
  static const Color textSecondaryLight = Color(0xFF636366);
  static const Color textTertiaryLight = Color(0xFF8E8E93);

  // Calculator specific
  static const Color calculatorBg = Color(0xFF000000);
  static const Color calculatorDisplay = Color(0xFFFFFFFF);
  static const Color calculatorButtonDark = Color(0xFF333333);
  static const Color calculatorButtonLight = Color(0xFFA5A5A5);
  static const Color calculatorButtonAccent = Color(0xFFFF9F0A);
  static const Color calculatorButtonAccentPressed = Color(0xFFFFCC80);

  // Status
  static const Color success = Color(0xFF30D158);
  static const Color warning = Color(0xFFFFD60A);
  static const Color error = Color(0xFFFF453A);
  static const Color destructive = Color(0xFFFF3B30);

  // Messenger
  static const Color messageSent = Color(0xFF2C7BE5);
  static const Color messageReceived = Color(0xFF2C2C2E);
  static const Color messageReceivedLight = Color(0xFFE9ECEF);
  static const Color online = Color(0xFF30D158);

  // Borders & Dividers
  static const Color dividerDark = Color(0xFF38383A);
  static const Color dividerLight = Color(0xFFE5E5EA);
}
