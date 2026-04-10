import 'package:flutter/foundation.dart';

import '../data/models/cart_item.dart';
import '../data/models/menu_item.dart';
import '../data/models/order_overview.dart';
import '../data/repositories/menu_repository.dart';
import '../data/repositories/order_repository.dart';

class AppState extends ChangeNotifier {
  AppState({required MenuRepository menuRepository, required OrderRepository orderRepository})
      : _menuRepository = menuRepository,
        _orderRepository = orderRepository;

  final MenuRepository _menuRepository;
  final OrderRepository _orderRepository;

  List<MenuItem> _menu = [];
  final List<CartItem> _cart = [];
  List<OrderOverview> _orders = [];
  String selectedCategory = 'zapiekanki';
  String fulfillmentType = 'delivery';
  String paymentMethod = 'blik';
  String selectedAddress = 'Skłotowa 6/9, 02-220 Warszawa';

  List<MenuItem> get menu => _menu;
  List<CartItem> get cart => List.unmodifiable(_cart);
  List<OrderOverview> get orders => _orders;

  Future<void> bootstrap() async {
    _menu = await _menuRepository.fetchMenu();
    _orders = await _orderRepository.fetchOrders();
    if (_cart.isEmpty && _menu.length >= 2) {
      _cart.addAll([
        CartItem(menuItem: _menu[0], serving: 'Pudełko', cut: 'Na pół'),
        CartItem(menuItem: _menu[1]),
      ]);
    }
    notifyListeners();
  }

  List<MenuItem> get favorites => _menu.where((e) => e.isFavorite).toList();
  List<MenuItem> get recent => _menu.take(3).toList();
  List<MenuItem> menuForCategory(String category) => _menu.where((e) => e.category == category).toList();
  double get cartTotal => _cart.fold(0, (sum, item) => sum + item.totalPrice);

  void changeCategory(String category) { selectedCategory = category; notifyListeners(); }
  void addToCart(MenuItem item) { /* minimalna logika */ }
  void updateQuantity(MenuItem item, int delta) { /* minimalna logika */ }
  void updateCustomization({required MenuItem item, required String serving, required String cut, required List<String> extras}) { /* minimalna logika */ }
  void setFulfillmentType(String value) { fulfillmentType = value; notifyListeners(); }
  void setPaymentMethod(String value) { paymentMethod = value; notifyListeners(); }
  void selectAddress(String value) { selectedAddress = value; notifyListeners(); }
}