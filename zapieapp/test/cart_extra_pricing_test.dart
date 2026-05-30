import 'package:flutter_test/flutter_test.dart';
import 'package:zapieapp_flutter_starter/features/dashboard/cart_extra_pricing.dart';

void main() {
  test('applies one complimentary sauce before charging extras', () {
    final breakdown = computeExtraPricingBreakdown(
      extras: const {
        'Sos czosnkowy': 2,
        'Sos ostry': 1,
      },
      extraUnitPrices: const {
        'Sos czosnkowy': 2.0,
        'Sos ostry': 2.0,
      },
      defaultExtras: const {},
      extraGroupKeys: const {
        'Sos czosnkowy': 'sauce',
        'Sos ostry': 'sauce',
      },
      includedExtrasByGroup: const {
        'sauce': 1,
      },
    );

    expect(breakdown.totalPrice, 4.0);
    expect(
      breakdown.freeCountsByLabel.values.fold<int>(0, (sum, count) => sum + count),
      1,
    );
    expect(
      breakdown.paidCountsByLabel.values.fold<int>(0, (sum, count) => sum + count),
      2,
    );
  });

  test('keeps non-sauce defaults and charges only over default quantity', () {
    final breakdown = computeExtraPricingBreakdown(
      extras: const {
        'Salami': 2,
      },
      extraUnitPrices: const {
        'Salami': 4.0,
      },
      defaultExtras: const {
        'Salami': 1,
      },
      extraGroupKeys: const {
        'Salami': 'hot',
      },
      includedExtrasByGroup: const {},
    );

    expect(breakdown.totalPrice, 4.0);
    expect(breakdown.freeCountForLabel('Salami'), 1);
    expect(breakdown.paidCountForLabel('Salami'), 1);
  });

  test('keeps the explicitly chosen complimentary sauce free first', () {
    final breakdown = computeExtraPricingBreakdown(
      extras: const {
        'Sos czosnkowy': 1,
        'Sos BBQ': 1,
      },
      extraUnitPrices: const {
        'Sos czosnkowy': 1.5,
        'Sos BBQ': 2.5,
      },
      defaultExtras: const {},
      extraGroupKeys: const {
        'Sos czosnkowy': 'sauce',
        'Sos BBQ': 'sauce',
      },
      includedExtrasByGroup: const {
        'sauce': 1,
      },
      preferredFreeLabelByGroup: const {
        'sauce': 'Sos czosnkowy',
      },
    );

    expect(breakdown.freeCountForLabel('Sos czosnkowy'), 1);
    expect(breakdown.paidCountForLabel('Sos BBQ'), 1);
    expect(breakdown.totalPrice, 2.5);
  });
}
