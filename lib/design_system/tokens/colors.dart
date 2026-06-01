import 'package:flutter/material.dart';

/// MetroSafar design colors - Material 3 based
class AppColors {
  AppColors._();

  // Brand colors
  static const Color metroIndigo = Color(0xFF4F46E5);
  static const Color warmCoral = Color(0xFFFB7185);
  static const Color mintSuccess = Color(0xFF10B981);
  static const Color goldPoints = Color(0xFFF59E0B);
  static const Color electricTeal = Color(0xFF00B8A9);
  static const Color neonLime = Color(0xFFC8F901);
  static const Color signalPink = Color(0xFFFF3D7F);
  static const Color cityInk = Color(0xFF101828);
  static const Color skyPop = Color(0xFF38BDF8);
  static const Color mangoPop = Color(0xFFFFB703);

  // Gradient pair for hero surfaces
  static const Color gradientStart = Color(0xFF00B8A9);
  static const Color gradientEnd = Color(0xFFFF3D7F);

  // Light theme
  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: electricTeal,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFE2FFFB),
    onPrimaryContainer: Color(0xFF003B36),
    secondary: signalPink,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFFFEBEF),
    onSecondaryContainer: Color(0xFF5E0824),
    tertiary: mangoPop,
    onTertiary: cityInk,
    tertiaryContainer: Color(0xFFFFF2C2),
    onTertiaryContainer: Color(0xFF4A3300),
    error: Color(0xFFEF4444),
    onError: Colors.white,
    errorContainer: Color(0xFFFEE2E2),
    onErrorContainer: Color(0xFF7F1D1D),
    surface: Color(0xFFFCFCF7),
    onSurface: cityInk,
    surfaceContainerHighest: Color(0xFFE9F2EF),
    onSurfaceVariant: Color(0xFF49454F),
    outline: Color(0xFF79747E),
    outlineVariant: Color(0xFFCAC7D0),
    scrim: Colors.black,
    inverseSurface: Color(0xFF313142),
    onInverseSurface: Color(0xFFFCFAFF),
    inversePrimary: neonLime,
    shadow: Colors.black,
    surfaceTint: electricTeal,
  );

  // Dark theme
  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFD0BCFF),
    onPrimary: Color(0xFF2D1B69),
    primaryContainer: Color(0xFF443A82),
    onPrimaryContainer: Color(0xFFEEF2FF),
    secondary: Color(0xFFFFB3C6),
    onSecondary: Color(0xFF62102D),
    secondaryContainer: Color(0xFF8A1D43),
    onSecondaryContainer: Color(0xFFFFD8E6),
    tertiary: Color(0xFFA5EDCC),
    onTertiary: Color(0xFF0F3D2A),
    tertiaryContainer: Color(0xFF1C5A41),
    onTertiaryContainer: Color(0xFFC9F0E4),
    error: Color(0xFFF87171),
    onError: Color(0xFF7F1D1D),
    errorContainer: Color(0xFFB42318),
    onErrorContainer: Color(0xFFFEE2E2),
    surface: Color(0xFF1F1F2E),
    onSurface: Color(0xFFF5F1F7),
    surfaceContainerHighest: Color(0xFF49454F),
    onSurfaceVariant: Color(0xFFC4C7D0),
    outline: Color(0xFF938F96),
    outlineVariant: Color(0xFF49454F),
    scrim: Colors.black,
    inverseSurface: Color(0xFFFBFAFF),
    onInverseSurface: Color(0xFF313142),
    inversePrimary: metroIndigo,
    shadow: Colors.black,
    surfaceTint: Color(0xFFD0BCFF),
  );

  // Semantic colors
  static const Color warning = Color(0xFFFF9800);
  static const Color info = Color(0xFF2196F3);
  static const Color success = mintSuccess;
  static const Color danger = Color(0xFFEF4444);

  // Neutral greys
  static const Color grey50 = Color(0xFFFAFAFA);
  static const Color grey100 = Color(0xFFF3F4F6);
  static const Color grey200 = Color(0xFFE5E7EB);
  static const Color grey300 = Color(0xFFD1D5DB);
  static const Color grey400 = Color(0xFF9CA3AF);
  static const Color grey500 = Color(0xFF6B7280);
  static const Color grey600 = Color(0xFF4B5563);
  static const Color grey700 = Color(0xFF374151);
  static const Color grey800 = Color(0xFF1F2937);
  static const Color grey900 = Color(0xFF111827);

  // Overlay
  static const Color scrimLight = Color(0x1F000000);
  static const Color scrimDark = Color(0x33000000);
}
