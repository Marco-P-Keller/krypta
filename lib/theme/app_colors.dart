import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── Accent (one color, used with conviction) ──────────────────────────
  static const Color accent = Color(0xFF0A84FF); // iOS blue dark
  static const Color accentLight = Color(0xFF007AFF); // iOS blue light

  // ── Dark backgrounds (pure black to near-black) ───────────────────────
  static const Color backgroundDark = Color(0xFF000000);
  static const Color surfaceDark = Color(0xFF1C1C1E);
  static const Color surfaceElevatedDark = Color(0xFF2C2C2E);
  static const Color cardDark = Color(0xFF1C1C1E);

  // ── Light backgrounds ─────────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF2F2F7);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFE5E5EA);
  static const Color cardLight = Color(0xFFFFFFFF);

  // ── Dark text ─────────────────────────────────────────────────────────
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFF8E8E93);
  static const Color textTertiaryDark = Color(0xFF48484A);

  // ── Light text ────────────────────────────────────────────────────────
  static const Color textPrimaryLight = Color(0xFF000000);
  static const Color textSecondaryLight = Color(0xFF6C6C70);
  static const Color textTertiaryLight = Color(0xFFAEAEB2);

  // ── Calculator (pure iOS aesthetic) ───────────────────────────────────
  static const Color calculatorBg = Color(0xFF000000);
  static const Color calculatorDisplay = Color(0xFFFFFFFF);
  static const Color calculatorButtonDark = Color(0xFF1C1C1E);
  static const Color calculatorButtonLight = Color(0xFFD4D4D2);
  static const Color calculatorButtonAccent = Color(0xFFFF9F0A);
  static const Color calculatorButtonAccentPressed = Color(0xFFFFCC80);

  // ── Status ────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF30D158);
  static const Color warning = Color(0xFFFFD60A);
  static const Color error = Color(0xFFFF453A);
  static const Color destructive = Color(0xFFFF453A);

  // ── Messenger ─────────────────────────────────────────────────────────
  static const Color messageSent = Color(0xFF0A84FF);
  static const Color messageReceived = Color(0xFF1C1C1E);
  static const Color messageReceivedLight = Color(0xFFE9E9EB);
  static const Color online = Color(0xFF30D158);

  // ── Borders & Dividers (hairline) ─────────────────────────────────────
  static const Color dividerDark = Color(0xFF38383A);
  static const Color dividerLight = Color(0xFFC6C6C8);

  // ── Legacy aliases (keep for build compatibility) ─────────────────────
  static const Color primary = accent;
  static const Color primaryLight = Color(0xFF409CFF);
  static const Color primaryDark = Color(0xFF0060DF);
  static const Color messageSentStart = messageSent;
  static const Color messageSentEnd = messageSent;
}
