// lib/utils/constants.dart
//
// Generic app-wide constants. Station/city data has been removed from here
// and is now owned by CurrentCityProvider + CityRepository.
// Use `ref.read(cityStationsProvider)` wherever you need stations.

/// Constants used throughout the app
class Constants {
  static const String rewardsEndpoint = '/rewards';

  // Keep Google Maps integrations off unless a runtime key is supplied.
  static const bool useRealGoogleMapsApi = false;

  // Metro fare configuration (default — actual fares are per-city in city bundle)
  static const int baseAdultFare = 10;
  static const int maxFare = 60;

  // Maximum number of nearby stations to show
  static const int nearbyStationsLimit = 5;

  // REMOVED: metroStations, stationById, stationByName, findStation
  // These were Hyderabad-only hardcoded lists. Use CurrentCityProvider instead:
  //   final stations = ref.read(cityStationsProvider);
  //   final station  = stations.firstWhere((s) => s.id == id);
  //
  // Station lookups are now done via CurrentCityProvider.
  // See: lib/core/city/current_city_provider.dart → cityStationsProvider


  // Google Maps API settings
  static const String googleMapsApiKey =
      String.fromEnvironment('METROSAFAR_MAPS_API_KEY');

  // Google Maps API endpoints
  static const String googleMapsDistanceMatrixEndpoint =
      'https://maps.googleapis.com/maps/api/distancematrix/json';
  static const String googleMapsDirectionsEndpoint =
      'https://maps.googleapis.com/maps/api/directions/json';
  static const String googleMapsGeocodeEndpoint =
      'https://maps.googleapis.com/maps/api/geocode/json';

  // Location settings
  static const double locationSearchRadius = 5.0; // in kilometers
  static const int locationUpdateInterval = 60; // in seconds

  // App settings
  static const String appName = 'MetroSafar';
  static const String appVersion = '1.0.0';

  // Shared preferences keys
  static const String userKey = 'user_data';
  static const String authTokenKey = 'auth_token';
  static const String ticketsKey = 'user_tickets';
  static const String rewardsKey = 'user_rewards';
  static const String settingsKey = 'app_settings';
  static const String lastLocationKey = 'last_location';
  static const String recentStationsKey = 'recent_stations';

  // Metro line colors
  static const int redLineColor = 0xFFE53935;
  static const int blueLineColor = 0xFF1E88E5;
  static const int greenLineColor = 0xFF43A047;

  // Fare constants

  static const int baseChildFare = 25;


  // Reward points
  static const int signupPoints = 100;
  static const int videoWatchPoints = 20;
  static const int referralPoints = 50;

  // App URLs
  static const String privacyPolicyUrl = 'https://metrosafar.in/privacy';
  static const String termsAndConditionsUrl = 'https://metrosafar.in/terms';
  static const String helpUrl = 'https://metrosafar.in/support';

  // Contact information
  static const String supportEmail = 'support@metrosafar.in';
  static const String supportPhone = '+91 40 2322 5129';

  // Animation durations
  static const Duration splashDuration = Duration(seconds: 2);
  static const Duration fadeInDuration = Duration(milliseconds: 300);
  static const Duration slideInDuration = Duration(milliseconds: 400);

  // Map default zoom level
  static const double defaultMapZoom = 15.0;

  // Error messages
  static const String networkErrorMessage =
      'Please check your internet connection and try again.';
  static const String locationErrorMessage =
      'Unable to access your location. Please enable location services.';
  static const String apiKeyErrorMessage =
      'API key not configured. Please set a valid Google Maps API key.';

  // Success messages
  static const String pointsEarnedMessage = 'Congratulations! You\'ve earned rewards points!';

  // Feature flags
  static const bool enabledRewards = true;
  static const bool enabledLocationServices = true;
}
