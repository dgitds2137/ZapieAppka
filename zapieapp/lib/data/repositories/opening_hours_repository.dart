import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../models/opening_hours.dart';

class OpeningHoursRepository {
  OpeningHoursRepository({
    http.Client? client,
    String? apiBaseUrl,
  })  : _client = client ?? http.Client(),
        _apiBaseUrl = apiBaseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _apiBaseUrl;

  Future<OpeningHoursData> fetchOpeningHours() async {
    final response = await _client.get(
      Uri.parse('$_apiBaseUrl/opening-hours'),
      headers: const {
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Backend zwrocil ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Nieoczekiwany format odpowiedzi z /opening-hours.');
    }

    return OpeningHoursData.fromJson(decoded);
  }
}
