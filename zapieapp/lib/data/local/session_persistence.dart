import 'dart:convert';

import '../../core/config/app_config.dart';
import '../models/auth_session.dart';
import '../models/checkout_verification.dart';
import 'storage_backend.dart';

class SessionPersistence {
  static const _authSessionKey = 'auth_session';
  static const _activeCheckoutKey = 'active_checkout';
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await initializeStorageBackend();
    _initialized = true;
    _clearExpiredSessionSync();
  }

  static Future<void> saveAuthSession(
    AuthSession session, {
    Duration? lifetime,
  }) async {
    final now = DateTime.now().toUtc();
    final effectiveLifetime =
        lifetime ?? Duration(days: AppConfig.persistedLoginDays);
    await writeStorageValue(
      _authSessionKey,
      jsonEncode({
        'session': session.toRouteArgs(),
        'persisted_at': now.toIso8601String(),
        'expires_at': now.add(effectiveLifetime).toIso8601String(),
      }),
    );
  }

  static AuthSession? loadAuthSessionSync() {
    _clearExpiredSessionSync();
    final raw = readStorageValueSync(_authSessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      final sessionJson = decoded['session'];
      if (sessionJson is Map<String, dynamic>) {
        return AuthSession.fromRouteArgs(sessionJson);
      }
      if (sessionJson is Map) {
        return AuthSession.fromRouteArgs(Map<String, dynamic>.from(sessionJson));
      }
    }
    if (decoded is Map<String, dynamic>) {
      return AuthSession.fromRouteArgs(decoded);
    }
    if (decoded is Map) {
      return AuthSession.fromRouteArgs(Map<String, dynamic>.from(decoded));
    }
    return null;
  }

  static Future<AuthSession?> loadAuthSession() async {
    await initialize();
    return loadAuthSessionSync();
  }

  static bool hasValidAuthSessionSync() {
    return loadAuthSessionSync()?.hasIdentity == true;
  }

  static Future<void> clearAuthSession() async {
    await removeStorageValue(_authSessionKey);
  }

  static Future<void> saveActiveCheckout(
    CheckoutVerificationResponse? checkout,
  ) async {
    if (checkout == null) {
      await removeStorageValue(_activeCheckoutKey);
      return;
    }

    await writeStorageValue(_activeCheckoutKey, jsonEncode(checkout.toJson()));
  }

  static CheckoutVerificationResponse? loadActiveCheckoutSync() {
    final raw = readStorageValueSync(_activeCheckoutKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return CheckoutVerificationResponse.fromJson(decoded);
    }
    if (decoded is Map) {
      return CheckoutVerificationResponse.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    }
    return null;
  }

  static Future<CheckoutVerificationResponse?> loadActiveCheckout() async {
    await initialize();
    return loadActiveCheckoutSync();
  }

  static Future<void> clearAll() async {
    await removeStorageValue(_authSessionKey);
    await removeStorageValue(_activeCheckoutKey);
  }

  static void _clearExpiredSessionSync() {
    final raw = readStorageValueSync(_authSessionKey);
    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      final expiresAtRaw = decoded['expires_at']?.toString();
      if (expiresAtRaw == null || expiresAtRaw.isEmpty) {
        return;
      }
      final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
      if (expiresAt == null) {
        return;
      }
      if (expiresAt.isAfter(DateTime.now().toUtc())) {
        return;
      }
      removeStorageValueSync(_authSessionKey);
      removeStorageValueSync(_activeCheckoutKey);
    } catch (_) {
      // Ignore malformed cached data and let normal login flow recover it.
    }
  }
}
