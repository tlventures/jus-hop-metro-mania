import 'dart:io';

class ApiConfig {
  static const String _envBaseUrl = String.fromEnvironment(
    'METROSAFAR_API_BASE_URL',
  );
  static const String _productionBaseUrl =
      'https://metrosafar-backend-682046427985.asia-south1.run.app';

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
