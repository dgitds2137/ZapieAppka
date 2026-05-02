import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../models/admin_dashboard.dart';
import '../models/auth_session.dart';

abstract class AdminDashboardRepository {
  Future<AdminDashboardData> fetchDashboard({
    required AuthSession authSession,
  });

  Future<AdminCatalogData> fetchCatalog({
    required AuthSession authSession,
  });

  Future<AdminDashboardOrder> updateOrderProcessingStatus({
    required AuthSession authSession,
    required int checkoutOrderId,
    required String processingStatus,
    String? verificationStage,
  });

  Future<AdminPrepTimeSetting> updatePrepTimeSetting({
    required AuthSession authSession,
    required String groupKey,
    required int minutes,
  });

  Future<AdminCatalogPosition> updatePositionActive({
    required AuthSession authSession,
    required int positionId,
    required bool isActive,
  });

  Future<AdminCatalogAddon> updateAddonActive({
    required AuthSession authSession,
    required int addonId,
    required bool isActive,
  });
}

class HttpAdminDashboardRepository implements AdminDashboardRepository {
  HttpAdminDashboardRepository({
    http.Client? client,
    String? apiBaseUrl,
  })  : _client = client ?? http.Client(),
        _apiBaseUrl = apiBaseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _apiBaseUrl;

  @override
  Future<AdminDashboardData> fetchDashboard({
    required AuthSession authSession,
  }) async {
    final response = await _client.get(
      Uri.parse('$_apiBaseUrl/admin/dashboard').replace(
        queryParameters: _identityQueryParameters(authSession),
      ),
      headers: const {
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Backend zwrocil ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Nieoczekiwany format odpowiedzi z /admin/dashboard.');
    }

    return AdminDashboardData.fromJson(decoded);
  }

  @override
  Future<AdminCatalogData> fetchCatalog({
    required AuthSession authSession,
  }) async {
    final response = await _client.get(
      Uri.parse('$_apiBaseUrl/admin/catalog').replace(
        queryParameters: _identityQueryParameters(authSession),
      ),
      headers: const {
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Backend zwrocil ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Nieoczekiwany format odpowiedzi z /admin/catalog.');
    }

    return AdminCatalogData.fromJson(decoded);
  }

  @override
  Future<AdminDashboardOrder> updateOrderProcessingStatus({
    required AuthSession authSession,
    required int checkoutOrderId,
    required String processingStatus,
    String? verificationStage,
  }) async {
    final response = await _client
        .patch(
          Uri.parse(
            '$_apiBaseUrl/admin/orders/$checkoutOrderId/processing-status',
          ),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'processing_status': processingStatus,
            if (verificationStage != null &&
                verificationStage.trim().isNotEmpty)
              'verification_stage': verificationStage,
            'session_token': authSession.sessionToken,
            'user_email': authSession.email,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Backend zwrocil ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception(
        'Nieoczekiwany format odpowiedzi z /admin/orders/{id}/processing-status.',
      );
    }

    return AdminDashboardOrder.fromJson(decoded);
  }

  @override
  Future<AdminPrepTimeSetting> updatePrepTimeSetting({
    required AuthSession authSession,
    required String groupKey,
    required int minutes,
  }) async {
    final response = await _client
        .patch(
          Uri.parse(
            '$_apiBaseUrl/admin/prep-time-settings/$groupKey',
          ),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'minutes': minutes,
            'session_token': authSession.sessionToken,
            'user_email': authSession.email,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Backend zwrocil ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception(
        'Nieoczekiwany format odpowiedzi z /admin/prep-time-settings/{group_key}.',
      );
    }

    return AdminPrepTimeSetting.fromJson(decoded);
  }

  @override
  Future<AdminCatalogPosition> updatePositionActive({
    required AuthSession authSession,
    required int positionId,
    required bool isActive,
  }) async {
    final response = await _client
        .patch(
          Uri.parse('$_apiBaseUrl/admin/catalog/positions/$positionId'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'is_active': isActive,
            'session_token': authSession.sessionToken,
            'user_email': authSession.email,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Backend zwrocil ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception(
        'Nieoczekiwany format odpowiedzi z /admin/catalog/positions/{id}.',
      );
    }

    return AdminCatalogPosition.fromJson(decoded);
  }

  @override
  Future<AdminCatalogAddon> updateAddonActive({
    required AuthSession authSession,
    required int addonId,
    required bool isActive,
  }) async {
    final response = await _client
        .patch(
          Uri.parse('$_apiBaseUrl/admin/catalog/addons/$addonId'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'is_active': isActive,
            'session_token': authSession.sessionToken,
            'user_email': authSession.email,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Backend zwrocil ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception(
        'Nieoczekiwany format odpowiedzi z /admin/catalog/addons/{id}.',
      );
    }

    return AdminCatalogAddon.fromJson(decoded);
  }

  Map<String, String> _identityQueryParameters(AuthSession authSession) {
    final params = <String, String>{};
    final sessionToken = authSession.sessionToken?.trim();
    final email = authSession.email?.trim();

    if (sessionToken != null && sessionToken.isNotEmpty) {
      params['session_token'] = sessionToken;
    }
    if (email != null && email.isNotEmpty) {
      params['email'] = email;
    }
    return params;
  }
}
