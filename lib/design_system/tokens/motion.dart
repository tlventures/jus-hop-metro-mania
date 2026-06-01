import 'package:flutter/material.dart';

/// MetroSafar motion & animation tokens
class AppMotion {
  AppMotion._();

  // Durations
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMed = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 500);
  static const Duration durationVerySlow = Duration(milliseconds: 800);

  // Easing curves
  static const Curve easeInOut = Curves.easeInOut;
  static const Curve easeOutCubic = Curves.easeOutCubic;
  static const Curve easeInCubic = Curves.easeInCubic;
  static const Curve easeInOutBack = Curves.easeInOutBack;
  static const Curve easeOutBack = Curves.easeOutBack;

  // Custom curves for Material 3 emphasis
  static const Curve emphasizedAccelerate = Curves.easeInCubic;
  static const Curve emphasizedDecelerate = Curves.easeOutCubic;
  static const Curve standardCurve = Curves.easeInOut;

  // Page transitions
  static const Duration pageTransitionDuration = Duration(milliseconds: 300);
  static const Curve pageTransitionCurve = Curves.easeOutCubic;

  // Micro-interactions
  static const Duration tapFeedbackDuration = Duration(milliseconds: 100);
  static const Duration hoverFeedbackDuration = Duration(milliseconds: 200);
}
