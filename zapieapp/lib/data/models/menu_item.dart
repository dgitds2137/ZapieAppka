class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.calories,
    required this.prepMinutes,
    this.imageUrl,
    this.isFavorite = false,
  });

  final int id;
  final String name;
  final String description;
  final String category;
  final double price;
  final int calories;
  final int prepMinutes;
  final String? imageUrl;
  final bool isFavorite;
}
