import 'dart:io';

import 'package:flutter/foundation.dart';

/// Backend base URLs. MetroSafar talks to **two** backends:
///
///  • [baseUrl]     — the app backend (home, rewards, profile, games, trip,
///                    streak, wallet). Injected via METROSAFAR_API_BASE_URL.
///  • [ondcBaseUrl] — the ONDC / Beckn mobility backend that fulfils ticket
///                    booking (search / select / init / confirm, payments).
///                    Injected via METROSAFAR_ONDC_BASE_URL.
///
/// They live on different hosts, so the booking flow and the rest of the app
/// must not share one URL — that is why booking has its own getter.
///
/// Resolution order (identical for both):
///   1. `--dart-define=<NAME>=...` (set by build_release.sh / CI)
///   2. localhost when running under `flutter test`
///   3. Release: **hard-fail** — never fall back to a hardcoded URL, so a build
///      that forgot the dart-define cannot silently ship the wrong backend.
///   4. Debug/profile only: a known URL for convenience.
class ApiConfig {
  // App backend.
  static const String _envBaseUrl =
      String.fromEnvironment('METROSAFAR_API_BASE_URL');
  static const String _debugAppBackend =
      'https://metrosafar-backend-pxx5jjbiyq-el.a.run.app';

  // ONDC / Beckn mobility backend.
  static const String _envOndcBaseUrl =
      String.fromEnvironment('METROSAFAR_ONDC_BASE_URL');
  static const String _debugOndcBackend = 'https://ondc.metrosafar.in';

  /// App backend base URL (everything except ticket booking).
  static String get baseUrl =>
      _resolve(_envBaseUrl, _debugAppBackend, 'METROSAFAR_API_BASE_URL');

  /// ONDC mobility backend base URL (ticket booking only).
  static String get ondcBaseUrl =>
      _resolve(_envOndcBaseUrl, _debugOndcBackend, 'METROSAFAR_ONDC_BASE_URL');

  static String _resolve(String envValue, String debugFallback, String define) {
    if (envValue.isNotEmpty) {
      _assertSecure(envValue);
      return envValue;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      // Only tests may talk to localhost. Anything else is a real device or CI
      // where the backend must be reached over HTTPS.
      return Platform.isAndroid
          ? 'http://10.0.2.2:8080'
          : 'http://127.0.0.1:8080';
    }

    if (kReleaseMode) {
      throw StateError(
        '$define was not supplied to a release build. '
        'Ship via scripts/build_release.sh which passes --dart-define.',
      );
    }

    _assertSecure(debugFallback);
    return debugFallback;
  }

  static void _assertSecure(String url) {
    if (!url.startsWith('https://')) {
      throw StateError('Backend URL must be HTTPS: $url');
    }
  }
}
