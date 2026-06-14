import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../data/local/session_persistence.dart';
import '../../data/models/auth_session.dart';
import '../../router/app_router.dart';

class AuthCallbackScreen extends StatefulWidget {
  AuthCallbackScreen({
    super.key,
    required this.callbackUri,
    http.Client? httpClient,
    String? googleRedirectUri,
    String? appleRedirectUri,
  })  : httpClient = httpClient ?? _DefaultHttpClient(),
        googleRedirectUri = googleRedirectUri ?? AppConfig.authRedirectUri,
        appleRedirectUri = appleRedirectUri ?? AppConfig.appleAuthRedirectUri;

  final http.Client httpClient;

  final Uri callbackUri;
  final String googleRedirectUri;
  final String appleRedirectUri;

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
    final providerProfile = _decodeProviderProfile(
      widget.callbackUri.queryParameters['user'],
    );
    final provider = widget.callbackUri.queryParameters['provider'] ??
        stateData['provider']?.toString();
    final email = stateData['email']?.toString() ?? providerProfile.email;
    final name = providerProfile.displayName;

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
      name: name,
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
    required String? name,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/$provider-auth/callback');
    final redirectUri = _redirectUriForProvider(
      provider,
      googleRedirectUri: widget.googleRedirectUri,
      appleRedirectUri: widget.appleRedirectUri,
      callbackUri: widget.callbackUri,
    );

    try {
      final response = await _postCallbackExchange(
        uri,
        code,
        state,
        email,
        name,
        redirectUri,
      );

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

  Future<http.Response> _postCallbackExchange(
    Uri uri,
    String code,
    String? state,
    String? email,
    String? name,
    String redirectUri,
  ) {
    return widget.httpClient.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'code': code,
        if (state != null) 'state': state,
        if (email != null && email.isNotEmpty) 'email': email,
        if (name != null && name.isNotEmpty) 'name': name,
        'redirect_uri': redirectUri,
      }),
    ).timeout(const Duration(seconds: 10));
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

class _DefaultHttpClient extends http.BaseClient {
  _DefaultHttpClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final client = http.Client();
    return client.send(request);
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

class _ProviderProfile {
  const _ProviderProfile({
    this.email,
    this.displayName,
  });

  final String? email;
  final String? displayName;
}

Map<String, Object?> _decodeState(String? value) {
  if (value == null || value.isEmpty) {
    return const {};
  }

  Map<String, Object?>? tryDecodeSegment(String raw) {
    try {
      final normalized = base64Url.normalize(raw);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      // Ignore and continue with other state formats.
    }
    return null;
  }

  final directDecoded = tryDecodeSegment(value);
  if (directDecoded != null) {
    return directDecoded;
  }

  final parts = value.split('.');
  if (parts.length == 3) {
    final jwtPayload = tryDecodeSegment(parts[1]);
    if (jwtPayload != null) {
      return jwtPayload;
    }
  }

  try {
    final decoded = jsonDecode(value);
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

_ProviderProfile _decodeProviderProfile(String? value) {
  if (value == null || value.isEmpty) {
    return const _ProviderProfile();
  }

  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      return const _ProviderProfile();
    }

    final map = Map<String, Object?>.from(decoded);
    final email = map['email']?.toString().trim();
    final nameMap =
        map['name'] is Map ? Map<String, Object?>.from(map['name'] as Map) : null;
    final firstName = nameMap?['firstName']?.toString().trim();
    final lastName = nameMap?['lastName']?.toString().trim();
    final displayName = [
      if (firstName != null && firstName.isNotEmpty) firstName,
      if (lastName != null && lastName.isNotEmpty) lastName,
    ].join(' ').trim();

    return _ProviderProfile(
      email: email != null && email.isNotEmpty ? email : null,
      displayName: displayName.isNotEmpty ? displayName : null,
    );
  } catch (_) {
    return const _ProviderProfile();
  }
}

String _redirectUriForProvider(
  String provider, {
  required String googleRedirectUri,
  required String appleRedirectUri,
  Uri? callbackUri,
}) {
  final configured = switch (provider.trim().toLowerCase()) {
    'apple' => appleRedirectUri,
    'google' => googleRedirectUri,
    _ => googleRedirectUri,
  };
  return _resolveCallbackRedirectUri(
    configured,
    callbackUri: callbackUri,
  );
}

String _resolveCallbackRedirectUri(
  String configuredRedirectUri, {
  Uri? callbackUri,
}) {
  if (!kIsWeb) {
    return configuredRedirectUri;
  }

  final parsed = Uri.tryParse(configuredRedirectUri);
  if (parsed != null &&
      (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    return configuredRedirectUri;
  }

  final runtimeBase = (callbackUri != null && callbackUri.hasScheme)
      ? callbackUri
      : Uri.base;
  return '${runtimeBase.origin}/auth/callback';
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
