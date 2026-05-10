import '../models/order_overview.dart';

abstract class OrderRepository {
  Future<List<OrderOverview>> fetchOrders();
}
