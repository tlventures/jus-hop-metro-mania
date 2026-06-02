import 'dart:io';

class ApiConfig {
  static const String _envBaseUrl = String.fromEnvironment(
    'METROSAFAR_API_BASE_URL',
  );
  // Backend in project metrosafar-20260517-223707 — runs the current code
  // (live catalog, redemptions, code pools, rate-limit split, CO₂ fix).
  static const String _productionBaseUrl =
      'https://metrosafar-backend-pxx5jjbiyq-el.a.run.app';

  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:8080';
      }

      return 'http://127.0.0.1:8080';
    }

    if (Platform.isAndroid || Platform.isIOS) {
      return _productionBaseUrl;
    }

    return _productionBaseUrl;
  }
}
