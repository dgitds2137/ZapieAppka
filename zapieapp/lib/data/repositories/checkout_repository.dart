import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/checkout_verification.dart';

abstract class CheckoutRepository {
  Future<CheckoutVerificationResponse> submitCheckoutVerification(
    CheckoutVerificationRequest request,
  );

  Future<CheckoutVerificationResponse?> fetchActiveCheckout({
    String? sessionToken,
    String? email,
  });
}

class HttpCheckoutRepository implements CheckoutRepository {
  HttpCheckoutRepository({
    http.Client? client,
    String? apiBaseUrl,
  })  : _client = client ?? http.Client(),
        _apiBaseUrl = apiBaseUrl ??
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://127.0.0.1:8000',
            );

  final http.Client _client;
  final String _apiBaseUrl;

  @override
  Future<CheckoutVerificationResponse> submitCheckoutVerification(
    CheckoutVerificationRequest request,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_apiBaseUrl/checkout/verification'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(request.toJson()),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Backend zwrocil ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Nieoczekiwany format odpowiedzi z /checkout/verification.');
    }

    return CheckoutVerificationResponse.fromJson(decoded);
  }

  @override
  Future<CheckoutVerificationResponse?> fetchActiveCheckout({
    String? sessionToken,
    String? email,
  }) async {
    final queryParameters = <String, String>{};
    if (sessionToken != null && sessionToken.isNotEmpty) {
      queryParameters['session_token'] = sessionToken;
    }
    if (email != null && email.isNotEmpty) {
      queryParameters['email'] = email;
    }

    final response = await _client
        .get(
          Uri.parse('$_apiBaseUrl/checkout/active').replace(
            queryParameters: queryParameters.isEmpty ? null : queryParameters,
          ),
          headers: const {
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Backend zwrocil ${response.statusCode}: ${response.body}');
    }

    if (response.body.trim().isEmpty || response.body.trim() == 'null') {
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Nieoczekiwany format odpowiedzi z /checkout/active.');
    }

    return CheckoutVerificationResponse.fromJson(decoded);
  }
}
