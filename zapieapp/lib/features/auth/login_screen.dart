import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../data/local/session_persistence.dart';
import '../../data/models/auth_session.dart';
import '../../router/app_router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _backgroundAsset =
      'assets/images/background_big_ingredients_darker.png';
  static const _heroAsset =
      'assets/images/BrancMadeImages/bannerHorizontal.png';
  static const _watermarkAsset =
      'assets/images/BrancMadeImages/LogoCorner.png';
  static const _apiBaseUrl = AppConfig.apiBaseUrl;

  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;
  bool obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
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

  Future<void> submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => loading = true);

    final result = await authenticate(
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
          content: Text(result.message ?? 'Logowanie nie powiodlo sie.'),
        ),
      );
      return;
    }

    final authSession = AuthSession(
      email: emailController.text.trim(),
      jwt: result.jwt,
      sessionToken: result.sessionToken,
      role: result.role,
      authProvider: 'password',
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
    final heroHeight = compact ? 172.0 : 196.0;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(_backgroundAsset),
            fit: BoxFit.cover,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xE6100C0A),
                const Color(0xD916100E),
                theme.colorScheme.surface,
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
                          color: const Color(0xED15110F),
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
                                SizedBox(
                                  height: heroHeight,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.asset(
                                        _heroAsset,
                                        fit: BoxFit.cover,
                                        alignment: Alignment.center,
                                      ),
                                      const DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0x26000000),
                                              Color(0xB3120E0D),
                                              Color(0xF014100F),
                                            ],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            stops: [0, 0.58, 1],
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          18,
                                          18,
                                          18,
                                          18,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xD91C1715),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: const Color(
                                                    0x33FFD7B1,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                'Prosto z pieca',
                                                style: theme
                                                    .textTheme.labelMedium
                                                    ?.copyWith(
                                                      color: const Color(
                                                        0xFFFFD8B7,
                                                      ),
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              'Witaj z powrotem',
                                              style: theme
                                                  .textTheme.headlineMedium
                                                  ?.copyWith(
                                                    color: const Color(
                                                      0xFFFFF4EC,
                                                    ),
                                                    fontWeight:
                                                        FontWeight.w900,
                                                    height: 1.02,
                                                  ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Twoje miejsce od zapiekanek, lodow i smaku, ktory juz znasz.',
                                              style: theme
                                                  .textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color: const Color(
                                                      0xFFF0DDD0,
                                                    ),
                                                    height: 1.3,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    compact ? 18 : 24,
                                    22,
                                    compact ? 18 : 24,
                                    24,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'Logowanie',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                          color: const Color(0xFFF7EEE7),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Zaloguj sie do panelu i rozpocznij prace z aplikacja.',
                                        textAlign: TextAlign.center,
                                        style:
                                            theme.textTheme.bodyMedium?.copyWith(
                                          color: const Color(0xFFD6C4B8),
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 22),
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
                                        validator: (value) {
                                          final email = value?.trim() ?? '';
                                          if (email.isEmpty) {
                                            return 'Podaj adres e-mail.';
                                          }
                                          if (!email.contains('@') ||
                                              !email.contains('.')) {
                                            return 'Podaj poprawny adres e-mail.';
                                          }
                                          return null;
                                        },
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
                                          if (!loading) {
                                            submit();
                                          }
                                        },
                                        decoration: InputDecoration(
                                          labelText: 'Haslo',
                                          prefixIcon: const Icon(
                                            Icons.lock_outline,
                                          ),
                                          suffixIcon: IconButton(
                                            onPressed: loading
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
                                        onPressed: loading ? null : submit,
                                        style: FilledButton.styleFrom(
                                          minimumSize:
                                              const Size.fromHeight(52),
                                        ),
                                        child: Text(
                                          loading
                                              ? 'Logowanie...'
                                              : 'Zaloguj sie',
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
                                            onPressed: loading
                                                ? null
                                                : fillDemoCredentials,
                                          ),
                                          _QuickFillButton(
                                            label: 'Admin',
                                            onPressed: loading
                                                ? null
                                                : fillAdminCredentials,
                                          ),
                                          _QuickFillButton(
                                            label: 'Pracownik',
                                            onPressed: loading
                                                ? null
                                                : fillEmployeeCredentials,
                                          ),
                                          _QuickFillButton(
                                            label: 'Kierowca',
                                            onPressed: loading
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
