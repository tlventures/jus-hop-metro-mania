const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

const bool kIsProduction = bool.fromEnvironment(
  'dart.vm.product',
  defaultValue: false,
);
