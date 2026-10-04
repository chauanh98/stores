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

  /// Sinh mã nhà cung cấp tiếp theo (ví dụ: NCC000001)
  static String generateNextSupplierCode(List<String> existingSupplierCodes) {
    return generateNextCode('NCC', existingSupplierCodes, padLength: 6);
  }

  /// Phân tích mã hóa đơn thành (baseCode, version).
  /// Ví dụ:
  /// - 'HD000001' -> ('HD000001', 0)
  /// - 'HD000001_01' -> ('HD000001', 1)
  /// - 'HD000001.02' -> ('HD000001', 2)
  /// - 'HD000001-03' -> ('HD000001', 3)
  static (String baseCode, int version) parseInvoiceCode(String code) {
    final sanitized = code.trim();
    if (sanitized.isEmpty) {
      return ('HD000001', 0);
    }

    // Match trailing version suffix: e.g. _01, .01, -01, #01
    final suffixMatch =
        RegExp(r'^(.*?)[_.\-#$\[\]]+(\d+)$').firstMatch(sanitized);
    if (suffixMatch != null) {
      final base = suffixMatch
          .group(1)!
          .replaceAll(RegExp(r'[.#$\[\]]'), '')
          .trim();
      final ver = int.tryParse(suffixMatch.group(2)!) ?? 0;
      return (base.isEmpty ? 'HD000001' : base, ver);
    }

    final cleanBase = sanitized.replaceAll(RegExp(r'[.#$\[\]]'), '').trim();
    return (cleanBase.isEmpty ? 'HD000001' : cleanBase, 0);
  }

  /// Sinh mã hóa đơn mới cho chức năng Sửa hóa đơn theo phiên bản (Phương án 1):
  /// - Mã hóa đơn gốc: `HD000001`
  /// - Sửa lần 1: `HD000001_01`
  /// - Sửa lần 2: `HD000001_02`
  /// Dùng dấu gạch dưới `_` thay cho dấu chấm `.` để an toàn 100% với Firebase Realtime Database.
  static String generateVersionedInvoiceCode(
    String currentCode, {
    List<String> existingCodes = const [],
  }) {
    final (baseCode, currentVersion) = parseInvoiceCode(currentCode);
    int maxVersion = currentVersion;

    final basePattern = RegExp(
      '^${RegExp.escape(baseCode)}[_.\\-#\$\\[\\]]+(\\d+)\$',
      caseSensitive: false,
    );

    for (final raw in existingCodes) {
      final trimmed = raw.trim();
      final match = basePattern.firstMatch(trimmed);
      if (match != null) {
        final v = int.tryParse(match.group(1)!) ?? 0;
        if (v > maxVersion) {
          maxVersion = v;
        }
      }
    }

    final nextVersion = maxVersion + 1;
    final formattedVersion = nextVersion.toString().padLeft(2, '0');
    return '${baseCode}_$formattedVersion';
  }
}
