import 'menu_item.dart';

class CartItem {
  CartItem({
    required this.menuItem,
    this.quantity = 1,
    this.serving = 'Standard',
    this.cut = 'Bez krojenia',
    List<String>? extras,
  }) : extras = extras ?? <String>[];

  final MenuItem menuItem;
  int quantity;
  String serving;
  String cut;
  List<String> extras;

  double get totalPrice => menuItem.price * quantity;
}
