import 'package:flutter_test/flutter_test.dart';
import 'package:zapieapp_flutter_starter/features/dashboard/catalog_sorting.dart';

void main() {
  test('sorts zapiekanki by explicit sort_order before title', () {
    final items = [
      {
        'name': 'Salame 50cm',
        'sort_order': 40,
      },
      {
        'name': 'Pieczarka 50cm',
        'sort_order': 10,
      },
      {
        'name': 'Szynka 50cm',
        'sort_order': 20,
      },
    ];

    final sorted = sortDashboardCategoryItems('zapiekanki', items);

    expect(
      sorted.map((item) => item['name']).toList(),
      [
        'Pieczarka 50cm',
        'Szynka 50cm',
        'Salame 50cm',
      ],
    );
  });

  test('falls back to business order for 0,5 m zapiekanki without sort_order', () {
    final items = [
      {
        'name': 'Grecka 50cm',
      },
      {
        'name': 'Jalapeno Salami 50cm',
      },
      {
        'name': 'Pieczarka 50cm',
      },
      {
        'name': 'Goralska 50cm',
      },
      {
        'name': 'Hawajska 50cm',
      },
      {
        'name': 'Wiejska 50cm',
      },
      {
        'name': 'Szynka 50cm',
      },
      {
        'name': 'Salami 50cm',
      },
    ];

    final sorted = sortDashboardCategoryItems('zapiekanki', items);

    expect(
      sorted.map((item) => item['name']).toList(),
      [
        'Pieczarka 50cm',
        'Szynka 50cm',
        'Hawajska 50cm',
        'Salami 50cm',
        'Jalapeno Salami 50cm',
        'Wiejska 50cm',
        'Goralska 50cm',
        'Grecka 50cm',
      ],
    );
  });

  test('keeps generic category sorting by sort_order then title', () {
    final items = [
      {
        'name': 'Sprite puszka 0.33',
        'sort_order': 30,
      },
      {
        'name': 'Coca Cola puszka 0.33',
        'sort_order': 10,
      },
      {
        'name': 'Fanta puszka 0.33',
        'sort_order': 20,
      },
    ];

    final sorted = sortDashboardCategoryItems('napoje', items);

    expect(
      sorted.map((item) => item['name']).toList(),
      [
        'Coca Cola puszka 0.33',
        'Fanta puszka 0.33',
        'Sprite puszka 0.33',
      ],
    );
  });
}
