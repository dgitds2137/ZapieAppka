class ExtraPricingBreakdown {
  const ExtraPricingBreakdown({
    required this.totalPrice,
    required this.freeCountsByLabel,
    required this.paidCountsByLabel,
  });

  final double totalPrice;
  final Map<String, int> freeCountsByLabel;
  final Map<String, int> paidCountsByLabel;

  int freeCountForLabel(String label) => freeCountsByLabel[label] ?? 0;

  int paidCountForLabel(String label) => paidCountsByLabel[label] ?? 0;
}

ExtraPricingBreakdown computeExtraPricingBreakdown({
  required Map<String, int> extras,
  required Map<String, double> extraUnitPrices,
  required Map<String, int> defaultExtras,
  required Map<String, String> extraGroupKeys,
  required Map<String, int> includedExtrasByGroup,
  Map<String, String> preferredFreeLabelByGroup = const <String, String>{},
}) {
  final freeCountsByLabel = <String, int>{};
  final paidCountsByLabel = <String, int>{};
  final groupCandidates = <String, List<_PricedExtraUnit>>{};

  for (final entry in extras.entries) {
    final label = entry.key;
    final selectedCount = entry.value;
    if (selectedCount <= 0) {
      continue;
    }

    final defaultIncludedCount = defaultExtras[label] ?? 0;
    final defaultFreeCount = selectedCount < defaultIncludedCount
        ? selectedCount
        : defaultIncludedCount;
    if (defaultFreeCount > 0) {
      freeCountsByLabel[label] = defaultFreeCount;
    }

    final remainingCount = selectedCount - defaultFreeCount;
    if (remainingCount <= 0) {
      continue;
    }

    final groupKey = (extraGroupKeys[label] ?? '').trim().toLowerCase();
    if (groupKey.isEmpty) {
      paidCountsByLabel[label] = (paidCountsByLabel[label] ?? 0) + remainingCount;
      continue;
    }

    final unitPrice = extraUnitPrices[label] ?? 0;
    final units = groupCandidates.putIfAbsent(
      groupKey,
      () => <_PricedExtraUnit>[],
    );
    for (var index = 0; index < remainingCount; index++) {
      units.add(_PricedExtraUnit(label: label, unitPrice: unitPrice));
    }
  }

  var totalPrice = 0.0;

  for (final entry in groupCandidates.entries) {
    final groupKey = entry.key;
    final units = entry.value;
    units.sort((left, right) {
      final priceCompare = right.unitPrice.compareTo(left.unitPrice);
      if (priceCompare != 0) {
        return priceCompare;
      }
      return left.label.compareTo(right.label);
    });

    var freeUnitsRemaining = includedExtrasByGroup[groupKey] ?? 0;
    final preferredFreeLabel = preferredFreeLabelByGroup[groupKey]?.trim();
    if (freeUnitsRemaining > 0 &&
        preferredFreeLabel != null &&
        preferredFreeLabel.isNotEmpty) {
      final preferredIndex = units.indexWhere(
        (unit) => unit.label == preferredFreeLabel,
      );
      if (preferredIndex >= 0) {
        final preferredUnit = units.removeAt(preferredIndex);
        freeUnitsRemaining -= 1;
        freeCountsByLabel[preferredUnit.label] =
            (freeCountsByLabel[preferredUnit.label] ?? 0) + 1;
      }
    }

    for (final unit in units) {
      if (freeUnitsRemaining > 0) {
        freeUnitsRemaining -= 1;
        freeCountsByLabel[unit.label] = (freeCountsByLabel[unit.label] ?? 0) + 1;
        continue;
      }

      paidCountsByLabel[unit.label] = (paidCountsByLabel[unit.label] ?? 0) + 1;
      totalPrice += unit.unitPrice;
    }
  }

  for (final entry in paidCountsByLabel.entries) {
    final label = entry.key;
    final count = entry.value;
    if (count <= 0) {
      continue;
    }
    if (groupCandidates.values.any((units) => units.any((unit) => unit.label == label))) {
      continue;
    }
    totalPrice += count * (extraUnitPrices[label] ?? 0);
  }

  return ExtraPricingBreakdown(
    totalPrice: totalPrice,
    freeCountsByLabel: Map.unmodifiable(freeCountsByLabel),
    paidCountsByLabel: Map.unmodifiable(paidCountsByLabel),
  );
}

class _PricedExtraUnit {
  const _PricedExtraUnit({
    required this.label,
    required this.unitPrice,
  });

  final String label;
  final double unitPrice;
}
