class CheckoutVerificationAddress {
  const CheckoutVerificationAddress({
    required this.title,
    required this.subtitle,
    required this.etaLabel,
  });

  final String title;
  final String subtitle;
  final String etaLabel;

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'eta_label': etaLabel,
      };

  factory CheckoutVerificationAddress.fromJson(Map<String, dynamic> json) {
    return CheckoutVerificationAddress(
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      etaLabel: json['eta_label']?.toString() ?? '',
    );
  }
}

class CheckoutVerificationItem {
  const CheckoutVerificationItem({
    required this.cartEntryId,
    required this.name,
    this.positionId,
    this.description,
    this.photoUrl,
    this.calories,
    this.price,
  });

  final int cartEntryId;
  final int? positionId;
  final String name;
  final String? description;
  final String? photoUrl;
  final int? calories;
  final double? price;

  Map<String, dynamic> toJson() => {
        'cart_entry_id': cartEntryId,
        'position_id': positionId,
        'name': name,
        'description': description,
        'photo_url': photoUrl,
        'calories': calories,
        'price': price,
      };

  factory CheckoutVerificationItem.fromJson(Map<String, dynamic> json) {
    return CheckoutVerificationItem(
      cartEntryId: _asInt(json['cart_entry_id']) ?? 0,
      positionId: _asInt(json['position_id']),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      photoUrl: json['photo_url']?.toString(),
      calories: _asInt(json['calories']),
      price: _asDouble(json['price']),
    );
  }
}

class CheckoutVerificationRequest {
  const CheckoutVerificationRequest({
    required this.createdAt,
    required this.currency,
    this.subtotalAmount,
    required this.totalAmount,
    this.redeemedPoints = 0,
    this.redeemedAmount = 0,
    required this.etaMinutes,
    required this.paymentMethod,
    required this.fulfillmentMethod,
    required this.fulfillmentOptionIndex,
    required this.addressOptionIndex,
    required this.address,
    required this.items,
    this.sessionToken,
    this.userEmail,
    this.notes,
  });

  final DateTime createdAt;
  final String currency;
  final double? subtotalAmount;
  final double totalAmount;
  final int redeemedPoints;
  final double redeemedAmount;
  final int etaMinutes;
  final String paymentMethod;
  final String fulfillmentMethod;
  final int fulfillmentOptionIndex;
  final int addressOptionIndex;
  final CheckoutVerificationAddress address;
  final List<CheckoutVerificationItem> items;
  final String? sessionToken;
  final String? userEmail;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'created_at': createdAt.toUtc().toIso8601String(),
        'currency': currency,
        'subtotal_amount': subtotalAmount,
        'total_amount': totalAmount,
        'redeemed_points': redeemedPoints,
        'redeemed_amount': redeemedAmount,
        'eta_minutes': etaMinutes,
        'payment_method': paymentMethod,
        'fulfillment_method': fulfillmentMethod,
        'fulfillment_option_index': fulfillmentOptionIndex,
        'address_option_index': addressOptionIndex,
        'address': address.toJson(),
        'items': items.map((item) => item.toJson()).toList(growable: false),
        'session_token': sessionToken,
        'user_email': userEmail,
        'notes': notes,
      };

  factory CheckoutVerificationRequest.fromJson(Map<String, dynamic> json) {
    final addressJson = json['address'];
    final itemsJson = json['items'];

    return CheckoutVerificationRequest(
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      currency: json['currency']?.toString() ?? 'PLN',
      subtotalAmount: _asDouble(json['subtotal_amount']),
      totalAmount: _asDouble(json['total_amount']) ?? 0,
      redeemedPoints: _asInt(json['redeemed_points']) ?? 0,
      redeemedAmount: _asDouble(json['redeemed_amount']) ?? 0,
      etaMinutes: _asInt(json['eta_minutes']) ?? 0,
      paymentMethod: json['payment_method']?.toString() ?? '',
      fulfillmentMethod: json['fulfillment_method']?.toString() ?? '',
      fulfillmentOptionIndex: _asInt(json['fulfillment_option_index']) ?? 0,
      addressOptionIndex: _asInt(json['address_option_index']) ?? 0,
      address: addressJson is Map<String, dynamic>
          ? CheckoutVerificationAddress.fromJson(addressJson)
          : CheckoutVerificationAddress(title: '', subtitle: '', etaLabel: ''),
      items: itemsJson is List
          ? itemsJson
              .whereType<Map>()
              .map((item) => CheckoutVerificationItem.fromJson(
                  Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const [],
      sessionToken: json['session_token']?.toString(),
      userEmail: json['user_email']?.toString(),
      notes: json['notes']?.toString(),
    );
  }
}

class CheckoutVerificationResponse {
  const CheckoutVerificationResponse({
    required this.verificationId,
    required this.savedOrderId,
    required this.status,
    this.processingStatus = 'unassigned',
    required this.paymentMethod,
    required this.verificationStage,
    required this.message,
    required this.createdAt,
    this.activeUntil,
    this.remainingEtaMinutes,
    this.requiresReceiptConfirmation = false,
    this.receiptConfirmationRequestedAt,
    this.supportAlertSentAt,
    this.deliveryExtensionCount = 0,
    this.awardedPoints = 0,
    this.userPointsBalance = 0,
    this.scheduledPickupAt,
    required this.receivedOrder,
  });

  final String verificationId;
  final int savedOrderId;
  final String status;
  final String processingStatus;
  final String paymentMethod;
  final String verificationStage;
  final String message;
  final DateTime createdAt;
  final DateTime? activeUntil;
  final int? remainingEtaMinutes;
  final bool requiresReceiptConfirmation;
  final DateTime? receiptConfirmationRequestedAt;
  final DateTime? supportAlertSentAt;
  final int deliveryExtensionCount;
  final int awardedPoints;
  final int userPointsBalance;
  final DateTime? scheduledPickupAt;
  final CheckoutVerificationRequest receivedOrder;

  Map<String, dynamic> toJson() => {
        'verification_id': verificationId,
        'saved_order_id': savedOrderId,
        'status': status,
        'processing_status': processingStatus,
        'payment_method': paymentMethod,
        'verification_stage': verificationStage,
        'message': message,
        'created_at': createdAt.toUtc().toIso8601String(),
        'active_until': activeUntil?.toUtc().toIso8601String(),
        'remaining_eta_minutes': remainingEtaMinutes,
        'requires_receipt_confirmation': requiresReceiptConfirmation,
        'receipt_confirmation_requested_at':
            receiptConfirmationRequestedAt?.toUtc().toIso8601String(),
        'support_alert_sent_at': supportAlertSentAt?.toUtc().toIso8601String(),
        'delivery_extension_count': deliveryExtensionCount,
        'awarded_points': awardedPoints,
        'user_points_balance': userPointsBalance,
        'scheduled_pickup_at': scheduledPickupAt?.toUtc().toIso8601String(),
        'received_order': receivedOrder.toJson(),
      };

  factory CheckoutVerificationResponse.fromJson(Map<String, dynamic> json) {
    final receivedOrderJson = json['received_order'];

    return CheckoutVerificationResponse(
      verificationId: json['verification_id']?.toString() ?? '',
      savedOrderId: _asInt(json['saved_order_id']) ?? 0,
      status: json['status']?.toString() ?? '',
      processingStatus: json['processing_status']?.toString() ?? 'unassigned',
      paymentMethod: json['payment_method']?.toString() ?? '',
      verificationStage: json['verification_stage']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      activeUntil: DateTime.tryParse(json['active_until']?.toString() ?? ''),
      remainingEtaMinutes: _asInt(json['remaining_eta_minutes']),
      requiresReceiptConfirmation:
          json['requires_receipt_confirmation'] == true,
      receiptConfirmationRequestedAt: DateTime.tryParse(
        json['receipt_confirmation_requested_at']?.toString() ?? '',
      ),
      supportAlertSentAt: DateTime.tryParse(
        json['support_alert_sent_at']?.toString() ?? '',
      ),
      deliveryExtensionCount: _asInt(json['delivery_extension_count']) ?? 0,
      awardedPoints: _asInt(json['awarded_points']) ?? 0,
      userPointsBalance: _asInt(json['user_points_balance']) ?? 0,
      scheduledPickupAt:
          DateTime.tryParse(json['scheduled_pickup_at']?.toString() ?? ''),
      receivedOrder: receivedOrderJson is Map<String, dynamic>
          ? CheckoutVerificationRequest.fromJson(receivedOrderJson)
          : CheckoutVerificationRequest(
              createdAt: DateTime.now().toUtc(),
              currency: 'PLN',
              subtotalAmount: 0,
              totalAmount: 0,
              redeemedPoints: 0,
              redeemedAmount: 0,
              etaMinutes: 0,
              paymentMethod: '',
              fulfillmentMethod: '',
              fulfillmentOptionIndex: 0,
              addressOptionIndex: 0,
              address: const CheckoutVerificationAddress(
                  title: '', subtitle: '', etaLabel: ''),
              items: const [],
              sessionToken: null,
              userEmail: null,
            ),
    );
  }
}

class CheckoutHistoryPage {
  const CheckoutHistoryPage({
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.hasMore,
    required this.orders,
  });

  final int page;
  final int pageSize;
  final int totalCount;
  final bool hasMore;
  final List<CheckoutVerificationResponse> orders;

  factory CheckoutHistoryPage.fromJson(Map<String, dynamic> json) {
    final ordersJson = json['orders'];
    return CheckoutHistoryPage(
      page: _asInt(json['page']) ?? 1,
      pageSize: _asInt(json['page_size']) ?? 10,
      totalCount: _asInt(json['total_count']) ?? 0,
      hasMore: json['has_more'] == true,
      orders: ordersJson is List
          ? ordersJson
              .whereType<Map>()
              .map(
                (item) => CheckoutVerificationResponse.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
          : const [],
    );
  }
}

class CheckoutReceiptConfirmationRequest {
  const CheckoutReceiptConfirmationRequest({
    required this.received,
    this.sessionToken,
    this.userEmail,
  });

  final bool received;
  final String? sessionToken;
  final String? userEmail;

  Map<String, dynamic> toJson() => {
        'received': received,
        'session_token': sessionToken,
        'user_email': userEmail,
      };
}

class CheckoutChatMessage {
  const CheckoutChatMessage({
    required this.checkoutOrderMessageId,
    required this.checkoutOrderId,
    required this.senderRole,
    required this.authorLabel,
    required this.message,
    required this.createdAt,
    this.staffReadAt,
  });

  final int checkoutOrderMessageId;
  final int checkoutOrderId;
  final String senderRole;
  final String authorLabel;
  final String message;
  final DateTime createdAt;
  final DateTime? staffReadAt;

  factory CheckoutChatMessage.fromJson(Map<String, dynamic> json) {
    return CheckoutChatMessage(
      checkoutOrderMessageId: _asInt(json['checkout_order_message_id']) ?? 0,
      checkoutOrderId: _asInt(json['checkout_order_id']) ?? 0,
      senderRole: json['sender_role']?.toString() ?? '',
      authorLabel: json['author_label']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      staffReadAt:
          DateTime.tryParse(json['staff_read_at']?.toString() ?? ''),
    );
  }
}

class CheckoutChatMessageCreateRequest {
  const CheckoutChatMessageCreateRequest({
    required this.message,
    this.sessionToken,
    this.userEmail,
  });

  final String message;
  final String? sessionToken;
  final String? userEmail;

  Map<String, dynamic> toJson() => {
        'message': message,
        'session_token': sessionToken,
        'user_email': userEmail,
      };
}

class CheckoutChatMessagesReadRequest {
  const CheckoutChatMessagesReadRequest({
    this.sessionToken,
    this.userEmail,
  });

  final String? sessionToken;
  final String? userEmail;

  Map<String, dynamic> toJson() => {
        'session_token': sessionToken,
        'user_email': userEmail,
      };
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

double? _asDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.'));
  }
  return null;
}
