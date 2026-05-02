class AdminDashboardTurnoverPoint {
  const AdminDashboardTurnoverPoint({
    required this.dayLabel,
    required this.totalAmount,
  });

  final String dayLabel;
  final double totalAmount;

  factory AdminDashboardTurnoverPoint.fromJson(Map<String, dynamic> json) {
    return AdminDashboardTurnoverPoint(
      dayLabel: json['day_label']?.toString() ?? '',
      totalAmount: _asDouble(json['total_amount']) ?? 0,
    );
  }
}

class AdminDashboardActiveEmployee {
  const AdminDashboardActiveEmployee({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.initials,
    required this.lastSeenAt,
  });

  final int userId;
  final String email;
  final String displayName;
  final String initials;
  final DateTime lastSeenAt;

  factory AdminDashboardActiveEmployee.fromJson(Map<String, dynamic> json) {
    return AdminDashboardActiveEmployee(
      userId: _asInt(json['user_id']) ?? 0,
      email: json['email']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      initials: json['initials']?.toString() ?? '',
      lastSeenAt: DateTime.tryParse(json['last_seen_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

class AdminPrepTimeSetting {
  const AdminPrepTimeSetting({
    required this.groupKey,
    required this.label,
    required this.minutes,
    required this.sortOrder,
    required this.isActive,
  });

  final String groupKey;
  final String label;
  final int minutes;
  final int sortOrder;
  final bool isActive;

  factory AdminPrepTimeSetting.fromJson(Map<String, dynamic> json) {
    return AdminPrepTimeSetting(
      groupKey: json['group_key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      minutes: _asInt(json['minutes']) ?? 0,
      sortOrder: _asInt(json['sort_order']) ?? 0,
      isActive: json['is_active'] != false,
    );
  }
}

class AdminCatalogPosition {
  const AdminCatalogPosition({
    required this.positionId,
    required this.positionType,
    required this.name,
    this.description,
    this.price,
    required this.isActive,
  });

  final int positionId;
  final String positionType;
  final String name;
  final String? description;
  final double? price;
  final bool isActive;

  factory AdminCatalogPosition.fromJson(Map<String, dynamic> json) {
    return AdminCatalogPosition(
      positionId: _asInt(json['position_id']) ?? 0,
      positionType: json['position_type']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      price: _asDouble(json['price']),
      isActive: json['is_active'] != false,
    );
  }
}

class AdminCatalogAddon {
  const AdminCatalogAddon({
    required this.addonId,
    required this.name,
    this.description,
    required this.price,
    required this.sortOrder,
    required this.isActive,
  });

  final int addonId;
  final String name;
  final String? description;
  final double price;
  final int sortOrder;
  final bool isActive;

  factory AdminCatalogAddon.fromJson(Map<String, dynamic> json) {
    return AdminCatalogAddon(
      addonId: _asInt(json['addon_id']) ?? 0,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      price: _asDouble(json['price']) ?? 0,
      sortOrder: _asInt(json['sort_order']) ?? 0,
      isActive: json['is_active'] != false,
    );
  }
}

class AdminCatalogData {
  const AdminCatalogData({
    required this.positions,
    required this.addons,
  });

  final List<AdminCatalogPosition> positions;
  final List<AdminCatalogAddon> addons;

  factory AdminCatalogData.fromJson(Map<String, dynamic> json) {
    final positionsJson = json['positions'];
    final addonsJson = json['addons'];

    return AdminCatalogData(
      positions: positionsJson is List
          ? positionsJson
              .whereType<Map>()
              .map(
                (item) => AdminCatalogPosition.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
          : const [],
      addons: addonsJson is List
          ? addonsJson
              .whereType<Map>()
              .map(
                (item) => AdminCatalogAddon.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
          : const [],
    );
  }
}

class AdminDashboardOrder {
  const AdminDashboardOrder({
    required this.checkoutOrderId,
    required this.verificationId,
    required this.processingStatus,
    required this.lifecycleStatus,
    required this.verificationStage,
    required this.createdAt,
    this.closedAt,
    this.activeUntil,
    required this.remainingEtaMinutes,
    this.customerEmail,
    required this.paymentMethod,
    required this.fulfillmentMethod,
    required this.totalAmount,
    required this.itemCount,
    required this.itemNames,
    required this.items,
    required this.addressTitle,
    required this.addressSubtitle,
    this.notes,
    bool? supportsProgressUpdates = true,
    this.unreadCustomerMessageCount = 0,
    this.assignedToMe = false,
    this.assignedOperatorEmail,
  }) : _supportsProgressUpdates = supportsProgressUpdates;

  final int checkoutOrderId;
  final String verificationId;
  final String processingStatus;
  final String lifecycleStatus;
  final String verificationStage;
  final DateTime createdAt;
  final DateTime? closedAt;
  final DateTime? activeUntil;
  final int remainingEtaMinutes;
  final String? customerEmail;
  final String paymentMethod;
  final String fulfillmentMethod;
  final double totalAmount;
  final int itemCount;
  final List<String> itemNames;
  final List<AdminDashboardOrderItem> items;
  final String addressTitle;
  final String addressSubtitle;
  final String? notes;
  final bool? _supportsProgressUpdates;
  final int unreadCustomerMessageCount;
  final bool assignedToMe;
  final String? assignedOperatorEmail;
  bool get supportsProgressUpdates => _supportsProgressUpdates ?? true;

  bool get isPending => processingStatus == 'unassigned';
  bool get isInProgress => processingStatus == 'assigned';

  factory AdminDashboardOrder.fromJson(Map<String, dynamic> json) {
    final itemNamesJson = json['item_names'];
    final itemsJson = json['items'];

    return AdminDashboardOrder(
      checkoutOrderId: _asInt(json['checkout_order_id']) ?? 0,
      verificationId: json['verification_id']?.toString() ?? '',
      processingStatus: json['processing_status']?.toString() ?? '',
      lifecycleStatus: json['lifecycle_status']?.toString() ?? '',
      verificationStage: json['verification_stage']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      closedAt: DateTime.tryParse(json['closed_at']?.toString() ?? ''),
      activeUntil: DateTime.tryParse(json['active_until']?.toString() ?? ''),
      remainingEtaMinutes: _asInt(json['remaining_eta_minutes']) ?? 0,
      customerEmail: json['customer_email']?.toString(),
      paymentMethod: json['payment_method']?.toString() ?? '',
      fulfillmentMethod: json['fulfillment_method']?.toString() ?? '',
      totalAmount: _asDouble(json['total_amount']) ?? 0,
      itemCount: _asInt(json['item_count']) ?? 0,
      itemNames: itemNamesJson is List
          ? itemNamesJson.map((item) => item.toString()).toList(growable: false)
          : const [],
      items: itemsJson is List
          ? itemsJson
              .whereType<Map>()
              .map(
                (item) => AdminDashboardOrderItem.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
          : const [],
      addressTitle: json['address_title']?.toString() ?? '',
      addressSubtitle: json['address_subtitle']?.toString() ?? '',
      notes: json['notes']?.toString(),
      supportsProgressUpdates: json['supports_progress_updates'] != false,
      unreadCustomerMessageCount:
          _asInt(json['unread_customer_message_count']) ?? 0,
      assignedToMe: json['assigned_to_me'] == true,
      assignedOperatorEmail: json['assigned_operator_email']?.toString(),
    );
  }
}

class AdminDashboardOrderItem {
  const AdminDashboardOrderItem({
    required this.name,
    required this.quantity,
    this.price,
    this.description,
  });

  final String name;
  final int quantity;
  final double? price;
  final String? description;

  factory AdminDashboardOrderItem.fromJson(Map<String, dynamic> json) {
    return AdminDashboardOrderItem(
      name: json['name']?.toString() ?? '',
      quantity: _asInt(json['quantity']) ?? 1,
      price: _asDouble(json['price']),
      description: json['description']?.toString(),
    );
  }
}

class AdminDashboardData {
  const AdminDashboardData({
    required this.loggedInEmployeeCount,
    required this.activeEmployees,
    required this.prepTimeSettings,
    required this.pendingOrderCount,
    required this.inProgressOrderCount,
    required this.newUsersThisMonth,
    required this.completedOrdersToday,
    required this.orderHistoryCount,
    required this.turnoverLastDays,
    required this.pendingOrders,
    required this.inProgressOrders,
    required this.closedOrders,
    required this.myTakenOrders,
  });

  final int loggedInEmployeeCount;
  final List<AdminDashboardActiveEmployee> activeEmployees;
  final List<AdminPrepTimeSetting> prepTimeSettings;
  final int pendingOrderCount;
  final int inProgressOrderCount;
  final int newUsersThisMonth;
  final int completedOrdersToday;
  final int orderHistoryCount;
  final List<AdminDashboardTurnoverPoint> turnoverLastDays;
  final List<AdminDashboardOrder> pendingOrders;
  final List<AdminDashboardOrder> inProgressOrders;
  final List<AdminDashboardOrder> closedOrders;
  final List<AdminDashboardOrder> myTakenOrders;

  factory AdminDashboardData.fromJson(Map<String, dynamic> json) {
    final activeEmployeesJson = json['active_employees'];
    final prepTimeSettingsJson = json['prep_time_settings'];
    final turnoverJson = json['turnover_last_days'];
    final pendingJson = json['pending_orders'];
    final inProgressJson = json['in_progress_orders'];
    final closedJson = json['closed_orders'];
    final myTakenJson = json['my_taken_orders'];

    return AdminDashboardData(
      loggedInEmployeeCount: _asInt(json['logged_in_employee_count']) ?? 0,
      activeEmployees: activeEmployeesJson is List
          ? activeEmployeesJson
              .whereType<Map>()
              .map(
                (item) => AdminDashboardActiveEmployee.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
          : const [],
      prepTimeSettings: prepTimeSettingsJson is List
          ? prepTimeSettingsJson
              .whereType<Map>()
              .map(
                (item) => AdminPrepTimeSetting.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
          : const [],
      pendingOrderCount: _asInt(json['pending_order_count']) ?? 0,
      inProgressOrderCount: _asInt(json['in_progress_order_count']) ?? 0,
      newUsersThisMonth: _asInt(json['new_users_this_month']) ?? 0,
      completedOrdersToday: _asInt(json['completed_orders_today']) ?? 0,
      orderHistoryCount: _asInt(json['order_history_count']) ?? 0,
      turnoverLastDays: turnoverJson is List
          ? turnoverJson
              .whereType<Map>()
              .map((item) => AdminDashboardTurnoverPoint.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
      pendingOrders: pendingJson is List
          ? pendingJson
              .whereType<Map>()
              .map((item) => AdminDashboardOrder.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
      inProgressOrders: inProgressJson is List
          ? inProgressJson
              .whereType<Map>()
              .map((item) => AdminDashboardOrder.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
      closedOrders: closedJson is List
          ? closedJson
              .whereType<Map>()
              .map((item) => AdminDashboardOrder.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
      myTakenOrders: myTakenJson is List
          ? myTakenJson
              .whereType<Map>()
              .map(
                (item) => AdminDashboardOrder.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false)
          : const [],
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
