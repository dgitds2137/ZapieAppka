import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../data/local/session_persistence.dart';
import '../../data/models/auth_session.dart';
import '../../data/repositories/social_auth_repository.dart';
import '../../router/app_router.dart';

enum _LoginProvider {
  google(
    id: 'google',
    label: 'Google',
    icon: _ProviderIcon.google,
  ),
  apple(
    id: 'apple',
    label: 'Apple',
    icon: _ProviderIcon.apple,
  );

  const _LoginProvider({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final _ProviderIcon icon;
}

enum _ProviderIcon { google, apple }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _heroAsset =
      'assets/images/BrancMadeImages/bannerVertical.png';
  static const _characterAsset =
      'assets/images/BrancMadeImages/cartoonBoyNoBanner.png';
  static const _characterBannerAsset =
      'assets/images/BrancMadeImages/zapiekankiBanner.png';
  static const _watermarkAsset =
      'assets/images/BrancMadeImages/LogoCorner.png';
  static const _apiBaseUrl = AppConfig.apiBaseUrl;
  static final SocialAuthRepository _socialAuthRepository =
      HttpSocialAuthRepository(
    apiBaseUrl: _apiBaseUrl,
  );
  static GoogleSignIn? _mobileGoogleSignIn;

  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  bool loading = false;
  bool registering = false;
  bool obscurePassword = true;
  _LoginProvider? socialLoadingProvider;

  bool get isBusy => loading || socialLoadingProvider != null;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<_LoginResult> authenticate({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/login');
    final encodedPassword = base64Encode(utf8.encode(password));

    try {
      final response = await http.post(
        uri,
        headers: const {
          'Accept': 'application/json',
        },
        body: {
          'email': email,
          'password': encodedPassword,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = response.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(response.body) as Map<String, dynamic>;

        return _LoginResult.success(
          jwt: body['jwt']?.toString(),
          sessionToken: body['session_token']?.toString(),
          role: body['role']?.toString(),
          loyaltyPoints: _asInt(body['loyalty_points']) ?? 0,
        );
      }

      String message = 'Logowanie nie powiodlo sie.';
      if (response.body.isNotEmpty) {
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final detail = body['detail'];
          if (detail is String && detail.isNotEmpty) {
            message = detail;
          }
        } catch (_) {
          message = response.body;
        }
      }

      return _LoginResult.failure(message);
    } catch (_) {
      return const _LoginResult.failure(
        'Brak polaczenia z backendem. Sprawdz czy FastAPI dziala pod ${AppConfig.apiBaseUrl}.',
      );
    }
  }

  Future<_LoginResult> registerAccount({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/register');
    final encodedPassword = base64Encode(utf8.encode(password));

    try {
      final response = await http.post(
        uri,
        headers: const {
          'Accept': 'application/json',
        },
        body: {
          'email': email,
          'password': encodedPassword,
          if (name.trim().isNotEmpty) 'name': name.trim(),
          if (phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = response.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(response.body) as Map<String, dynamic>;

        return _LoginResult.success(
          jwt: body['jwt']?.toString(),
          sessionToken: body['session_token']?.toString(),
          role: body['role']?.toString(),
          loyaltyPoints: _asInt(body['loyalty_points']) ?? 0,
        );
      }

      String message = 'Rejestracja nie powiodla sie.';
      if (response.body.isNotEmpty) {
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final detail = body['detail'];
          if (detail is String && detail.isNotEmpty) {
            message = detail;
          }
        } catch (_) {
          message = response.body;
        }
      }

      return _LoginResult.failure(message);
    } catch (_) {
      return const _LoginResult.failure(
        'Brak polaczenia z backendem. Sprawdz czy FastAPI dziala pod ${AppConfig.apiBaseUrl}.',
      );
    }
  }

  Future<bool> openProviderAuthorization({
    required _LoginProvider provider,
  }) async {
    final authStart = switch (provider) {
      _LoginProvider.google => await _socialAuthRepository.startGoogleAuth(
          email: null,
          redirectUri: _redirectUriFor(provider),
        ),
      _LoginProvider.apple => await _socialAuthRepository.startAppleAuth(
          email: null,
          redirectUri: _redirectUriFor(provider),
        ),
    };
    final uri = Uri.parse(authStart.authorizationUrl);
    return launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_self' : null,
    );
  }

  bool get _useNativeGoogleOnAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  GoogleSignIn _getMobileGoogleSignIn() {
    final existing = _mobileGoogleSignIn;
    if (existing != null) {
      return existing;
    }
    final client = GoogleSignIn(
      serverClientId:
          AppConfig.googleAuthClientId.isEmpty ? null : AppConfig.googleAuthClientId,
    );
    _mobileGoogleSignIn = client;
    return client;
  }

  Future<void> _finishSocialSession(AuthSession authSession) async {
    await SessionPersistence.saveAuthSession(
      authSession,
      lifetime: Duration(days: AppConfig.persistedLoginDays),
    );

    if (!mounted) {
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      AppRoutes.dashboard,
      arguments: authSession.toRouteArgs(),
    );
  }

  Future<AuthSession> _authenticateGoogleOnAndroid() async {
    final account = await _getMobileGoogleSignIn().signIn();
    if (account == null) {
      throw Exception('Logowanie Google anulowane.');
    }
    final authentication = await account.authentication;
    final idToken = authentication.idToken;
    if (idToken == null || idToken.trim().isEmpty) {
      throw Exception(
        'Google nie zwrocilo ID tokenu dla backendu. Sprawdz konfiguracje Android OAuth.',
      );
    }

    return _socialAuthRepository.completeGoogleMobileAuth(
      idToken: idToken,
      email: account.email,
    );
  }

  Future<void> submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => loading = true);

    final result = registering
        ? await registerAccount(
            email: emailController.text.trim(),
            password: passwordController.text,
            name: nameController.text,
            phone: phoneController.text,
          )
        : await authenticate(
            email: emailController.text.trim(),
            password: passwordController.text,
          );

    if (!mounted) {
      return;
    }

    setState(() => loading = false);

    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message ??
                (registering
                    ? 'Rejestracja nie powiodla sie.'
                    : 'Logowanie nie powiodlo sie.'),
          ),
        ),
      );
      return;
    }

    await _finishLogin(
      email: emailController.text.trim(),
      providerId: 'password',
      result: result,
    );
  }

  Future<void> submitProvider(_LoginProvider provider) async {
    if (provider == _LoginProvider.google &&
        _useNativeGoogleOnAndroid &&
        AppConfig.googleAuthClientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Brakuje GOOGLE_AUTH_CLIENT_ID do natywnego logowania Google na Androidzie.',
          ),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => socialLoadingProvider = provider);

    String? providerError;
    AuthSession? nativeGoogleSession;
    bool opened = false;
    try {
      if (provider == _LoginProvider.google && _useNativeGoogleOnAndroid) {
        nativeGoogleSession = await _authenticateGoogleOnAndroid();
      } else {
        opened = await openProviderAuthorization(
          provider: provider,
        );
      }
    } catch (error) {
      providerError = error.toString();
    }

    if (!mounted) {
      return;
    }

    setState(() => socialLoadingProvider = null);

    if (providerError != null && providerError.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(providerError)),
      );
      return;
    }

    if (nativeGoogleSession != null) {
      await _finishSocialSession(nativeGoogleSession);
      return;
    }

    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nie udalo sie otworzyc oficjalnego logowania ${provider.label}.',
          ),
        ),
      );
    }
  }

  Future<void> _finishLogin({
    required String email,
    required String providerId,
    required _LoginResult result,
  }) async {
    final authSession = AuthSession(
      email: email,
      jwt: result.jwt,
      sessionToken: result.sessionToken,
      role: result.role,
      authProvider: providerId,
      loyaltyPoints: result.loyaltyPoints ?? 0,
    );

    await SessionPersistence.saveAuthSession(
      authSession,
      lifetime: Duration(days: AppConfig.persistedLoginDays),
    );

    if (!mounted) {
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      AppRoutes.dashboard,
      arguments: authSession.toRouteArgs(),
    );
  }

  void toggleAuthenticationMode(bool register) {
    if (isBusy || registering == register) {
      return;
    }

    setState(() {
      registering = register;
    });
  }

  void fillCustomerOneCredentials() {
    nameController.text = 'Klient Testowy 1';
    emailController.text = 'customer1@zapieapp.pl';
    phoneController.text = '500100100';
    passwordController.text = 'Haslo123!';
  }

  void fillCustomerTwoCredentials() {
    nameController.text = 'Klient Testowy 2';
    emailController.text = 'customer2@zapieapp.pl';
    phoneController.text = '500200200';
    passwordController.text = 'Haslo123!';
  }


  void fillCustomerThreeCredentials() {
    nameController.text = 'Klient Testowy 3';
    emailController.text = 'customer3@zapieapp.pl';
    phoneController.text = '500300300';
    passwordController.text = 'Haslo123!';
  }

  void fillDemoCredentials() {
    emailController.text = 'demo@zapieapp.pl';
    passwordController.text = 'Haslo123!';
  }

  void fillAdminCredentials() {
    emailController.text = 'admin@zapieapp.pl';
    passwordController.text = 'Admin123!';
  }

  void fillEmployeeCredentials() {
    emailController.text = 'employee@zapieapp.pl';
    passwordController.text = 'Employee123!';
  }

  void fillDriverCredentials() {
    emailController.text = 'driver@zapieapp.pl';
    passwordController.text = 'Driver123!';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final compact = media.size.width < 420;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(_heroAsset),
            fit: BoxFit.cover,
            alignment: Alignment(0, -0.78),
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xC20C0807),
                const Color(0xDA120C0B),
                const Color(0xF015100E),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 24,
                  right: -36,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.08,
                      child: Transform.rotate(
                        angle: 0.18,
                        child: Image.asset(
                          _watermarkAsset,
                          width: media.size.width < 520 ? 180 : 240,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xE9181311),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: const Color(0x24FFFFFF)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x2B000000),
                              blurRadius: 28,
                              offset: Offset(0, 16),
                            ),
                            BoxShadow(
                              color: Color(0x16FF7A1A),
                              blurRadius: 24,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    compact ? 18 : 24,
                                    20,
                                    compact ? 18 : 24,
                                    24,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        height: compact ? 248 : 322,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.start,
                                          children: [
                                            Image.asset(
                                              _characterBannerAsset,
                                              height: compact ? 104 : 136,
                                              fit: BoxFit.contain,
                                            ),
                                            const SizedBox(height: 0.6),
                                            Expanded(
                                              child: Image.asset(
                                                _characterAsset,
                                                fit: BoxFit.contain,
                                                alignment:
                                                    Alignment.topCenter,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Witaj z powrotem',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.headlineMedium
                                            ?.copyWith(
                                          color: const Color(0xFFFFF4EC),
                                          fontWeight: FontWeight.w900,
                                          height: 1.02,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Twoje miejsce od zapiekanek, lodow i smaku, ktory juz znasz.',
                                        textAlign: TextAlign.center,
                                        style:
                                            theme.textTheme.bodyMedium?.copyWith(
                                          color: const Color(0xFFF0DDD0),
                                          height: 1.3,
                                        ),
                                      ),
                                      const SizedBox(height: 22),
                                      Container(
                                        height: 1,
                                        color: const Color(0x16FFFFFF),
                                      ),
                                      const SizedBox(height: 22),
                                      Text(
                                        registering ? 'Rejestracja' : 'Logowanie',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                          color: const Color(0xFFF7EEE7),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        registering
                                            ? 'Utworz konto klienta i od razu przejdz do aplikacji.'
                                            : 'Zaloguj sie do panelu i rozpocznij prace z aplikacja.',
                                        textAlign: TextAlign.center,
                                        style:
                                            theme.textTheme.bodyMedium?.copyWith(
                                          color: const Color(0xFFD6C4B8),
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: FilledButton.tonal(
                                              onPressed: isBusy
                                                  ? null
                                                  : () =>
                                                      toggleAuthenticationMode(
                                                        false,
                                                      ),
                                              child: const Text('Mam konto'),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: isBusy
                                                  ? null
                                                  : () =>
                                                      toggleAuthenticationMode(
                                                        true,
                                                      ),
                                              child: const Text('Rejestracja'),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (registering) ...[
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: nameController,
                                          textInputAction: TextInputAction.next,
                                          autofillHints: const [
                                            AutofillHints.name,
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: 'Imie i nazwisko',
                                            prefixIcon: Icon(
                                              Icons.person_outline,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: phoneController,
                                          keyboardType: TextInputType.phone,
                                          textInputAction: TextInputAction.next,
                                          autofillHints: const [
                                            AutofillHints.telephoneNumber,
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: 'Telefon (opcjonalnie)',
                                            prefixIcon: Icon(
                                              Icons.phone_outlined,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 16),
                                      TextFormField(
                                        controller: emailController,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints.username,
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'E-mail',
                                          prefixIcon:
                                              Icon(Icons.mail_outline),
                                        ),
                                        validator: (value) =>
                                            _validateEmail(value?.trim() ?? ''),
                                      ),
                                      const SizedBox(height: 16),
                                      TextFormField(
                                        controller: passwordController,
                                        obscureText: obscurePassword,
                                        textInputAction: TextInputAction.done,
                                        autofillHints: const [
                                          AutofillHints.password,
                                        ],
                                        onFieldSubmitted: (_) {
                                          if (!isBusy) {
                                            submit();
                                          }
                                        },
                                        decoration: InputDecoration(
                                          labelText: 'Haslo',
                                          prefixIcon: const Icon(
                                            Icons.lock_outline,
                                          ),
                                          suffixIcon: IconButton(
                                            onPressed: isBusy
                                                ? null
                                                : () {
                                                    setState(() {
                                                      obscurePassword =
                                                          !obscurePassword;
                                                    });
                                                  },
                                            icon: Icon(
                                              obscurePassword
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                      .visibility_off_outlined,
                                            ),
                                          ),
                                        ),
                                        validator: (value) {
                                          final password = value ?? '';
                                          if (password.isEmpty) {
                                            return 'Podaj haslo.';
                                          }
                                          if (password.length < 8) {
                                            return 'Haslo musi miec co najmniej 8 znakow.';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 24),
                                      FilledButton(
                                        onPressed: isBusy ? null : submit,
                                        style: FilledButton.styleFrom(
                                          minimumSize:
                                              const Size.fromHeight(52),
                                        ),
                                        child: Text(
                                          loading
                                              ? (registering
                                                  ? 'Rejestracja...'
                                                  : 'Logowanie...')
                                              : (registering
                                                  ? 'Zarejestruj sie'
                                                  : 'Zaloguj sie'),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Row(
                                        children: [
                                          const Expanded(
                                            child: Divider(
                                              color: Color(0x24FFFFFF),
                                            ),
                                          ),
                                          Padding(
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                            child: Text(
                                              'albo',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: const Color(0xFFD6C4B8),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const Expanded(
                                            child: Divider(
                                              color: Color(0x24FFFFFF),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'Google otworzy konto zalogowane na urzadzeniu. Apple pozostaje logowaniem dodatkowym.',
                                        textAlign: TextAlign.center,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: const Color(0xFFD6C4B8),
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _ProviderLoginButton(
                                        provider: _LoginProvider.google,
                                        loading: socialLoadingProvider ==
                                            _LoginProvider.google,
                                        onPressed: isBusy
                                            ? null
                                            : () => submitProvider(
                                                  _LoginProvider.google,
                                                ),
                                      ),
                                      const SizedBox(height: 10),
                                      _ProviderLoginButton(
                                        provider: _LoginProvider.apple,
                                        loading: socialLoadingProvider ==
                                            _LoginProvider.apple,
                                        onPressed: isBusy
                                            ? null
                                            : () => submitProvider(
                                                  _LoginProvider.apple,
                                                ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Sesja logowania bedzie zapamietana na tym urzadzeniu przez okolo ${AppConfig.persistedLoginDays} dni.',
                                        textAlign: TextAlign.center,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: const Color(0xFFD6C4B8),
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          _QuickFillButton(
                                            label: 'Demo',
                                            onPressed: isBusy
                                                ? null
                                                : fillDemoCredentials,
                                          ),
                                          _QuickFillButton(
                                            label: 'Klient 1',
                                            onPressed: isBusy
                                                ? null
                                                : fillCustomerOneCredentials,
                                          ),
                                          _QuickFillButton(
                                            label: 'Klient 2',
                                            onPressed: isBusy
                                                ? null
                                                : fillCustomerTwoCredentials,
                                          ),
                                          _QuickFillButton(
                                            label: 'Klient 3',
                                            onPressed: isBusy
                                                ? null
                                                : fillCustomerThreeCredentials,
                                          ),
                                          _QuickFillButton(
                                            label: 'Admin',
                                            onPressed: isBusy
                                                ? null
                                                : fillAdminCredentials,
                                          ),
                                          _QuickFillButton(
                                            label: 'Pracownik',
                                            onPressed: isBusy
                                                ? null
                                                : fillEmployeeCredentials,
                                          ),
                                          _QuickFillButton(
                                            label: 'Kierowca',
                                            onPressed: isBusy
                                                ? null
                                                : fillDriverCredentials,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 18),
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1A1513),
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          border: Border.all(
                                            color: const Color(0x1FFFFFFF),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              'Szybkie loginy testowe',
                                              textAlign: TextAlign.center,
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                color:
                                                    const Color(0xFFFFD7B5),
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            _CredentialHint(
                                              label:
                                                  'Demo user: demo@zapieapp.pl / Haslo123!',
                                            ),
                                            const SizedBox(height: 6),
                                            _CredentialHint(
                                              label:
                                                  'Klient 1: customer1@zapieapp.pl / Haslo123!',
                                            ),
                                            const SizedBox(height: 6),
                                            _CredentialHint(
                                              label:
                                                  'Klient 2: customer2@zapieapp.pl / Haslo123!',
                                            ),
                                            const SizedBox(height: 6),
                                            _CredentialHint(
                                              label:
                                                  'Klient 3: customer3@zapieapp.pl / Haslo123!',
                                            ),
                                            const SizedBox(height: 6),
                                            _CredentialHint(
                                              label:
                                                  'Admin: admin@zapieapp.pl / Admin123!',
                                            ),
                                            const SizedBox(height: 6),
                                            _CredentialHint(
                                              label:
                                                  'Pracownik: employee@zapieapp.pl / Employee123!',
                                            ),
                                            const SizedBox(height: 6),
                                            _CredentialHint(
                                              label:
                                                  'Kierowca: driver@zapieapp.pl / Driver123!',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _redirectUriFor(_LoginProvider provider) {
  final configured = switch (provider) {
    _LoginProvider.google => AppConfig.authRedirectUri,
    _LoginProvider.apple => AppConfig.appleAuthRedirectUri,
  };
  return _resolveRuntimeRedirectUri(configured);
}

String _resolveRuntimeRedirectUri(String configuredRedirectUri) {
  if (!kIsWeb) {
    return configuredRedirectUri;
  }

  final parsed = Uri.tryParse(configuredRedirectUri);
  if (parsed != null &&
      (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    return configuredRedirectUri;
  }

  return '${Uri.base.origin}/auth/callback';
}

class _LoginResult {
  const _LoginResult.success({
    this.jwt,
    this.sessionToken,
    this.role,
    this.loyaltyPoints,
  })  : isSuccess = true,
        message = null;

  const _LoginResult.failure(this.message)
      : isSuccess = false,
        jwt = null,
        sessionToken = null,
        role = null,
        loyaltyPoints = null;

  final bool isSuccess;
  final String? message;
  final String? jwt;
  final String? sessionToken;
  final String? role;
  final int? loyaltyPoints;
}

class _ProviderLoginButton extends StatelessWidget {
  const _ProviderLoginButton({
    required this.provider,
    required this.loading,
    required this.onPressed,
  });

  final _LoginProvider provider;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _ProviderIconBadge(icon: provider.icon),
      label: Text(
        loading
            ? 'Laczenie z ${provider.label}...'
            : 'Kontynuuj z ${provider.label}',
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        foregroundColor: const Color(0xFFFFF4EC),
        side: const BorderSide(color: Color(0x33FFFFFF)),
        backgroundColor: const Color(0x1AFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _ProviderIconBadge extends StatelessWidget {
  const _ProviderIconBadge({required this.icon});

  final _ProviderIcon icon;

  @override
  Widget build(BuildContext context) {
    return switch (icon) {
      _ProviderIcon.google => const Text(
          'G',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF4285F4),
          ),
        ),
      _ProviderIcon.apple => const Icon(Icons.apple, size: 22),
    };
  }
}

class _QuickFillButton extends StatelessWidget {
  const _QuickFillButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        side: const BorderSide(color: Color(0x33FFB061)),
        foregroundColor: const Color(0xFFF2D6BE),
      ),
      child: Text(label),
    );
  }
}

class _CredentialHint extends StatelessWidget {
  const _CredentialHint({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFFD6C4B8),
            height: 1.35,
          ),
    );
  }
}

String? _validateEmail(String email) {
  if (email.isEmpty) {
    return 'Podaj adres e-mail.';
  }
  if (!email.contains('@') || !email.contains('.')) {
    return 'Podaj poprawny adres e-mail.';
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
