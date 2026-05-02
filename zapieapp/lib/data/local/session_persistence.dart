import 'dart:convert';

import '../models/auth_session.dart';
import '../models/checkout_verification.dart';
import 'storage_backend.dart';

class SessionPersistence {
  static const _authSessionKey = 'auth_session';
  static const _activeCheckoutKey = 'active_checkout';

  static Future<void> saveAuthSession(AuthSession session) async {
    await writeStorageValue(_authSessionKey, jsonEncode(session.toRouteArgs()));
  }

  static AuthSession? loadAuthSessionSync() {
    final raw = readStorageValueSync(_authSessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return AuthSession.fromRouteArgs(decoded);
    }
    if (decoded is Map) {
      return AuthSession.fromRouteArgs(Map<String, dynamic>.from(decoded));
    }
    return null;
  }

  static Future<AuthSession?> loadAuthSession() async {
    return loadAuthSessionSync();
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
    return loadActiveCheckoutSync();
  }

  static Future<void> clearAll() async {
    await removeStorageValue(_authSessionKey);
    await removeStorageValue(_activeCheckoutKey);
  }
}
