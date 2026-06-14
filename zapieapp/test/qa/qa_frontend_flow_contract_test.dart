import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zapieapp_flutter_starter/data/models/auth_session.dart';
import 'package:zapieapp_flutter_starter/data/models/checkout_verification.dart';
import 'package:zapieapp_flutter_starter/data/repositories/admin_dashboard_repository.dart';
import 'package:zapieapp_flutter_starter/data/repositories/checkout_repository.dart';
import 'package:zapieapp_flutter_starter/data/repositories/social_auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Frontend QA: checkout/admin flow contracts', () {
    const apiBaseUrl = 'https://zapieapp-api.qa.local';
    const orderId = 512;

    test(
        'order lifecycle: customer -> employee -> driver -> customer via repositories',
        () async {
      final calls = <String>[];
      var currentProcessing = 'unassigned';

      final mockClient = MockClient((http.Request request) async {
        calls.add('${request.method} ${request.url.path}');

        if (request.method == 'POST' &&
            request.url.path == '/checkout/verification') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['session_token'], 'session-customer');
          expect(payload['user_email'], 'customer@zapieapp.pl');
          expect(payload['fulfillment_method'], 'dostawa');

          return _jsonResponse(
            jsonEncode(
              _mockCheckoutVerificationPayload(verificationId: 'ord-qa-1'),
            ),
          );
        }

        if (request.method == 'PATCH' &&
            request.url.path == '/admin/orders/$orderId/processing-status') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['session_token'],
              anyOf('session-employee', 'session-driver'));
          expect(payload['user_email'],
              anyOf('employee@zapieapp.pl', 'driver@zapieapp.pl'));

          final nextStatus = payload['processing_status']?.toString() ?? '';
          final nextStage = payload['verification_stage']?.toString();
          currentProcessing =
              nextStatus.isEmpty ? currentProcessing : nextStatus;

          if (nextStage == 'in_oven') {
            return _jsonResponse(
              jsonEncode(
                _mockAdminOrderPayload(
                  status: currentProcessing,
                  verificationStage: 'in_oven',
                ),
              ),
            );
          }

          if (nextStage == 'ready_for_delivery') {
            return _jsonResponse(
              jsonEncode(
                _mockAdminOrderPayload(
                  status: currentProcessing,
                  verificationStage: 'ready_for_delivery',
                ),
              ),
            );
          }

          if (nextStage == 'on_the_way') {
            return _jsonResponse(
              jsonEncode(
                _mockAdminOrderPayload(
                  status: 'assigned',
                  verificationStage: 'on_the_way',
                ),
              ),
            );
          }

          if (nextStatus == 'completed') {
            return _jsonResponse(
              jsonEncode(
                _mockAdminOrderPayload(
                  status: 'completed',
                  verificationStage: 'completed',
                ),
              ),
            );
          }

          return _jsonResponse(
            jsonEncode(_mockAdminOrderPayload(status: currentProcessing)),
          );
        }

        if (request.method == 'POST' &&
            request.url.path == '/checkout/confirm-receipt') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['session_token'], 'session-customer');
          expect(payload['user_email'], 'customer@zapieapp.pl');
          expect(payload['received'], true);

          return _jsonResponse(
            jsonEncode(
              _mockCheckoutVerificationPayload(
                verificationId: 'ord-qa-1',
                status: 'completed',
                processingStatus: 'completed',
              ),
            ),
          );
        }

        return _jsonResponse('{"detail":"unexpected endpoint"}',
            statusCode: 404);
      });

      final checkoutRepo = HttpCheckoutRepository(
        client: mockClient,
        apiBaseUrl: apiBaseUrl,
      );
      final adminRepo = HttpAdminDashboardRepository(
        client: mockClient,
        apiBaseUrl: apiBaseUrl,
      );

      final employeeSession = AuthSession(
        email: 'employee@zapieapp.pl',
        sessionToken: 'session-employee',
        role: 'employee',
      );
      final driverSession = AuthSession(
        email: 'driver@zapieapp.pl',
        sessionToken: 'session-driver',
        role: 'driver',
      );

      final createReq = CheckoutVerificationRequest(
        createdAt: DateTime.parse('2026-06-07T10:00:00Z'),
        currency: 'PLN',
        subtotalAmount: 120,
        totalAmount: 120,
        redeemedPoints: 0,
        redeemedAmount: 0,
        etaMinutes: 20,
        paymentMethod: 'BLIK',
        fulfillmentMethod: 'dostawa',
        fulfillmentOptionIndex: 0,
        addressOptionIndex: 0,
        address: const CheckoutVerificationAddress(
          title: 'Przykladowa',
          subtitle: 'ul. Testowa 1, Warszawa',
          etaLabel: '~20 min',
        ),
        items: const [
          CheckoutVerificationItem(
            cartEntryId: 1,
            positionId: 10,
            name: 'Test zapiekanka',
            price: 120,
          ),
        ],
        sessionToken: 'session-customer',
        userEmail: 'customer@zapieapp.pl',
        notes: 'qa flow',
      );

      final submitted =
          await checkoutRepo.submitCheckoutVerification(createReq);
      expect(submitted.verificationId, 'ord-qa-1');
      expect(submitted.processingStatus, 'unassigned');
      expect(submitted.receivedOrder.paymentMethod, 'BLIK');
      expect(checkoutRepo.cachedActiveCheckout?.verificationId, 'ord-qa-1');

      final assigned = await adminRepo.updateOrderProcessingStatus(
        authSession: employeeSession,
        checkoutOrderId: orderId,
        processingStatus: 'assigned',
      );
      expect(assigned.processingStatus, 'assigned');

      final inOven = await adminRepo.updateOrderProcessingStatus(
        authSession: employeeSession,
        checkoutOrderId: orderId,
        processingStatus: 'assigned',
        verificationStage: 'in_oven',
      );
      expect(inOven.verificationStage, 'in_oven');

      final readyForDelivery = await adminRepo.updateOrderProcessingStatus(
        authSession: employeeSession,
        checkoutOrderId: orderId,
        processingStatus: 'assigned',
        verificationStage: 'ready_for_delivery',
      );
      expect(readyForDelivery.verificationStage, 'ready_for_delivery');

      final onTheWay = await adminRepo.updateOrderProcessingStatus(
        authSession: driverSession,
        checkoutOrderId: orderId,
        processingStatus: 'assigned',
        verificationStage: 'on_the_way',
      );
      expect(onTheWay.verificationStage, 'on_the_way');

      final completed = await adminRepo.updateOrderProcessingStatus(
        authSession: driverSession,
        checkoutOrderId: orderId,
        processingStatus: 'completed',
      );
      expect(completed.processingStatus, 'completed');

      final receipt = await checkoutRepo.confirmReceipt(
        CheckoutReceiptConfirmationRequest(
          received: true,
          sessionToken: 'session-customer',
          userEmail: 'customer@zapieapp.pl',
        ),
      );
      expect(receipt.status, 'completed');
      expect(checkoutRepo.cachedActiveCheckout, isNull);

      expect(calls, contains('POST /checkout/verification'));
      expect(
        calls.where(
            (call) => call == 'PATCH /admin/orders/$orderId/processing-status'),
        hasLength(5),
      );
      expect(calls, contains('POST /checkout/confirm-receipt'));
    });

    test('checkout eta preview endpoint returns backend kitchen diagnostics',
        () async {
      final mockClient = MockClient((http.Request request) async {
        if (request.method == 'POST' &&
            request.url.path == '/checkout/eta-preview') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['session_token'], 'session-customer');
          expect(payload['user_email'], 'customer@zapieapp.pl');
          expect(payload['payment_method'], 'preview');
          expect(payload['fulfillment_method'], 'odbior');
          expect(payload['fulfillment_option_index'], 1);
          expect(payload['address_option_index'], 0);
          expect(payload['eta_minutes'], 15);
          expect(payload['items'], hasLength(2));

          return _jsonResponse(
            jsonEncode({
              'eta_minutes': 15,
              'available_from': '2026-06-14T12:15:00Z',
              'scheduled_pickup_at': '2026-06-14T12:15:00Z',
              'kitchen_eta_minutes': 15,
              'kitchen_batch_index': 2,
              'kitchen_batch_count': 3,
              'kitchen_capacity': 6,
              'kitchen_current_oven_load': 4,
              'kitchen_queue_pieces_before_order': 6,
              'kitchen_slots_before_order': 1,
              'kitchen_slots_used_by_order': 2,
            }),
          );
        }

        return _jsonResponse('{"detail":"unexpected endpoint"}',
            statusCode: 404);
      });

      final checkoutRepo = HttpCheckoutRepository(
        client: mockClient,
        apiBaseUrl: apiBaseUrl,
      );

      final preview = await checkoutRepo.previewCheckoutEta(
        CheckoutVerificationRequest(
          createdAt: DateTime.parse('2026-06-14T12:00:00Z'),
          currency: 'PLN',
          subtotalAmount: 80,
          totalAmount: 80,
          redeemedPoints: 0,
          redeemedAmount: 0,
          etaMinutes: 15,
          paymentMethod: 'preview',
          fulfillmentMethod: 'odbior',
          fulfillmentOptionIndex: 1,
          addressOptionIndex: 0,
          address: const CheckoutVerificationAddress(
            title: 'Sklotowa 6/9',
            subtitle: 'Punkt odbioru',
            etaLabel: 'ok. 15 min',
          ),
          items: const [
            CheckoutVerificationItem(
              cartEntryId: 11,
              positionId: 201,
              name: 'Pieczarka 50cm',
              price: 40,
            ),
            CheckoutVerificationItem(
              cartEntryId: 12,
              positionId: 201,
              name: 'Pieczarka 50cm',
              price: 40,
            ),
          ],
          sessionToken: 'session-customer',
          userEmail: 'customer@zapieapp.pl',
          notes: 'preview qa',
        ),
      );

      expect(preview.etaMinutes, 15);
      expect(
        preview.availableFrom,
        DateTime.parse('2026-06-14T12:15:00Z'),
      );
      expect(
        preview.scheduledPickupAt,
        DateTime.parse('2026-06-14T12:15:00Z'),
      );
      expect(preview.kitchenEtaMinutes, 15);
      expect(preview.kitchenBatchIndex, 2);
      expect(preview.kitchenBatchCount, 3);
      expect(preview.kitchenCapacity, 6);
      expect(preview.kitchenCurrentOvenLoad, 4);
      expect(preview.kitchenQueuePiecesBeforeOrder, 6);
      expect(preview.kitchenSlotsBeforeOrder, 1);
      expect(preview.kitchenSlotsUsedByOrder, 2);
      expect(checkoutRepo.cachedActiveCheckout, isNull);
    });

    test('active checkout endpoint maps kitchen diagnostics and caches response',
        () async {
      final mockClient = MockClient((http.Request request) async {
        if (request.method == 'GET' && request.url.path == '/checkout/active') {
          expect(request.url.queryParameters['session_token'], 'session-customer');
          expect(request.url.queryParameters['email'], 'customer@zapieapp.pl');

          return _jsonResponse(
            jsonEncode({
              'verification_id': 'ord-phase2-active',
              'saved_order_id': 913,
              'status': 'active',
              'processing_status': 'assigned',
              'payment_method': 'BLIK',
              'verification_stage': 'accepted',
              'message': 'ok',
              'created_at': '2026-06-14T12:00:00Z',
              'remaining_eta_minutes': 11,
              'kitchen_eta_minutes': 15,
              'kitchen_batch_index': 2,
              'kitchen_batch_count': 2,
              'kitchen_capacity': 6,
              'kitchen_current_oven_load': 4,
              'kitchen_queue_pieces_before_order': 6,
              'kitchen_slots_before_order': 1,
              'kitchen_slots_used_by_order': 2,
              'received_order': {
                'created_at': '2026-06-14T12:00:00Z',
                'currency': 'PLN',
                'subtotal_amount': 80,
                'total_amount': 80,
                'redeemed_points': 0,
                'redeemed_amount': 0,
                'eta_minutes': 10,
                'payment_method': 'BLIK',
                'fulfillment_method': 'odbior',
                'fulfillment_option_index': 0,
                'address_option_index': 0,
                'address': {
                  'title': 'Sklotowa 6/9',
                  'subtitle': 'Punkt odbioru',
                  'eta_label': 'ok. 15 min',
                },
                'items': [
                  {
                    'cart_entry_id': 1,
                    'position_id': 101,
                    'name': 'Pieczarka 50cm',
                    'price': 40,
                  },
                  {
                    'cart_entry_id': 2,
                    'position_id': 101,
                    'name': 'Pieczarka 50cm',
                    'price': 40,
                  },
                ],
              },
            }),
          );
        }

        return _jsonResponse('{"detail":"unexpected endpoint"}',
            statusCode: 404);
      });

      final checkoutRepo = HttpCheckoutRepository(
        client: mockClient,
        apiBaseUrl: apiBaseUrl,
      );

      final active = await checkoutRepo.fetchActiveCheckout(
        sessionToken: 'session-customer',
        email: 'customer@zapieapp.pl',
      );

      expect(active, isNotNull);
      expect(active!.effectiveBaseEtaMinutes, 15);
      expect(active.effectiveRemainingEtaMinutes, 11);
      expect(active.kitchenBatchIndex, 2);
      expect(active.kitchenBatchCount, 2);
      expect(active.kitchenSlotsUsedByOrder, 2);
      expect(active.hasKitchenDiagnostics, true);
      expect(checkoutRepo.cachedActiveCheckout?.verificationId, 'ord-phase2-active');
    });
  });

  group('Frontend QA: admin catalog and auth session', () {
    test('google auth start endpoint returns external authorization URL', () async {
      final mockClient = MockClient((http.Request request) async {
        if (request.method == 'GET' && request.url.path == '/google-auth/start') {
          expect(request.url.queryParameters['email'], 'user@zapieapp.pl');
          expect(
            request.url.queryParameters['redirect_uri'],
            'zapieapp://auth/callback',
          );

          return _jsonResponse(
            jsonEncode({
              'provider': 'google',
              'authorization_url':
                  'https://accounts.google.com/o/oauth2/v2/auth?client_id=test',
              'redirect_uri': 'zapieapp://auth/callback',
              'state': 'signed-state',
            }),
          );
        }

        return _jsonResponse('not implemented', statusCode: 500);
      });

      final repo = HttpSocialAuthRepository(
        client: mockClient,
        apiBaseUrl: 'https://zapieapp-api.qa.local',
      );

      final result = await repo.startGoogleAuth(
        email: 'user@zapieapp.pl',
        redirectUri: 'zapieapp://auth/callback',
      );

      expect(result.provider, 'google');
      expect(
        result.authorizationUrl,
        'https://accounts.google.com/o/oauth2/v2/auth?client_id=test',
      );
      expect(result.redirectUri, 'zapieapp://auth/callback');
      expect(result.state, 'signed-state');
    });

    test('google auth start endpoint works without e-mail hint', () async {
      final mockClient = MockClient((http.Request request) async {
        if (request.method == 'GET' && request.url.path == '/google-auth/start') {
          expect(request.url.queryParameters.containsKey('email'), false);
          expect(
            request.url.queryParameters['redirect_uri'],
            'zapieapp://auth/callback',
          );

          return _jsonResponse(
            jsonEncode({
              'provider': 'google',
              'authorization_url':
                  'https://accounts.google.com/o/oauth2/v2/auth?client_id=test',
              'redirect_uri': 'zapieapp://auth/callback',
              'state': 'signed-state-no-email',
            }),
          );
        }

        return _jsonResponse('not implemented', statusCode: 500);
      });

      final repo = HttpSocialAuthRepository(
        client: mockClient,
        apiBaseUrl: 'https://zapieapp-api.qa.local',
      );

      final result = await repo.startGoogleAuth(
        email: null,
        redirectUri: 'zapieapp://auth/callback',
      );

      expect(result.provider, 'google');
      expect(result.state, 'signed-state-no-email');
      expect(result.redirectUri, 'zapieapp://auth/callback');
    });

    test('apple auth start endpoint returns external authorization URL', () async {
      final mockClient = MockClient((http.Request request) async {
        if (request.method == 'GET' && request.url.path == '/apple-auth/start') {
          expect(request.url.queryParameters.containsKey('email'), false);
          expect(
            request.url.queryParameters['redirect_uri'],
            'zapieapp://auth/callback',
          );

          return _jsonResponse(
            jsonEncode({
              'provider': 'apple',
              'authorization_url':
                  'https://appleid.apple.com/auth/authorize?client_id=test',
              'redirect_uri': 'zapieapp://auth/callback',
              'state': 'apple-signed-state',
              'nonce': 'apple-nonce',
            }),
          );
        }

        return _jsonResponse('not implemented', statusCode: 500);
      });

      final repo = HttpSocialAuthRepository(
        client: mockClient,
        apiBaseUrl: 'https://zapieapp-api.qa.local',
      );

      final result = await repo.startAppleAuth(
        email: null,
        redirectUri: 'zapieapp://auth/callback',
      );

      expect(result.provider, 'apple');
      expect(
        result.authorizationUrl,
        'https://appleid.apple.com/auth/authorize?client_id=test',
      );
      expect(result.redirectUri, 'zapieapp://auth/callback');
      expect(result.state, 'apple-signed-state');
      expect(result.nonce, 'apple-nonce');
    });

    test('google mobile auth endpoint returns standard app session', () async {
      final mockClient = MockClient((http.Request request) async {
        if (request.method == 'POST' &&
            request.url.path == '/google-auth/mobile') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['id_token'], 'mobile-id-token');
          expect(payload['email'], 'daniel.gromak2137@gmail.com');

          return _jsonResponse(
            jsonEncode({
              'jwt': 'jwt-token',
              'session_token': 'session-token',
              'role': 'user',
              'user_id': 17,
              'email': 'daniel.gromak2137@gmail.com',
              'loyalty_points': 12,
            }),
          );
        }

        return _jsonResponse('not implemented', statusCode: 500);
      });

      final repo = HttpSocialAuthRepository(
        client: mockClient,
        apiBaseUrl: 'https://zapieapp-api.qa.local',
      );

      final result = await repo.completeGoogleMobileAuth(
        idToken: 'mobile-id-token',
        email: 'daniel.gromak2137@gmail.com',
      );

      expect(result.email, 'daniel.gromak2137@gmail.com');
      expect(result.sessionToken, 'session-token');
      expect(result.jwt, 'jwt-token');
      expect(result.role, 'user');
      expect(result.authProvider, 'google');
      expect(result.loyaltyPoints, 12);
    });

    test(
        'admin catalog endpoints accept price updates for positions and addons',
        () async {
      final mockClient = MockClient((http.Request request) async {
        if (request.method == 'PATCH' &&
            request.url.path == '/admin/catalog/positions/501') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['price'], 24.9);

          return _jsonResponse(
            jsonEncode(
              _mockCatalogPositionPayload(
                positionId: 501,
                price: 24.9,
              ),
            ),
          );
        }

        if (request.method == 'PATCH' &&
            request.url.path == '/admin/catalog/addons/601') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['price'], 5.5);

          return _jsonResponse(
            jsonEncode(
              _mockCatalogAddonPayload(
                addonId: 601,
                price: 5.5,
              ),
            ),
          );
        }

        return _jsonResponse('not implemented', statusCode: 500);
      });

      final repo = HttpAdminDashboardRepository(
        client: mockClient,
        apiBaseUrl: 'https://zapieapp-api.qa.local',
      );

      final session = AuthSession(
        email: 'admin@zapieapp.pl',
        sessionToken: 'admin-session',
        role: 'admin',
      );

      final position = await repo.updatePositionActive(
        authSession: session,
        positionId: 501,
        price: 24.9,
      );
      expect(position.positionId, 501);
      expect(position.price, 24.9);

      final addon = await repo.updateAddonActive(
        authSession: session,
        addonId: 601,
        price: 5.5,
      );
      expect(addon.addonId, 601);
      expect(addon.price, 5.5);
    });

    test('kitchen ETA override endpoint maps into catalog payload', () async {
      final mockClient = MockClient((http.Request request) async {
        if (request.method == 'PATCH' &&
            request.url.path == '/admin/catalog/kitchen-eta') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['minutes'], 30);

          return _jsonResponse(
            jsonEncode({
              'delivery_minimum_amount': 35.0,
              'delivery_radius_km': 10,
              'delivery_origin_address': 'test base',
              'kitchen_eta_override_minutes': 30,
              'opening_hours': {
                'open_time': '11:00',
                'close_time': '22:00',
                'formatted_range': '11:00-22:00',
                'is_open_now': true,
              },
              'positions': <Map<String, dynamic>>[],
              'addons': <Map<String, dynamic>>[],
            }),
          );
        }

        return _jsonResponse('not implemented', statusCode: 500);
      });

      final repo = HttpAdminDashboardRepository(
        client: mockClient,
        apiBaseUrl: 'https://zapieapp-api.qa.local',
      );

      final session = AuthSession(
        email: 'admin@zapieapp.pl',
        sessionToken: 'admin-session',
        role: 'admin',
      );
      final catalog = await repo.updateKitchenEtaOverride(
        authSession: session,
        minutes: 30,
      );

      expect(catalog.kitchenEtaOverrideMinutes, 30);
      expect(catalog.deliveryRadiusKm, 10);
      expect(catalog.deliveryOriginAddress, 'test base');
    });

    test('admin dashboard endpoint maps kitchen diagnostics for in-progress orders',
        () async {
      final mockClient = MockClient((http.Request request) async {
        if (request.method == 'GET' && request.url.path == '/admin/dashboard') {
          expect(request.url.queryParameters['session_token'], 'admin-session');
          expect(request.url.queryParameters['email'], 'admin@zapieapp.pl');

          return _jsonResponse(
            jsonEncode({
              'logged_in_employee_count': 1,
              'active_employees': [],
              'prep_time_settings': [],
              'opening_hours': {
                'open_time': '12:00',
                'close_time': '21:00',
                'formatted_range': '12:00-21:00',
                'is_open_now': true,
              },
              'oven_load': 6,
              'oven_capacity': 6,
              'udka_oven_load': 0,
              'udka_oven_capacity': 16,
              'udka_slot_label': '12:00, 15:00, 18:00',
              'pending_order_count': 0,
              'in_progress_order_count': 1,
              'new_users_this_month': 3,
              'completed_orders_today': 12,
              'order_history_count': 40,
              'turnover_last_days': [],
              'pending_orders': [],
              'in_progress_orders': [
                {
                  'checkout_order_id': 700,
                  'verification_id': 'phase2-admin-1',
                  'processing_status': 'assigned',
                  'lifecycle_status': 'active',
                  'verification_stage': 'accepted',
                  'created_at': '2026-06-14T12:00:00Z',
                  'payment_method': 'BLIK',
                  'fulfillment_method': 'odbior',
                  'total_amount': 120.0,
                  'item_count': 3,
                  'item_names': [
                    'Pieczarka 50cm',
                    'Szynka 50cm',
                    'Salame 50cm'
                  ],
                  'items': [
                    {'name': 'Pieczarka 50cm', 'quantity': 1, 'price': 40.0},
                    {'name': 'Szynka 50cm', 'quantity': 1, 'price': 40.0},
                    {'name': 'Salame 50cm', 'quantity': 1, 'price': 40.0}
                  ],
                  'address_title': 'Sklotowa 6/9',
                  'address_subtitle': 'Punkt odbioru',
                  'remaining_eta_minutes': 15,
                  'supports_progress_updates': true,
                  'oven_kind': 'zapiekanki',
                  'can_mark_in_oven': false,
                  'oven_slot_count': 3,
                  'oven_load': 6,
                  'oven_capacity': 6,
                  'kitchen_eta_minutes': 15,
                  'kitchen_batch_index': 2,
                  'kitchen_batch_count': 1,
                  'kitchen_capacity': 6,
                  'kitchen_current_oven_load': 6,
                  'kitchen_queue_pieces_before_order': 4,
                  'kitchen_slots_before_order': 1,
                  'kitchen_slots_used_by_order': 3,
                  'unread_customer_message_count': 2,
                  'assigned_to_me': true,
                  'assigned_operator_email': 'admin@zapieapp.pl',
                }
              ],
              'closed_orders': [],
              'closed_orders_has_more': false,
              'my_taken_orders': [],
            }),
          );
        }

        return _jsonResponse('not implemented', statusCode: 500);
      });

      final repo = HttpAdminDashboardRepository(
        client: mockClient,
        apiBaseUrl: 'https://zapieapp-api.qa.local',
      );

      final session = AuthSession(
        email: 'admin@zapieapp.pl',
        sessionToken: 'admin-session',
        role: 'admin',
      );

      final dashboard = await repo.fetchDashboard(authSession: session);
      expect(dashboard.ovenLoad, 6);
      expect(dashboard.ovenCapacity, 6);
      expect(dashboard.inProgressOrders, hasLength(1));

      final order = dashboard.inProgressOrders.single;
      expect(order.canMarkInOven, false);
      expect(order.kitchenEtaMinutes, 15);
      expect(order.kitchenBatchIndex, 2);
      expect(order.kitchenBatchCount, 1);
      expect(order.kitchenCurrentOvenLoad, 6);
      expect(order.kitchenQueuePiecesBeforeOrder, 4);
      expect(order.kitchenSlotsBeforeOrder, 1);
      expect(order.kitchenSlotsUsedByOrder, 3);
      expect(order.assignedToMe, true);
    });

    test('AuthSession role helpers are consistent', () {
      final admin = AuthSession(email: 'admin@zapieapp.pl', role: 'admin');
      final employee =
          AuthSession(email: 'employee@zapieapp.pl', role: 'employee');
      final driver = AuthSession(email: 'driver@zapieapp.pl', role: 'driver');
      final user = AuthSession(email: 'demo@zapieapp.pl', role: 'user');

      expect(admin.isAdmin, true);
      expect(admin.isStaff, true);
      expect(admin.isUser, false);

      expect(employee.isEmployee, true);
      expect(employee.isStaff, true);
      expect(employee.isDriver, false);

      expect(driver.isDriver, true);
      expect(driver.isStaff, true);

      expect(user.isUser, true);
      expect(user.isStaff, false);
      expect(user.hasIdentity, true);
    });
  });
}

Map<String, dynamic> _mockCheckoutVerificationPayload({
  required String verificationId,
  String status = 'unassigned',
  String processingStatus = 'unassigned',
}) {
  return {
    'verification_id': verificationId,
    'saved_order_id': 512,
    'status': status,
    'processing_status': processingStatus,
    'payment_method': 'BLIK',
    'verification_stage': 'accepted',
    'message': 'ok',
    'created_at': '2026-06-07T10:00:00Z',
    'requires_receipt_confirmation': false,
    'awarded_points': 0,
    'user_points_balance': 10,
    'remaining_eta_minutes': 20,
    'received_order': {
      'created_at': '2026-06-07T10:00:00Z',
      'currency': 'PLN',
      'subtotal_amount': 120,
      'total_amount': 120,
      'redeemed_points': 0,
      'redeemed_amount': 0,
      'eta_minutes': 20,
      'payment_method': 'BLIK',
      'fulfillment_method': 'dostawa',
      'fulfillment_option_index': 0,
      'address_option_index': 0,
      'address': {
        'title': 'Przykladowa',
        'subtitle': 'ul. Testowa 1',
        'eta_label': '~20 min',
      },
      'items': [
        {
          'cart_entry_id': 1,
          'position_id': 10,
          'name': 'Test zapiekanka',
          'price': 120,
        },
      ],
    },
  };
}

Map<String, dynamic> _mockAdminOrderPayload({
  String status = 'assigned',
  String verificationStage = 'accepted',
}) {
  return {
    'checkout_order_id': 512,
    'verification_id': 'ord-qa-1',
    'processing_status': status,
    'lifecycle_status': status == 'completed' ? 'closed' : 'active',
    'verification_stage': verificationStage,
    'created_at': '2026-06-07T10:00:00Z',
    'payment_method': 'BLIK',
    'fulfillment_method': 'dostawa',
    'total_amount': 120.0,
    'item_count': 1,
    'item_names': ['Test zapiekanka'],
    'items': [
      {
        'name': 'Test zapiekanka',
        'quantity': 1,
        'price': 120.0,
      },
    ],
    'address_title': 'Przykladowa',
    'address_subtitle': 'ul. Testowa 1',
    'remaining_eta_minutes': 20,
    'supports_progress_updates': true,
    'oven_kind': 'none',
    'can_mark_in_oven': true,
    'oven_slot_count': 0,
    'oven_load': 0,
    'oven_capacity': 6,
    'unread_customer_message_count': 0,
    'assigned_to_me': true,
    'assigned_operator_email': 'driver@zapieapp.pl',
  };
}

Map<String, dynamic> _mockCatalogPositionPayload({
  int positionId = 501,
  double price = 24.9,
}) {
  return {
    'position_id': positionId,
    'position_type': 'zapiekanka',
    'sort_order': 1,
    'name': 'Test pozycja',
    'description': 'pozycja testowa',
    'price': price,
    'is_active': true,
  };
}

Map<String, dynamic> _mockCatalogAddonPayload({
  int addonId = 601,
  double price = 5.5,
}) {
  return {
    'addon_id': addonId,
    'name': 'Test dodatek',
    'description': 'dodatek testowy',
    'price': price,
    'sort_order': 1,
    'is_active': true,
  };
}

http.Response _jsonResponse(String body, {int statusCode = 200}) {
  return http.Response.bytes(
    utf8.encode(body),
    statusCode,
    headers: {'Content-Type': 'application/json; charset=utf-8'},
  );
}
