import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../../application/auth/auth_providers.dart';
import '../../application/orders/orders_providers.dart';
import 'code_generator_helper.dart';

class OrderCodeResolver {
  /// Sinh mã hóa đơn mới nhất đảm bảo:
  /// 1. Luôn lấy từ mã hóa đơn mới nhất trong hệ thống + 1 (ví dụ: HD000001 -> HD000002).
  /// 2. Tuyệt đối không chứa ký tự cấm của Firebase (như dấu '.', '#', '$', '[', ']').
  /// 3. Truy vấn trực tiếp Firebase Realtime Database trên tất cả các chi nhánh để không bị sót đơn cũ.
  /// 4. Kiểm tra fetchById để bảo đảm tuyệt đối không trùng lặp.
  static Future<String> resolveNextOrderCode(
    dynamic ref, {
    String? storeId,
    String? currentOrderId,
  }) async {
    final existingCodes = <String>{};

    if (currentOrderId != null && currentOrderId.trim().isNotEmpty) {
      existingCodes.add(currentOrderId.trim());
    }

    // 1. (Đã bỏ) Không `ref.read` các provider đơn hàng theo khoảng ngày ở đây:
    // chúng là autoDispose, nếu màn hình chưa mở thì `read` sẽ tạo listener mới và
    // tải TOÀN BỘ đơn của tháng chỉ để lấy mã. Truy vấn RTDB bên dưới đã đủ chính xác.

    // 2. Truy vấn trực tiếp Firebase Realtime Database để lấy các mã đơn lớn nhất
    try {
      final db = ref.read(firebaseDatabaseProvider) as FirebaseDatabase;
      final availableStores =
          ref.read(availableStoresProvider).valueOrNull ?? <String, String>{};
      final targetStores = <String>{
        if (storeId != null && storeId.isNotEmpty) storeId,
        ...availableStores.keys,
        'store_001',
        'store_002',
      };

      for (final sId in targetStores) {
        if (sId.isEmpty || sId == 'all') continue;
        try {
          // Chỉ lấy vài đơn có mã lớn nhất trong dải khoá 'HD…' (thay vì 10 đơn
          // bất kỳ) — đủ để suy ra mã kế tiếp, giảm một nửa dữ liệu tải về mỗi lần bán.
          final snap = await db
              .ref('stores/$sId/orders')
              .orderByKey()
              .startAt('HD')
              .endAt('HD\uf8ff')
              .limitToLast(5)
              .get();
          if (snap.exists && snap.value is Map) {
            final map = snap.value as Map;
            for (final key in map.keys) {
              final kStr = key.toString().trim();
              if (kStr.isNotEmpty && !kStr.contains('.')) {
                existingCodes.add(kStr);
              }
            }
          }
        } catch (e) {
          debugPrint('Notice: Error querying latest orders for store $sId: $e');
        }
      }
    } catch (_) {}

    // 3. Tính mã tiếp theo: tìm số lớn nhất của tiền tố 'HD' và + 1
    var candidate =
        CodeGeneratorHelper.generateNextOrderCode(existingCodes.toList());

    // 4. Kiểm tra fetchById trên repository để bảo đảm tuyệt đối không trùng lặp
    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      while ((await orderRepo.fetchById(candidate)) != null) {
        existingCodes.add(candidate);
        candidate =
            CodeGeneratorHelper.generateNextOrderCode(existingCodes.toList());
      }
    } catch (_) {}

    return candidate;
  }

  /// Sinh mã hóa đơn mới theo số lần sửa (+ 1 cho mỗi lần sửa, dùng dấu '_'):
  /// Ví dụ: HD000001 -> HD000001_01 -> HD000001_02
  /// Đảm bảo không chứa dấu '.' tránh lỗi Firebase Realtime Database path.
  static Future<String> resolveVersionedOrderCode(
    dynamic ref, {
    required String originalOrderId,
    String? storeId,
  }) async {
    final existingCodes = <String>{};

    if (originalOrderId.trim().isNotEmpty) {
      existingCodes.add(originalOrderId.trim());
    }
    final (baseCode, _) =
        CodeGeneratorHelper.parseInvoiceCode(originalOrderId);

    // 1. (Đã bỏ) Không `ref.read` các provider đơn hàng theo khoảng ngày ở đây:
    // chúng là autoDispose, nếu màn hình chưa mở thì `read` sẽ tạo listener mới và
    // tải TOÀN BỘ đơn của tháng chỉ để lấy mã. Truy vấn RTDB bên dưới đã đủ chính xác.

    // 2. Truy vấn Firebase Realtime Database
    try {
      final db = ref.read(firebaseDatabaseProvider) as FirebaseDatabase;
      final availableStores =
          ref.read(availableStoresProvider).valueOrNull ?? <String, String>{};
      final targetStores = <String>{
        if (storeId != null && storeId.isNotEmpty) storeId,
        ...availableStores.keys,
        'store_001',
        'store_002',
      };

      for (final sId in targetStores) {
        if (sId.isEmpty || sId == 'all') continue;
        try {
          // Chỉ tải các phiên bản của đúng hoá đơn gốc (HD000123, HD000123_01, …)
          // thay vì 20 đơn mới nhất của chi nhánh.
          final snap = await db
              .ref('stores/$sId/orders')
              .orderByKey()
              .startAt(baseCode)
              .endAt('$baseCode\uf8ff')
              .get();
          if (snap.exists && snap.value is Map) {
            final map = snap.value as Map;
            for (final key in map.keys) {
              final kStr = key.toString().trim();
              if (kStr.isNotEmpty && !kStr.contains('.')) {
                existingCodes.add(kStr);
              }
            }
          }
        } catch (e) {
          debugPrint('Notice: Error querying latest orders for store $sId: $e');
        }
      }
    } catch (_) {}

    // 3. Tính mã phiên bản kế tiếp
    var candidate = CodeGeneratorHelper.generateVersionedInvoiceCode(
      originalOrderId,
      existingCodes: existingCodes.toList(),
    );

    // 4. Kiểm tra fetchById trên repository để bảo đảm tuyệt đối không trùng lặp
    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      while ((await orderRepo.fetchById(candidate)) != null) {
        existingCodes.add(candidate);
        candidate = CodeGeneratorHelper.generateVersionedInvoiceCode(
          originalOrderId,
          existingCodes: existingCodes.toList(),
        );
      }
    } catch (_) {}

    return candidate;
  }
}
