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
    required this.totalAmount,
    required this.etaMinutes,
    required this.paymentMethod,
    required this.fulfillmentMethod,
    required this.fulfillmentOptionIndex,
    required this.addressOptionIndex,
    required this.address,
    required this.items,
    this.notes,
  });

  final DateTime createdAt;
  final String currency;
  final double totalAmount;
  final int etaMinutes;
  final String paymentMethod;
  final String fulfillmentMethod;
  final int fulfillmentOptionIndex;
  final int addressOptionIndex;
  final CheckoutVerificationAddress address;
  final List<CheckoutVerificationItem> items;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'created_at': createdAt.toUtc().toIso8601String(),
        'currency': currency,
        'total_amount': totalAmount,
        'eta_minutes': etaMinutes,
        'payment_method': paymentMethod,
        'fulfillment_method': fulfillmentMethod,
        'fulfillment_option_index': fulfillmentOptionIndex,
        'address_option_index': addressOptionIndex,
        'address': address.toJson(),
        'items': items.map((item) => item.toJson()).toList(growable: false),
        'notes': notes,
      };

  factory CheckoutVerificationRequest.fromJson(Map<String, dynamic> json) {
    final addressJson = json['address'];
    final itemsJson = json['items'];

    return CheckoutVerificationRequest(
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now().toUtc(),
      currency: json['currency']?.toString() ?? 'PLN',
      totalAmount: _asDouble(json['total_amount']) ?? 0,
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
              .map((item) => CheckoutVerificationItem.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const [],
      notes: json['notes']?.toString(),
    );
  }
}

class CheckoutVerificationResponse {
  const CheckoutVerificationResponse({
    required this.verificationId,
    required this.savedOrderId,
    required this.status,
    required this.paymentMethod,
    required this.verificationStage,
    required this.message,
    required this.createdAt,
    required this.receivedOrder,
  });

  final String verificationId;
  final int savedOrderId;
  final String status;
  final String paymentMethod;
  final String verificationStage;
  final String message;
  final DateTime createdAt;
  final CheckoutVerificationRequest receivedOrder;

  Map<String, dynamic> toJson() => {
        'verification_id': verificationId,
        'saved_order_id': savedOrderId,
        'status': status,
        'payment_method': paymentMethod,
        'verification_stage': verificationStage,
        'message': message,
        'created_at': createdAt.toUtc().toIso8601String(),
        'received_order': receivedOrder.toJson(),
      };

  factory CheckoutVerificationResponse.fromJson(Map<String, dynamic> json) {
    final receivedOrderJson = json['received_order'];

    return CheckoutVerificationResponse(
      verificationId: json['verification_id']?.toString() ?? '',
      savedOrderId: _asInt(json['saved_order_id']) ?? 0,
      status: json['status']?.toString() ?? '',
      paymentMethod: json['payment_method']?.toString() ?? '',
      verificationStage: json['verification_stage']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now().toUtc(),
      receivedOrder: receivedOrderJson is Map<String, dynamic>
          ? CheckoutVerificationRequest.fromJson(receivedOrderJson)
          : CheckoutVerificationRequest(
              createdAt: DateTime.now().toUtc(),
              currency: 'PLN',
              totalAmount: 0,
              etaMinutes: 0,
              paymentMethod: '',
              fulfillmentMethod: '',
              fulfillmentOptionIndex: 0,
              addressOptionIndex: 0,
              address: const CheckoutVerificationAddress(title: '', subtitle: '', etaLabel: ''),
              items: const [],
            ),
    );
  }
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
