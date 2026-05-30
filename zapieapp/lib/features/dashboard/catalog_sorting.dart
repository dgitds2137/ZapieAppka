List<Map<String, dynamic>> sortDashboardCategoryItems(
  String categoryKey,
  Iterable<Map<String, dynamic>> items,
) {
  final sorted = items.toList(growable: true);
  sorted.sort((left, right) {
    final sortOrderCompare = _effectiveSortOrder(
      left,
      categoryKey: categoryKey,
    ).compareTo(
      _effectiveSortOrder(
        right,
        categoryKey: categoryKey,
      ),
    );
    if (sortOrderCompare != 0) {
      return sortOrderCompare;
    }

    return _normalizedTitle(left).compareTo(_normalizedTitle(right));
  });
  return List.unmodifiable(sorted);
}

int _effectiveSortOrder(
  Map<String, dynamic> item, {
  required String categoryKey,
}) {
  final rawSortOrder = _asInt(item['sort_order']);
  if (rawSortOrder != null && rawSortOrder > 0) {
    return rawSortOrder;
  }

  if (categoryKey == 'zapiekanki') {
    final fallbackSortOrder = _zapiekankaHalfMeterFallbackSortOrder(
      _normalizedTitle(item),
    );
    if (fallbackSortOrder != null) {
      return fallbackSortOrder;
    }
  }

  return 1000;
}

int? _zapiekankaHalfMeterFallbackSortOrder(String title) {
  return switch (title) {
    'pieczarka 50cm' => 10,
    'szynka 50cm' => 20,
    'hawajska 50cm' => 30,
    'salami 50cm' || 'salame 50cm' => 40,
    'jalapeno salami 50cm' || 'jalapeno salame 50cm' => 50,
    'wiejska 50cm' => 60,
    'goralska 50cm' => 70,
    'grecka 50cm' => 80,
    _ => null,
  };
}

String _normalizedTitle(Map<String, dynamic> item) {
  return (item['name']?.toString() ??
          item['title']?.toString() ??
          item['position_name']?.toString() ??
          '')
      .trim()
      .toLowerCase();
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
