import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../data/local/session_persistence.dart';
import '../../data/models/auth_session.dart';
import '../../router/app_router.dart';

class AuthCallbackScreen extends StatefulWidget {
  const AuthCallbackScreen({
    super.key,
    required this.callbackUri,
  });

  final Uri callbackUri;

  @override
  State<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<AuthCallbackScreen> {
  bool processing = true;
  String title = 'Konczymy logowanie';
  String message = 'Odbieramy odpowiedz od providera.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleCallback());
  }

  Future<void> _handleCallback() async {
    final error = widget.callbackUri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      _showError(
        widget.callbackUri.queryParameters['error_description'] ??
            'Provider zwrocil blad: $error',
      );
      return;
    }

    final code = widget.callbackUri.queryParameters['code'];
    final state = widget.callbackUri.queryParameters['state'];
    final stateData = _decodeState(state);
    final provider = widget.callbackUri.queryParameters['provider'] ??
        stateData['provider']?.toString();
    final email = stateData['email']?.toString();

    if (code == null || code.isEmpty || provider == null || provider.isEmpty) {
      _showError(
        'Brakuje kodu autoryzacyjnego albo providera w odpowiedzi logowania.',
      );
      return;
    }

    final result = await _exchangeCode(
      provider: provider,
      code: code,
      state: state,
      email: email,
    );

    if (!mounted) {
      return;
    }

    if (!result.isSuccess) {
      _showError(result.message ?? 'Nie udalo sie dokonczyc logowania.');
      return;
    }

    final authSession = AuthSession(
      email: result.email ?? email,
      jwt: result.jwt,
      sessionToken: result.sessionToken,
      role: result.role,
      authProvider: provider,
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

  Future<_CallbackExchangeResult> _exchangeCode({
    required String provider,
    required String code,
    required String? state,
    required String? email,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/$provider-auth/callback');

    try {
      final response = await http.post(
        uri,
        headers: const {'Accept': 'application/json'},
        body: {
          'code': code,
          if (state != null) 'state': state,
          if (email != null && email.isNotEmpty) 'email': email,
          'redirect_uri': AppConfig.authRedirectUri,
        },
      ).timeout(const Duration(seconds: 10));

      final body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _CallbackExchangeResult.success(
          email: body['email']?.toString(),
          jwt: body['jwt']?.toString(),
          sessionToken: body['session_token']?.toString(),
          role: body['role']?.toString(),
          loyaltyPoints: _asInt(body['loyalty_points']) ?? 0,
        );
      }

      return _CallbackExchangeResult.failure(
        body['detail']?.toString() ??
            body['error_description']?.toString() ??
            body['error']?.toString() ??
            'Backend odrzucil kod logowania.',
      );
    } catch (_) {
      return const _CallbackExchangeResult.failure(
        'Nie mozna polaczyc sie z backendem, aby wymienic kod logowania na sesje.',
      );
    }
  }

  void _showError(String errorMessage) {
    if (!mounted) {
      return;
    }
    setState(() {
      processing = false;
      title = 'Nie udalo sie zalogowac';
      message = errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (processing)
                  const Center(child: CircularProgressIndicator())
                else
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Color(0xFFD04437),
                  ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                if (!processing) ...[
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.pushReplacementNamed(
                      context,
                      AppRoutes.login,
                    ),
                    child: const Text('Wroc do logowania'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallbackExchangeResult {
  const _CallbackExchangeResult.success({
    this.email,
    this.jwt,
    this.sessionToken,
    this.role,
    this.loyaltyPoints,
  })  : isSuccess = true,
        message = null;

  const _CallbackExchangeResult.failure(this.message)
      : isSuccess = false,
        email = null,
        jwt = null,
        sessionToken = null,
        role = null,
        loyaltyPoints = null;

  final bool isSuccess;
  final String? message;
  final String? email;
  final String? jwt;
  final String? sessionToken;
  final String? role;
  final int? loyaltyPoints;
}

Map<String, Object?> _decodeState(String? value) {
  if (value == null || value.isEmpty) {
    return const {};
  }

  try {
    final normalized = base64Url.normalize(value);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
  } catch (_) {
    // The backend still receives the raw state and can reject it if needed.
  }
  return const {};
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
