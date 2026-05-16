class OpeningHoursData {
  const OpeningHoursData({
    required this.openTime,
    required this.closeTime,
    required this.formattedRange,
    required this.isOpenNow,
  });

  final String openTime;
  final String closeTime;
  final String formattedRange;
  final bool isOpenNow;

  String get primaryLabel =>
      isOpenNow ? 'Dzisiaj otwarte $formattedRange' : 'Dzisiaj $formattedRange';

  String get statusLabel => isOpenNow ? 'Otwarte' : 'Zamkniete';

  factory OpeningHoursData.fromJson(Map<String, dynamic> json) {
    final openTime = json['open_time']?.toString().trim();
    final closeTime = json['close_time']?.toString().trim();
    final formattedRange = json['formatted_range']?.toString().trim();

    final normalizedOpenTime =
        openTime == null || openTime.isEmpty ? '12:00' : openTime;
    final normalizedCloseTime =
        closeTime == null || closeTime.isEmpty ? '21:00' : closeTime;
    final normalizedRange =
        formattedRange == null || formattedRange.isEmpty
            ? '$normalizedOpenTime-$normalizedCloseTime'
            : formattedRange;

    return OpeningHoursData(
      openTime: normalizedOpenTime,
      closeTime: normalizedCloseTime,
      formattedRange: normalizedRange,
      isOpenNow: json['is_open_now'] == true,
    );
  }
}
