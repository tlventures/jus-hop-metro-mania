// lib/core/city/city_theme_provider.dart
//
// Derives a Flutter ColorScheme from the active city's brand tokens.
// Falls back to MetroSafar's default indigo if no city is loaded.
// Festival windows can override the accent color for limited-time theming.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design_system/theme.dart';
import '../../design_system/tokens/colors.dart';
import 'city_model.dart';
import 'current_city_provider.dart';

ColorScheme _cityColorScheme(City? city, Brightness brightness) {
  if (city == null) {
    // Default MetroSafar brand
    return brightness == Brightness.light
        ? AppColors.lightScheme
        : AppColors.darkScheme;
  }

  // Derive from city brand
  final primaryColor = Color(city.brand.primaryValue);
  final accentColor = Color(city.brand.accentValue);
  final surfaceVar = Color(city.brand.surfaceVariantValue);

  // Check for active festival — override accent
  final festival = city.activeFestival;
  final effectiveAccent = festival != null ? accentColor : accentColor;

  if (brightness == Brightness.light) {
    return ColorScheme(
      brightness: Brightness.light,
      primary: primaryColor,
      onPrimary: Colors.white,
      primaryContainer: surfaceVar,
      onPrimaryContainer: Color.lerp(primaryColor, Colors.black, 0.7)!,
      secondary: effectiveAccent,
      onSecondary: Colors.white,
      secondaryContainer: surfaceVar,
      onSecondaryContainer: Color.lerp(effectiveAccent, Colors.black, 0.7)!,
      tertiary: const Color(0xFF10B981),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFD1F4E8),
      onTertiaryContainer: const Color(0xFF0F3D2A),
      error: const Color(0xFFEF4444),
      onError: Colors.white,
      errorContainer: const Color(0xFFFEE2E2),
      onErrorContainer: const Color(0xFF7F1D1D),
      surface: const Color(0xFFFBFAFF),
      onSurface: const Color(0xFF1F1F2E),
      surfaceContainerHighest: surfaceVar,
      onSurfaceVariant: const Color(0xFF49454F),
      outline: const Color(0xFF79747E),
      outlineVariant: const Color(0xFFCAC7D0),
      scrim: Colors.black,
      inverseSurface: const Color(0xFF313142),
      onInverseSurface: const Color(0xFFFCFAFF),
      inversePrimary: Color.lerp(primaryColor, Colors.white, 0.6)!,
      shadow: Colors.black,
      surfaceTint: primaryColor,
    );
  } else {
    // Dark variant: lighten primary, darken surfaces
    final lightPrimary = Color.lerp(primaryColor, Colors.white, 0.55)!;
    return ColorScheme(
      brightness: Brightness.dark,
      primary: lightPrimary,
      onPrimary: Color.lerp(primaryColor, Colors.black, 0.7)!,
      primaryContainer: Color.lerp(primaryColor, Colors.black, 0.4)!,
      onPrimaryContainer: lightPrimary,
      secondary: Color.lerp(effectiveAccent, Colors.white, 0.5)!,
      onSecondary: Color.lerp(effectiveAccent, Colors.black, 0.6)!,
      secondaryContainer: Color.lerp(effectiveAccent, Colors.black, 0.4)!,
      onSecondaryContainer: Color.lerp(effectiveAccent, Colors.white, 0.5)!,
      tertiary: const Color(0xFF6EE7B7),
      onTertiary: const Color(0xFF0F3D2A),
      tertiaryContainer: const Color(0xFF1B5E40),
      onTertiaryContainer: const Color(0xFFD1F4E8),
      error: const Color(0xFFFCA5A5),
      onError: const Color(0xFF7F1D1D),
      errorContainer: const Color(0xFFB91C1C),
      onErrorContainer: const Color(0xFFFEE2E2),
      surface: const Color(0xFF1F1F2E),
      onSurface: const Color(0xFFF8F7FF),
      surfaceContainerHighest: const Color(0xFF2D2B3D),
      onSurfaceVariant: const Color(0xFFCAC4D0),
      outline: const Color(0xFF938F99),
      outlineVariant: const Color(0xFF49454F),
      scrim: Colors.black,
      inverseSurface: const Color(0xFFF3F0FF),
      onInverseSurface: const Color(0xFF1F1F2E),
      inversePrimary: primaryColor,
      shadow: Colors.black,
      surfaceTint: lightPrimary,
    );
  }
}

/// Provider that gives a city-derived ThemeData for light mode.
final cityLightThemeProvider = Provider<ThemeData>((ref) {
  final city = ref.watch(activeCityProvider);
  return AppTheme.fromColorScheme(_cityColorScheme(city, Brightness.light));
});

/// Provider that gives a city-derived ThemeData for dark mode.
final cityDarkThemeProvider = Provider<ThemeData>((ref) {
  final city = ref.watch(activeCityProvider);
  return AppTheme.fromColorScheme(_cityColorScheme(city, Brightness.dark));
});
