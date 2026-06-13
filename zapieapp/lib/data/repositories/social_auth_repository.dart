import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../models/auth_session.dart';
import '../models/social_auth.dart';

abstract class SocialAuthRepository {
  Future<SocialAuthStart> startGoogleAuth({
    String? email,
    required String redirectUri,
  });

  Future<AuthSession> completeGoogleMobileAuth({
    required String idToken,
    String? email,
  });
}

class HttpSocialAuthRepository implements SocialAuthRepository {
  HttpSocialAuthRepository({
    http.Client? client,
    String? apiBaseUrl,
  })  : _client = client ?? http.Client(),
        _apiBaseUrl = apiBaseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _apiBaseUrl;

  @override
  Future<SocialAuthStart> startGoogleAuth({
    String? email,
    required String redirectUri,
  }) async {
    final response = await _client
        .get(
          Uri.parse('$_apiBaseUrl/google-auth/start').replace(
            queryParameters: {
              if (email != null && email.trim().isNotEmpty) 'email': email,
              'redirect_uri': redirectUri,
            },
          ),
          headers: const {
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractMessage(response));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Nieoczekiwany format odpowiedzi z /google-auth/start.');
    }

    return SocialAuthStart.fromJson(decoded);
  }

  @override
  Future<AuthSession> completeGoogleMobileAuth({
    required String idToken,
    String? email,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_apiBaseUrl/google-auth/mobile'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'id_token': idToken,
            if (email != null && email.trim().isNotEmpty) 'email': email,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractMessage(response));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Nieoczekiwany format odpowiedzi z /google-auth/mobile.');
    }

    return AuthSession(
      email: decoded['email']?.toString(),
      jwt: decoded['jwt']?.toString(),
      sessionToken: decoded['session_token']?.toString(),
      role: decoded['role']?.toString(),
      authProvider: 'google',
      loyaltyPoints: _asInt(decoded['loyalty_points']) ?? 0,
    );
  }

  String _extractMessage(http.Response response) {
    if (response.body.isEmpty) {
      return 'Backend zwrocil ${response.statusCode}.';
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail']?.toString();
        if (detail != null && detail.trim().isNotEmpty) {
          return detail.trim();
        }
      }
    } catch (_) {
      // Fall through to generic message.
    }

    return 'Backend zwrocil ${response.statusCode}: ${response.body}';
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
