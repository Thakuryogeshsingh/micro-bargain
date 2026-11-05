class AppConfig {
  AppConfig._();

  // Android emulator reaches the host machine at 10.0.2.2. For a phone on Wi-Fi or production, pass
  // --dart-define=API_BASE_URL=https://your-domain/api/v1
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  /// Server root for web pages such as the privacy policy (the API URL without /api/v1).
  static String get siteUrl => apiBaseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');

  static const int defaultSearchRadiusMeters = 2000;
  static const List<int> searchRadiiMeters = [1000, 2000, 5000, 10000];

  // Used when location permission is denied: Bharatpur city centre.
  static const double fallbackLatitude = 27.2152;
  static const double fallbackLongitude = 77.4890;

  /// The pilot city. People farther than [serviceAreaKm] from it are shown its shops (nothing exists near them yet).
  static const String serviceCity = 'Bharatpur';
  static const double serviceAreaKm = 40;
}
