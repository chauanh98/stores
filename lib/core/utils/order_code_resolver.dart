import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../../application/auth/auth_providers.dart';
import '../../application/orders/orders_providers.dart';
import '../../application/reports/overview_providers.dart';
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

    // 1. Lấy mã từ cache / bộ nhớ trong các provider đã nạp
    try {
      final thisMonth = ref
          .read(allBranchesOrdersByDateRangeProvider(
              OverviewTimeRange.thisMonth.getRange()))
          .valueOrNull;
      if (thisMonth is List) {
        for (final o in thisMonth) {
          existingCodes.add(o.id.toString());
        }
      }
    } catch (_) {}

    try {
      final activeRange = ref.read(invoicesActiveDateRangeProvider);
      final activeOrders = ref
          .read(allBranchesOrdersByDateRangeProvider(activeRange))
          .valueOrNull;
      if (activeOrders is List) {
        for (final o in activeOrders) {
          existingCodes.add(o.id.toString());
        }
      }
    } catch (_) {}

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
          final snap = await db
              .ref('stores/$sId/orders')
              .orderByKey()
              .limitToLast(10)
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

    // 1. Lấy mã từ cache / bộ nhớ trong các provider đã nạp
    try {
      final thisMonth = ref
          .read(allBranchesOrdersByDateRangeProvider(
              OverviewTimeRange.thisMonth.getRange()))
          .valueOrNull;
      if (thisMonth is List) {
        for (final o in thisMonth) {
          existingCodes.add(o.id.toString());
        }
      }
    } catch (_) {}

    try {
      final activeRange = ref.read(invoicesActiveDateRangeProvider);
      final activeOrders = ref
          .read(allBranchesOrdersByDateRangeProvider(activeRange))
          .valueOrNull;
      if (activeOrders is List) {
        for (final o in activeOrders) {
          existingCodes.add(o.id.toString());
        }
      }
    } catch (_) {}

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
          final snap = await db
              .ref('stores/$sId/orders')
              .orderByKey()
              .limitToLast(20)
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
