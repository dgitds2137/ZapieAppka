class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static const showPerformanceOverlay = bool.fromEnvironment(
    'SHOW_PERFORMANCE_OVERLAY',
    defaultValue: false,
  );

  static const persistedLoginDays = int.fromEnvironment(
    'PERSISTED_LOGIN_DAYS',
    defaultValue: 30,
  );

  static const googleAuthClientId = String.fromEnvironment(
    'GOOGLE_AUTH_CLIENT_ID',
    defaultValue: '',
  );

  static const facebookAppId = String.fromEnvironment(
    'FACEBOOK_APP_ID',
    defaultValue: '',
  );

  static bool get googleAuthConfigured => googleAuthClientId.trim().isNotEmpty;
  static bool get facebookAuthConfigured => facebookAppId.trim().isNotEmpty;
}
