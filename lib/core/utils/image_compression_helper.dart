import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Helper tiện ích nén ảnh và xử lý Base64 Data URL chuẩn
class ImageCompressionHelper {
  const ImageCompressionHelper._();

  /// Nén ảnh sang định dạng JPEG với kích thước tối đa [maxWidth]x[maxHeight]
  /// và chất lượng [quality]% (mặc định 70% theo chuẩn R2).
  ///
  /// Tự động xoay ảnh theo EXIF orientation và đảm bảo dung lượng siêu nhẹ (~15KB - 30KB)
  /// để lưu an toàn vào Realtime Database mà không gây tràn bộ nhớ.
  static Uint8List compressImageBytes(
    Uint8List inputBytes, {
    int maxWidth = 300,
    int maxHeight = 300,
    int quality = 70,
  }) {
    if (inputBytes.isEmpty) return inputBytes;

    try {
      final decoded = img.decodeImage(inputBytes);
      if (decoded == null) {
        debugPrint(
            '[ImageCompressionHelper] decodeImage returned null, using raw bytes');
        return inputBytes;
      }

      // 1. Tự động chuẩn hóa góc xoay theo EXIF tags từ máy ảnh thiết bị thực
      final oriented = img.bakeOrientation(decoded);
      img.Image processed = oriented;

      // 2. Tránh nén lại (re-compression avoidance) nếu ảnh đầu vào đã là JPEG hợp lệ,
      // kích thước đã nằm trong giới hạn maxWidth x maxHeight, và dung lượng đã siêu nhẹ (<= 30KB)
      final bool isAlreadyJpeg = inputBytes.length >= 3 &&
          inputBytes[0] == 0xFF &&
          inputBytes[1] == 0xD8 &&
          inputBytes[2] == 0xFF;
      if (isAlreadyJpeg &&
          oriented.width <= maxWidth &&
          oriented.height <= maxHeight &&
          inputBytes.length <= 30 * 1024) {
        return inputBytes;
      }

      // 3. Chỉ thu nhỏ kích thước nếu vượt quá giới hạn maxWidth hoặc maxHeight
      if (oriented.width > maxWidth || oriented.height > maxHeight) {
        final double widthRatio = maxWidth / oriented.width;
        final double heightRatio = maxHeight / oriented.height;
        if (widthRatio <= heightRatio) {
          processed = img.copyResize(
            oriented,
            width: maxWidth,
            maintainAspect: true,
          );
        } else {
          processed = img.copyResize(
            oriented,
            height: maxHeight,
            maintainAspect: true,
          );
        }
      }

      final jpgBytes = img.encodeJpg(processed, quality: quality);
      return Uint8List.fromList(jpgBytes);
    } catch (e, stack) {
      debugPrint(
          '[ImageCompressionHelper] Error compressing image: $e\n$stack');
      return inputBytes;
    }
  }

  /// Chuyển mảng byte ảnh thành chuỗi Data URI chuẩn: `data:image/jpeg;base64,...`
  static String toBase64DataUrl(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
  }) {
    final base64String = base64Encode(bytes);
    return 'data:$mimeType;base64,$base64String';
  }

  /// Kiểm tra xem một chuỗi URL có phải là Base64 Data URI hay không
  static bool isBase64DataUrl(String? url) {
    if (url == null) return false;
    final trimmed = url.trim();
    return trimmed.startsWith('data:image') && trimmed.contains('base64,');
  }

  /// Giải mã chuỗi Base64 Data URI thành Uint8List (bắt lỗi an toàn, hỗ trợ unpadded và URI-encoded)
  static Uint8List? decodeBase64DataUrl(String? dataUrl) {
    if (!isBase64DataUrl(dataUrl)) return null;

    try {
      final trimmed = dataUrl!.trim();
      final commaIndex = trimmed.indexOf(',');
      if (commaIndex == -1) return null;

      var base64Payload =
          trimmed.substring(commaIndex + 1).replaceAll(RegExp(r'\s+'), '');
      if (base64Payload.isEmpty) return null;

      if (base64Payload.contains('%')) {
        try {
          base64Payload = Uri.decodeComponent(base64Payload);
        } catch (_) {}
      }

      final normalized = base64.normalize(base64Payload);
      return base64Decode(normalized);
    } catch (e) {
      debugPrint(
          '[ImageCompressionHelper] Failed to decode base64 data url: $e');
      return null;
    }
  }

  /// Trích xuất danh sách tất cả các URL ảnh từ chuỗi đầu vào.
  /// Hỗ trợ cả Network URL (HTTP/HTTPS/GS) và Base64 Data URL (`data:image/...`),
  /// đảm bảo không bị cắt đứt dấu phẩy phân tách bên trong Data URL.
  static List<String> parseImageUrls(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final trimmed = raw.trim();

    // 1. Trường hợp chuỗi đơn giản không chứa dấu phẩy
    if (!trimmed.contains(',')) {
      if (trimmed.startsWith('http://') ||
          trimmed.startsWith('https://') ||
          trimmed.startsWith('gs://') ||
          isBase64DataUrl(trimmed)) {
        return [trimmed];
      }
      return const [];
    }

    // 2. Trường hợp là 1 Base64 Data URL duy nhất (chỉ có dấu phẩy sau tiền tố base64)
    if (trimmed.startsWith('data:image') &&
        !trimmed.contains(',http://') &&
        !trimmed.contains(',https://') &&
        !trimmed.contains(',gs://') &&
        !trimmed.contains(',data:image') &&
        !trimmed.contains(', http://') &&
        !trimmed.contains(', https://') &&
        !trimmed.contains(', gs://') &&
        !trimmed.contains(', data:image')) {
      if (isBase64DataUrl(trimmed)) {
        return [trimmed];
      }
    }

    // 3. Quét và phân tách các URL độc lập
    final parts = trimmed.split(',');
    final List<String> result = [];
    final buffer = StringBuffer();

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      final nextTrimmed = part.trim();
      if (buffer.isEmpty) {
        buffer.write(part);
      } else {
        final currentBuffer = buffer.toString().trim();
        final isNetwork = currentBuffer.startsWith('http://') ||
            currentBuffer.startsWith('https://') ||
            currentBuffer.startsWith('gs://');
        final isCompleteBase64 = currentBuffer.startsWith('data:image') &&
            currentBuffer.contains('base64,') &&
            currentBuffer.split('base64,').last.isNotEmpty;
        final isNewBoundary = nextTrimmed.startsWith('http://') ||
            nextTrimmed.startsWith('https://') ||
            nextTrimmed.startsWith('gs://') ||
            nextTrimmed.startsWith('data:image');

        if (isNetwork || isCompleteBase64 || isNewBoundary) {
          final finished = buffer.toString().trim();
          if (finished.isNotEmpty) {
            result.add(finished);
          }
          buffer.clear();
          buffer.write(part);
        } else {
          buffer.write(',');
          buffer.write(part);
        }
      }
    }

    final finished = buffer.toString().trim();
    if (finished.isNotEmpty) {
      result.add(finished);
    }

    return result
        .map((u) => u.trim())
        .where((u) =>
            u.startsWith('http://') ||
            u.startsWith('https://') ||
            u.startsWith('gs://') ||
            isBase64DataUrl(u))
        .toList();
  }

  /// Trích xuất URL ảnh chính (ảnh đầu tiên) từ chuỗi ảnh
  static String? resolvePrimaryUrl(String? raw) {
    final urls = parseImageUrls(raw);
    return urls.isNotEmpty ? urls.first : null;
  }

  /// Định dạng dung lượng byte thành chuỗi hiển thị dễ đọc (ví dụ: "18.4 KB")
  static String formatByteSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    return '${mb.toStringAsFixed(2)} MB';
  }
}
