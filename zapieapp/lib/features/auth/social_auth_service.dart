import '../../core/config/app_config.dart';

enum SocialAuthProvider {
  google,
  facebook,
}

extension SocialAuthProviderX on SocialAuthProvider {
  String get label {
    switch (this) {
      case SocialAuthProvider.google:
        return 'Google';
      case SocialAuthProvider.facebook:
        return 'Facebook';
    }
  }
}

class SocialAuthUnavailableException implements Exception {
  const SocialAuthUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SocialAuthService {
  const SocialAuthService();

  bool isConfigured(SocialAuthProvider provider) {
    switch (provider) {
      case SocialAuthProvider.google:
        return AppConfig.googleAuthConfigured;
      case SocialAuthProvider.facebook:
        return AppConfig.facebookAuthConfigured;
    }
  }

  String preparationMessage(SocialAuthProvider provider) {
    switch (provider) {
      case SocialAuthProvider.google:
        return AppConfig.googleAuthConfigured
            ? 'Google login ma juz miejsce na konfiguracje klienta, ale wymaga jeszcze finalnego podpiecia SDK i weryfikacji tokena po stronie backendu.'
            : 'Google login jest przygotowany w UI i konfiguracji, ale najpierw ustaw GOOGLE_AUTH_CLIENT_ID oraz docelowa konfiguracje OAuth dla aplikacji.';
      case SocialAuthProvider.facebook:
        return AppConfig.facebookAuthConfigured
            ? 'Facebook login ma juz miejsce na konfiguracje aplikacji, ale wymaga jeszcze finalnego podpiecia SDK i weryfikacji tokena po stronie backendu.'
            : 'Facebook login jest przygotowany w UI i konfiguracji, ale najpierw ustaw FACEBOOK_APP_ID oraz docelowa konfiguracje OAuth dla aplikacji.';
    }
  }

  Future<void> authenticate(SocialAuthProvider provider) async {
    throw SocialAuthUnavailableException(preparationMessage(provider));
  }
}
