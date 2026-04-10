import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../router/app_router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _backgroundAsset =
      'assets/images/background_big_ingredients_darker.png';
  static const _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

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
      final response = await http
          .post(
            uri,
            headers: const {
              'Accept': 'application/json',
            },
            body: {
              'email': email,
              'password': encodedPassword,
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = response.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(response.body) as Map<String, dynamic>;

        return _LoginResult.success(
          jwt: body['jwt']?.toString(),
          sessionToken: body['session_token']?.toString(),
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
        'Brak polaczenia z backendem. Sprawdz czy FastAPI dziala pod http://127.0.0.1:8000.',
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

    Navigator.pushReplacementNamed(context, AppRoutes.dashboard, arguments: {
      'email': emailController.text.trim(),
      'jwt': result.jwt,
      'sessionToken': result.sessionToken,
    });
  }

  void fillDemoCredentials() {
    emailController.text = 'demo@zapieapp.pl';
    passwordController.text = 'Haslo123!';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_pizza_outlined,
                              size: 56,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Logowanie',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Zaloguj sie do panelu i rozpocznij prace z aplikacja.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFFD6C4B8),
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              decoration: const InputDecoration(
                                labelText: 'E-mail',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                              validator: (value) {
                                final email = value?.trim() ?? '';
                                if (email.isEmpty) {
                                  return 'Podaj adres e-mail.';
                                }
                                if (!email.contains('@') || !email.contains('.')) {
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
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) {
                                if (!loading) {
                                  submit();
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Haslo',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: loading
                                      ? null
                                      : () {
                                          setState(() {
                                            obscurePassword = !obscurePassword;
                                          });
                                        },
                                  icon: Icon(
                                    obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
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
                              child: Text(
                                loading ? 'Logowanie...' : 'Zaloguj sie',
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: loading ? null : fillDemoCredentials,
                              child: const Text('Wypelnij dane demo'),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Dane testowe: demo@zapieapp.pl / Haslo123!',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFFD6C4B8),
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
  })  : isSuccess = true,
        message = null;

  const _LoginResult.failure(this.message)
      : isSuccess = false,
        jwt = null,
        sessionToken = null;

  final bool isSuccess;
  final String? message;
  final String? jwt;
  final String? sessionToken;
}
