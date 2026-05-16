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
    required this.deliveryMinimumAmount,
    required this.deliveryRadiusKm,
    required this.deliveryOriginAddress,
    required this.positions,
    required this.addons,
  });

  final double deliveryMinimumAmount;
  final double deliveryRadiusKm;
  final String deliveryOriginAddress;
  final List<AdminCatalogPosition> positions;
  final List<AdminCatalogAddon> addons;

  factory AdminCatalogData.fromJson(Map<String, dynamic> json) {
    final positionsJson = json['positions'];
    final addonsJson = json['addons'];

    return AdminCatalogData(
      deliveryMinimumAmount: _asDouble(json['delivery_minimum_amount']) ?? 20,
      deliveryRadiusKm: _asDouble(json['delivery_radius_km']) ?? 8,
      deliveryOriginAddress: json['delivery_origin_address']?.toString() ?? '',
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
    this.ovenKind = 'none',
    this.canMarkInOven = true,
    this.ovenSlotCount = 0,
    this.ovenLoad = 0,
    this.ovenCapacity = 6,
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
  final String ovenKind;
  final bool canMarkInOven;
  final int ovenSlotCount;
  final int ovenLoad;
  final int ovenCapacity;
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
      ovenKind: json['oven_kind']?.toString() ?? 'none',
      canMarkInOven: json['can_mark_in_oven'] != false,
      ovenSlotCount: _asInt(json['oven_slot_count']) ?? 0,
      ovenLoad: _asInt(json['oven_load']) ?? 0,
      ovenCapacity: _asInt(json['oven_capacity']) ?? 6,
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
    required this.ovenLoad,
    required this.ovenCapacity,
    required this.udkaOvenLoad,
    required this.udkaOvenCapacity,
    required this.udkaSlotLabel,
    required this.pendingOrderCount,
    required this.inProgressOrderCount,
    required this.newUsersThisMonth,
    required this.completedOrdersToday,
    required this.orderHistoryCount,
    required this.turnoverLastDays,
    required this.pendingOrders,
    required this.inProgressOrders,
    required this.closedOrders,
    this.closedOrdersHasMore = false,
    required this.myTakenOrders,
  });

  final int loggedInEmployeeCount;
  final List<AdminDashboardActiveEmployee> activeEmployees;
  final List<AdminPrepTimeSetting> prepTimeSettings;
  final int ovenLoad;
  final int ovenCapacity;
  final int udkaOvenLoad;
  final int udkaOvenCapacity;
  final String udkaSlotLabel;
  final int pendingOrderCount;
  final int inProgressOrderCount;
  final int newUsersThisMonth;
  final int completedOrdersToday;
  final int orderHistoryCount;
  final List<AdminDashboardTurnoverPoint> turnoverLastDays;
  final List<AdminDashboardOrder> pendingOrders;
  final List<AdminDashboardOrder> inProgressOrders;
  final List<AdminDashboardOrder> closedOrders;
  final bool closedOrdersHasMore;
  final List<AdminDashboardOrder> myTakenOrders;

  factory AdminDashboardData.fromJson(Map<String, dynamic> json) {
    final activeEmployeesJson = json['active_employees'];
    final prepTimeSettingsJson = json['prep_time_settings'];
    final turnoverJson = json['turnover_last_days'];
    final pendingJson = json['pending_orders'];
    final inProgressJson = json['in_progress_orders'];
    final closedJson = json['closed_orders'];
    final myTakenJson = json['my_taken_orders'];

    final pendingOrders = pendingJson is List
        ? pendingJson
            .whereType<Map>()
            .map((item) => AdminDashboardOrder.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(growable: false)
        : const <AdminDashboardOrder>[];
    final inProgressOrders = inProgressJson is List
        ? inProgressJson
            .whereType<Map>()
            .map((item) => AdminDashboardOrder.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(growable: false)
        : const <AdminDashboardOrder>[];
    final closedOrders = closedJson is List
        ? closedJson
            .whereType<Map>()
            .map((item) => AdminDashboardOrder.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(growable: false)
        : const <AdminDashboardOrder>[];
    final myTakenOrders = myTakenJson is List
        ? myTakenJson
            .whereType<Map>()
            .map(
              (item) => AdminDashboardOrder.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false)
        : const <AdminDashboardOrder>[];
    final fallbackOvenCapacity =
        _ovenCapacityFromOrders(inProgressOrders) ?? 6;
    final fallbackOvenLoad = _ovenLoadFromOrders(inProgressOrders);

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
      ovenLoad: _asInt(json['oven_load']) ?? fallbackOvenLoad,
      ovenCapacity: _asInt(json['oven_capacity']) ?? fallbackOvenCapacity,
      udkaOvenLoad: _asInt(json['udka_oven_load']) ?? 0,
      udkaOvenCapacity: _asInt(json['udka_oven_capacity']) ?? 16,
      udkaSlotLabel: json['udka_slot_label']?.toString() ?? '',
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
      pendingOrders: pendingOrders,
      inProgressOrders: inProgressOrders,
      closedOrders: closedOrders,
      closedOrdersHasMore: json['closed_orders_has_more'] == true,
      myTakenOrders: myTakenOrders,
    );
  }
}

class AdminStaffPresencePerson {
  const AdminStaffPresencePerson({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.initials,
    required this.lastSeenAt,
    required this.isCurrentlyAvailable,
  });

  final int userId;
  final String email;
  final String displayName;
  final String initials;
  final DateTime? lastSeenAt;
  final bool isCurrentlyAvailable;

  factory AdminStaffPresencePerson.fromJson(Map<String, dynamic> json) {
    return AdminStaffPresencePerson(
      userId: _asInt(json['user_id']) ?? 0,
      email: json['email']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      initials: json['initials']?.toString() ?? '',
      lastSeenAt: DateTime.tryParse(json['last_seen_at']?.toString() ?? ''),
      isCurrentlyAvailable: json['is_currently_available'] == true,
    );
  }
}

class AdminStaffPresenceData {
  const AdminStaffPresenceData({
    required this.currentlyAvailable,
    required this.recentlyAvailable,
    required this.allResults,
  });

  final List<AdminStaffPresencePerson> currentlyAvailable;
  final List<AdminStaffPresencePerson> recentlyAvailable;
  final List<AdminStaffPresencePerson> allResults;

  factory AdminStaffPresenceData.fromJson(Map<String, dynamic> json) {
    List<AdminStaffPresencePerson> parseList(String key) {
      final raw = json[key];
      if (raw is! List) {
        return const [];
      }
      return raw
          .whereType<Map>()
          .map(
            (item) => AdminStaffPresencePerson.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false);
    }

    return AdminStaffPresenceData(
      currentlyAvailable: parseList('currently_available'),
      recentlyAvailable: parseList('recently_available'),
      allResults: parseList('all_results'),
    );
  }
}

int _ovenLoadFromOrders(List<AdminDashboardOrder> orders) {
  return orders
      .where(_isOrderInOven)
      .fold(0, (total, order) => total + order.ovenSlotCount);
}

int? _ovenCapacityFromOrders(List<AdminDashboardOrder> orders) {
  for (final order in orders) {
    if (order.ovenCapacity > 0) {
      return order.ovenCapacity;
    }
  }
  return null;
}

bool _isOrderInOven(AdminDashboardOrder order) {
  final stage = order.verificationStage.trim().toLowerCase();
  return stage == 'in_oven' || stage == 'oven';
}

class AdminClosedOrdersPage {
  const AdminClosedOrdersPage({
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
  final List<AdminDashboardOrder> orders;

  factory AdminClosedOrdersPage.fromJson(Map<String, dynamic> json) {
    final ordersJson = json['orders'];
    return AdminClosedOrdersPage(
      page: _asInt(json['page']) ?? 1,
      pageSize: _asInt(json['page_size']) ?? 15,
      totalCount: _asInt(json['total_count']) ?? 0,
      hasMore: json['has_more'] == true,
      orders: ordersJson is List
          ? ordersJson
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
