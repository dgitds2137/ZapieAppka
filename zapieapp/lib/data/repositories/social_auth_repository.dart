import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../models/social_auth.dart';

abstract class SocialAuthRepository {
  Future<SocialAuthStart> startGoogleAuth({
    required String email,
    required String redirectUri,
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
    required String email,
    required String redirectUri,
  }) async {
    final response = await _client
        .get(
          Uri.parse('$_apiBaseUrl/google-auth/start').replace(
            queryParameters: {
              'email': email,
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
