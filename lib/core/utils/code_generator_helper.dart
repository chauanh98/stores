class CodeGeneratorHelper {
  /// Sinh mã tăng dần tự động dựa theo tiền tố và danh sách các mã hiện có trong hệ thống.
  ///
  /// Ví dụ:
  /// - `prefix = 'HD'`, `existingCodes = ['HD000001', 'HD012770']` -> trả về `'HD012771'`
  /// - `prefix = 'KH'`, `existingCodes = ['KH000001']` -> trả về `'KH000002'`
  /// - `prefix = 'SP'`, `existingCodes = []` -> trả về `'SP000001'`
  static String generateNextCode(
    String prefix,
    List<String> existingCodes, {
    int padLength = 6,
  }) {
    int maxNumber = 0;
    final upperPrefix = prefix.toUpperCase();

    for (final rawCode in existingCodes) {
      final code = rawCode.trim().toUpperCase();
      if (code.startsWith(upperPrefix)) {
        // Tách phần số sau tiền tố
        final numericPart = code.substring(upperPrefix.length);
        // Tìm chuỗi các chữ số đầu tiên trong numericPart
        final match = RegExp(r'^\d+').firstMatch(numericPart);
        if (match != null) {
          final number = int.tryParse(match.group(0)!) ?? 0;
          if (number > maxNumber) {
            maxNumber = number;
          }
        }
      }
    }

    final nextNumber = maxNumber + 1;
    final formattedNumber = nextNumber.toString().padLeft(padLength, '0');
    return '$upperPrefix$formattedNumber';
  }

  /// Sinh mã đơn hàng tiếp theo (ví dụ: HD012771)
  static String generateNextOrderCode(List<String> existingOrderIds) {
    return generateNextCode('HD', existingOrderIds, padLength: 6);
  }

  /// Sinh mã khách hàng tiếp theo (ví dụ: KH006732)
  static String generateNextCustomerCode(List<String> existingCustomerIds) {
    return generateNextCode('KH', existingCustomerIds, padLength: 6);
  }

  /// Sinh mã sản phẩm tiếp theo (ví dụ: SP000001)
  static String generateNextProductCode(List<String> existingProductIds) {
    return generateNextCode('SP', existingProductIds, padLength: 6);
  }
}
