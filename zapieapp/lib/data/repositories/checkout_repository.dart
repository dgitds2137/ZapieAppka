import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../models/checkout_verification.dart';

abstract class CheckoutRepository {
  CheckoutVerificationResponse? get cachedActiveCheckout;

  void rememberActiveCheckout(CheckoutVerificationResponse? checkout);

  Future<CheckoutVerificationResponse> submitCheckoutVerification(
    CheckoutVerificationRequest request,
  );

  Future<CheckoutVerificationResponse?> fetchActiveCheckout({
    String? sessionToken,
    String? email,
  });

  Future<CheckoutVerificationResponse> confirmReceipt(
    CheckoutReceiptConfirmationRequest request,
  );

  Future<List<CheckoutChatMessage>> fetchOrderMessages({
    required int checkoutOrderId,
    String? sessionToken,
    String? email,
  });

  Future<CheckoutChatMessage> sendOrderMessage({
    required int checkoutOrderId,
    required CheckoutChatMessageCreateRequest request,
  });

  Future<void> markOrderMessagesRead({
    required int checkoutOrderId,
    required CheckoutChatMessagesReadRequest request,
  });
}

class HttpCheckoutRepository implements CheckoutRepository {
  HttpCheckoutRepository({
    http.Client? client,
    String? apiBaseUrl,
  })  : _client = client ?? http.Client(),
        _apiBaseUrl = apiBaseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _apiBaseUrl;
  CheckoutVerificationResponse? _cachedActiveCheckout;

  @override
  CheckoutVerificationResponse? get cachedActiveCheckout => _cachedActiveCheckout;

  @override
  void rememberActiveCheckout(CheckoutVerificationResponse? checkout) {
    _cachedActiveCheckout = checkout;
  }

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

    final checkout = CheckoutVerificationResponse.fromJson(decoded);
    rememberActiveCheckout(checkout);
    return checkout;
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
      rememberActiveCheckout(null);
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Nieoczekiwany format odpowiedzi z /checkout/active.');
    }

    final checkout = CheckoutVerificationResponse.fromJson(decoded);
    rememberActiveCheckout(checkout);
    return checkout;
  }

  @override
  Future<CheckoutVerificationResponse> confirmReceipt(
    CheckoutReceiptConfirmationRequest request,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_apiBaseUrl/checkout/confirm-receipt'),
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
      throw Exception('Nieoczekiwany format odpowiedzi z /checkout/confirm-receipt.');
    }

    final checkout = CheckoutVerificationResponse.fromJson(decoded);
    rememberActiveCheckout(
      checkout.status == 'completed' ? null : checkout,
    );
    return checkout;
  }

  @override
  Future<List<CheckoutChatMessage>> fetchOrderMessages({
    required int checkoutOrderId,
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
          Uri.parse('$_apiBaseUrl/checkout/orders/$checkoutOrderId/messages')
              .replace(
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

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception(
          'Nieoczekiwany format odpowiedzi z /checkout/orders/{id}/messages.');
    }

    return decoded
        .whereType<Map>()
        .map(
          (item) => CheckoutChatMessage.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<CheckoutChatMessage> sendOrderMessage({
    required int checkoutOrderId,
    required CheckoutChatMessageCreateRequest request,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_apiBaseUrl/checkout/orders/$checkoutOrderId/messages'),
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
      throw Exception(
        'Nieoczekiwany format odpowiedzi z /checkout/orders/{id}/messages.',
      );
    }

    return CheckoutChatMessage.fromJson(decoded);
  }

  @override
  Future<void> markOrderMessagesRead({
    required int checkoutOrderId,
    required CheckoutChatMessagesReadRequest request,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_apiBaseUrl/checkout/orders/$checkoutOrderId/messages/read'),
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
  }
}
