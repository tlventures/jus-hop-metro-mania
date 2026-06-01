import 'package:flutter/material.dart';

/// MetroSafar border radius tokens
class AppRadius {
  AppRadius._();

  // Base values
  static const double radiusXS = 4.0;
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 20.0;
  static const double radiusXXL = 24.0;
  static const double radius2XL = 32.0;
  static const double radiusFull = 999.0;

  // BorderRadius objects
  static const BorderRadius borderRadiusXS = BorderRadius.all(Radius.circular(radiusXS));
  static const BorderRadius borderRadiusS = BorderRadius.all(Radius.circular(radiusS));
  static const BorderRadius borderRadiusM = BorderRadius.all(Radius.circular(radiusM));
  static const BorderRadius borderRadiusL = BorderRadius.all(Radius.circular(radiusL));
  static const BorderRadius borderRadiusXL = BorderRadius.all(Radius.circular(radiusXL));
  static const BorderRadius borderRadiusXXL = BorderRadius.all(Radius.circular(radiusXXL));
  static const BorderRadius borderRadius2XL = BorderRadius.all(Radius.circular(radius2XL));
  static const BorderRadius borderRadiusFull = BorderRadius.all(Radius.circular(radiusFull));

  // Specific shape patterns
  static const BorderRadius cardRadius = borderRadiusXL;
  static const BorderRadius containerRadius = borderRadiusXL;
  static const BorderRadius buttonRadius = borderRadiusFull;
  static const BorderRadius chipRadius = borderRadiusFull;
  static const BorderRadius smallComponentRadius = borderRadiusM;
}
