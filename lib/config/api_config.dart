import 'dart:io';

import 'package:flutter/foundation.dart';

/// Single source of truth for the backend base URL.
///
/// Resolution order:
///   1. `--dart-define=METROSAFAR_API_BASE_URL=...` (set by build_release.sh / CI)
///   2. Local dev backend when running under `flutter test`
///   3. **Release: hard-fail** — refuse to fall back to a hardcoded URL so a
///      staging build that forgot the dart-define can't leak into prod.
///   4. Debug/profile only: known Cloud Run URL for convenience.
class ApiConfig {
  static const String _envBaseUrl = String.fromEnvironment(
    'METROSAFAR_API_BASE_URL',
  );

  static const String _debugFallbackUrl = 'https://ondc.metrosafar.in';

  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) {
      _assertSecure(_envBaseUrl);
      return _envBaseUrl;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      // Only tests may talk to localhost. Anything else is a real device or
      // CI where the backend must be reached over HTTPS.
      return Platform.isAndroid
          ? 'http://10.0.2.2:8080'
          : 'http://127.0.0.1:8080';
    }

    if (kReleaseMode) {
      throw StateError(
        'METROSAFAR_API_BASE_URL was not supplied to a release build. '
        'Ship via scripts/build_release.sh which passes --dart-define.',
      );
    }

    _assertSecure(_debugFallbackUrl);
    return _debugFallbackUrl;
  }

  static void _assertSecure(String url) {
    if (!url.startsWith('https://')) {
      throw StateError('METROSAFAR_API_BASE_URL must be HTTPS: $url');
    }
  }
}
