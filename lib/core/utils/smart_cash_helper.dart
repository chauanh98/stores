class SmartCashHelper {
  /// Sinh danh sách các mệnh giá tiền mặt gợi ý thông minh dựa trên số tiền cần thanh toán (Net Pay).
  ///
  /// Danh sách luôn bắt đầu bằng chính xác `netPay` (Trả đủ),
  /// theo sau là các mốc tiền làm tròn phổ biến theo mệnh giá VND (50k, 100k, 200k, 500k, 1.000.000đ,...),
  /// được sắp xếp tăng dần và giới hạn tối đa [maxSuggestions] gợi ý (mặc định 5).
  static List<double> generateSmartCashSuggestions(
    double netPay, {
    int maxSuggestions = 5,
  }) {
    if (netPay <= 0) return [];

    final suggestions = <double>{netPay};

    // Các mốc cơ sở làm tròn tiền mặt VND phổ biến
    final bases = [
      10000.0,
      20000.0,
      50000.0,
      100000.0,
      200000.0,
      500000.0,
      1000000.0,
    ];

    for (final base in bases) {
      final rounded = (netPay / base).ceil() * base;
      if (rounded >= netPay) {
        suggestions.add(rounded);
      }
    }

    // Bổ sung thêm các mốc kế tiếp nếu số lượng gợi ý còn ít (ví dụ khi netPay là số chẵn tròn)
    if (suggestions.length < maxSuggestions) {
      if (netPay < 500000) {
        final next100k = ((netPay / 100000).ceil() + 1) * 100000.0;
        if (next100k > netPay) suggestions.add(next100k);
        final next200k = ((netPay / 200000).ceil() + 1) * 200000.0;
        if (next200k > netPay) suggestions.add(next200k);
        final next500k = ((netPay / 500000).ceil() + 1) * 500000.0;
        if (next500k > netPay) suggestions.add(next500k);
      } else {
        final next500k = ((netPay / 500000).ceil() + 1) * 500000.0;
        if (next500k > netPay) suggestions.add(next500k);
        final next1M = ((netPay / 1000000).ceil() + 1) * 1000000.0;
        if (next1M > netPay) suggestions.add(next1M);
      }
    }

    final sortedList = suggestions.toList()..sort();
    if (sortedList.length > maxSuggestions) {
      return sortedList.sublist(0, maxSuggestions);
    }
    return sortedList;
  }
}
