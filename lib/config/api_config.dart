import 'dart:io';

import 'package:flutter/foundation.dart';

/// Single source of truth for the backend base URL.
///
/// Resolution order:
///   1. `--dart-define=METROSAFAR_API_BASE_URL=...` (set by build_release.sh / CI)
///   2. Local dev backend when running under `flutter test`
///   3. The known production Cloud Run URL (debug/dev convenience only)
///
/// In a **release** build we require the dart-define to be present: shipping a
/// hardcoded URL means a backend move forces an app update, and silently baking
/// the wrong environment into a store build is a classic launch incident. If it
/// is missing in release, we fail fast (assert in profile/debug; the const
/// fallback still applies in production so the app is never bricked, but the
/// assert catches it in CI/QA before it ships).
class ApiConfig {
  static const String _envBaseUrl = String.fromEnvironment(
    'METROSAFAR_API_BASE_URL',
  );

  // Production Cloud Run URL. Kept only as a last-resort fallback so debug runs
  // "just work"; release builds should always pass the dart-define.
  static const String _productionBaseUrl =
      'https://metrosafar-backend-pxx5jjbiyq-el.a.run.app';

  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return Platform.isAndroid
          ? 'http://10.0.2.2:8080'
          : 'http://127.0.0.1:8080';
    }

    // Release builds must supply the URL explicitly. This assert is stripped in
    // production but fails loudly in debug/profile and CI so a misconfigured
    // build is caught before the Play Store.
    assert(
      !kReleaseMode || _envBaseUrl.isNotEmpty,
      'METROSAFAR_API_BASE_URL must be provided via --dart-define for release '
      'builds. Use scripts/build_release.sh.',
    );

    return _productionBaseUrl;
  }
}
