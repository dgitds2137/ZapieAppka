import 'package:flutter_test/flutter_test.dart';
import 'package:zapieapp_flutter_starter/data/models/admin_dashboard.dart';
import 'package:zapieapp_flutter_starter/data/models/checkout_verification.dart';

void main() {
  group('Frontend QA: TIME_ZAPIEKANKI Phase 2 model contracts', () {
    test('CheckoutVerificationResponse exposes effective ETA from kitchen data',
        () {
      final response = CheckoutVerificationResponse.fromJson({
        'verification_id': 'phase2-order-1',
        'saved_order_id': 900,
        'status': 'assigned',
        'processing_status': 'assigned',
        'payment_method': 'BLIK',
        'verification_stage': 'accepted',
        'message': 'ok',
        'created_at': '2026-06-14T10:00:00Z',
        'remaining_eta_minutes': 11,
        'kitchen_eta_minutes': 15,
        'kitchen_batch_index': 2,
        'kitchen_batch_count': 3,
        'kitchen_capacity': 6,
        'kitchen_current_oven_load': 4,
        'kitchen_queue_pieces_before_order': 6,
        'kitchen_slots_before_order': 1,
        'kitchen_slots_used_by_order': 2,
        'received_order': {
          'created_at': '2026-06-14T10:00:00Z',
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
      });

      expect(response.kitchenEtaMinutes, 15);
      expect(response.kitchenBatchIndex, 2);
      expect(response.kitchenBatchCount, 3);
      expect(response.kitchenCapacity, 6);
      expect(response.kitchenCurrentOvenLoad, 4);
      expect(response.kitchenQueuePiecesBeforeOrder, 6);
      expect(response.kitchenSlotsBeforeOrder, 1);
      expect(response.kitchenSlotsUsedByOrder, 2);
      expect(response.effectiveBaseEtaMinutes, 15);
      expect(response.effectiveRemainingEtaMinutes, 11);
      expect(response.hasKitchenDiagnostics, true);
    });

    test('CheckoutVerificationResponse falls back to received order ETA', () {
      final response = CheckoutVerificationResponse.fromJson({
        'verification_id': 'phase2-order-2',
        'saved_order_id': 901,
        'status': 'pending',
        'processing_status': 'unassigned',
        'payment_method': 'card',
        'verification_stage': 'accepted',
        'message': 'ok',
        'created_at': '2026-06-14T11:00:00Z',
        'remaining_eta_minutes': null,
        'kitchen_eta_minutes': null,
        'kitchen_slots_used_by_order': 0,
        'received_order': {
          'created_at': '2026-06-14T11:00:00Z',
          'currency': 'PLN',
          'subtotal_amount': 21.37,
          'total_amount': 21.37,
          'redeemed_points': 0,
          'redeemed_amount': 0,
          'eta_minutes': 10,
          'payment_method': 'card',
          'fulfillment_method': 'odbior',
          'fulfillment_option_index': 0,
          'address_option_index': 0,
          'address': {
            'title': 'Sklotowa 6/9',
            'subtitle': 'Punkt odbioru',
            'eta_label': 'ok. 10 min',
          },
          'items': [
            {
              'cart_entry_id': 3,
              'position_id': 501,
              'name': 'Frytki',
              'price': 21.37,
            },
          ],
        },
      });

      expect(response.effectiveBaseEtaMinutes, 10);
      expect(response.effectiveRemainingEtaMinutes, 10);
      expect(response.hasKitchenDiagnostics, false);
    });

    test('AdminDashboardOrder maps kitchen diagnostics for operator view', () {
      final order = AdminDashboardOrder.fromJson({
        'checkout_order_id': 700,
        'verification_id': 'phase2-admin-1',
        'processing_status': 'assigned',
        'lifecycle_status': 'active',
        'verification_stage': 'accepted',
        'created_at': '2026-06-14T12:00:00Z',
        'remaining_eta_minutes': 15,
        'payment_method': 'BLIK',
        'fulfillment_method': 'odbior',
        'total_amount': 120.0,
        'item_count': 3,
        'item_names': ['Pieczarka 50cm', 'Szynka 50cm', 'Salame 50cm'],
        'items': [
          {'name': 'Pieczarka 50cm', 'quantity': 1, 'price': 40.0},
          {'name': 'Szynka 50cm', 'quantity': 1, 'price': 40.0},
          {'name': 'Salame 50cm', 'quantity': 1, 'price': 40.0},
        ],
        'address_title': 'Sklotowa 6/9',
        'address_subtitle': 'Punkt odbioru',
        'supports_progress_updates': true,
        'oven_kind': 'zapiekanki',
        'can_mark_in_oven': false,
        'oven_slot_count': 3,
        'oven_load': 6,
        'oven_capacity': 6,
        'kitchen_eta_minutes': 15,
        'kitchen_batch_index': 2,
        'kitchen_batch_count': 2,
        'kitchen_capacity': 6,
        'kitchen_current_oven_load': 6,
        'kitchen_queue_pieces_before_order': 4,
        'kitchen_slots_before_order': 1,
        'kitchen_slots_used_by_order': 3,
        'unread_customer_message_count': 2,
        'assigned_to_me': true,
        'assigned_operator_email': 'employee@zapieapp.pl',
      });

      expect(order.ovenKind, 'zapiekanki');
      expect(order.canMarkInOven, false);
      expect(order.kitchenEtaMinutes, 15);
      expect(order.kitchenBatchIndex, 2);
      expect(order.kitchenBatchCount, 2);
      expect(order.kitchenCapacity, 6);
      expect(order.kitchenCurrentOvenLoad, 6);
      expect(order.kitchenQueuePiecesBeforeOrder, 4);
      expect(order.kitchenSlotsBeforeOrder, 1);
      expect(order.kitchenSlotsUsedByOrder, 3);
      expect(order.unreadCustomerMessageCount, 2);
      expect(order.assignedToMe, true);
      expect(order.assignedOperatorEmail, 'employee@zapieapp.pl');
    });
  });
}
