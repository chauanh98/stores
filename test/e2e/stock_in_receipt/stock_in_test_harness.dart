import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../../support/firebase_test_harness.dart';

// ============================================================================
// 1. DOMAIN STATUS EXTENSIONS & CANONICAL VALUES
// ============================================================================

extension StockInReceiptStatusExtension on StockInReceipt {
  bool get isDraft => status == 'draft' || status == 'Phiếu tạm';
  bool get isCancelled => status == 'cancelled' || status == 'Đã hủy';
  bool get isCompleted => !isDraft && !isCancelled;
}

/// Extra metadata wrapper for cancellation audit trail and payment details.
class StockInReceiptAuditRecord {
  final String receiptId;
  final String importCode;
  final String paymentMethod;
  final String? cancelReason;
  final DateTime? cancelledAt;
  final String? cancelledBy;

  const StockInReceiptAuditRecord({
    required this.receiptId,
    required this.importCode,
    this.paymentMethod = 'cash',
    this.cancelReason,
    this.cancelledAt,
    this.cancelledBy,
  });
}

// ============================================================================
// 2. STOCK-IN E2E TEST HARNESS (RTDB + REPOSITORIES + CONTRACTS)
// ============================================================================

class StockInE2ETestHarness {
  final MockFirebaseDatabase db = MockFirebaseDatabase();

  final Map<String, Product> products = {};
  final Map<String, Supplier> suppliers = {};
  final List<InventoryTransaction> recordedTransactions = [];
  final List<SupplierDebtTransaction> recordedDebtTransactions = [];
  final Map<String, StockInReceipt> receipts = {};
  final Map<String, StockInReceiptAuditRecord> receiptAudits = {};

  static const String storeDongThang = 'store_001';
  static const String storeThoiBinh = 'store_002';

  static const UserAccount adminUser = UserAccount(
    username: 'admin_test',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: storeDongThang,
  );

  static const UserAccount supervisorDongThang = UserAccount(
    username: 'sup_dongthang',
    displayName: 'Giám sát Đông Thắng',
    role: 'supervisor',
    storeId: storeDongThang,
  );

  static const UserAccount supervisorThoiBinh = UserAccount(
    username: 'sup_thoibinh',
    displayName: 'Giám sát Thới Bình',
    role: 'supervisor',
    storeId: storeThoiBinh,
  );

  static const UserAccount staffUser = UserAccount(
    username: 'staff_test',
    displayName: 'Nhân viên bán hàng',
    role: 'nhanvien',
    storeId: storeDongThang,
  );

  StockInE2ETestHarness() {
    seedInitialData();
  }

  void seedInitialData() {
    // 1. Canonical Products
    const pST25 = Product(
      id: 'PROD_ST25',
      name: 'Lúa giống ST25 chất lượng cao',
      code: 'ST25',
      barcode: '893600000001',
      price: 180000.0,
      costPrice: 120000.0,
      branchStocks: {
        'store_001': 10,
        'branch_1': 10,
        'store_002': 25,
        'branch_2': 25,
      },
      category: 'Lúa giống',
      unit: 'Bao 50kg',
    );

    const pST26 = Product(
      id: 'PROD_ST26',
      name: 'Gạo sạch hữu cơ ST26 đặc sản',
      code: 'ST26',
      barcode: '893600000002',
      price: 6800000.0,
      costPrice: 6100000.0,
      branchStocks: {
        'store_001': 1,
        'branch_1': 1,
        'store_002': 5,
        'branch_2': 5,
      },
      category: 'Gạo đặc sản',
      unit: 'Tấn',
    );

    const pFertNPK = Product(
      id: 'PROD_FERT_NPK',
      name: 'Phân bón NPK Đầu Trâu 20-20-15',
      code: 'NPK50',
      barcode: '893600000003',
      price: 950000.0,
      costPrice: 820000.0,
      branchStocks: {
        'store_001': 50,
        'branch_1': 50,
        'store_002': 100,
        'branch_2': 100,
      },
      category: 'Phân bón',
      unit: 'Bao',
    );

    const pPestRegent = Product(
      id: 'PROD_PEST_01',
      name: 'Thuốc trừ sâu Regent 800WG',
      code: 'REGENT',
      barcode: '893600000004',
      price: 45000.0,
      costPrice: 32000.0,
      branchStocks: {
        'store_001': 120,
        'branch_1': 120,
        'store_002': 200,
        'branch_2': 200,
      },
      category: 'Thuốc BVTV',
      unit: 'Gói',
    );

    products[pST25.id] = pST25;
    products[pST26.id] = pST26;
    products[pFertNPK.id] = pFertNPK;
    products[pPestRegent.id] = pPestRegent;

    // Seed into mock RTDB
    for (final p in products.values) {
      db.seedData('stores/$storeDongThang/products/${p.id}', {
        'name': p.name,
        'code': p.code,
        'price': p.price,
        'costPrice': p.costPrice,
        'branchStocks': p.branchStocks,
      });
      db.seedData('stores/$storeThoiBinh/products/${p.id}', {
        'name': p.name,
        'code': p.code,
        'price': p.price,
        'costPrice': p.costPrice,
        'branchStocks': p.branchStocks,
      });
    }

    // 2. Canonical Suppliers
    const supABC = Supplier(
      id: 'SUP_001',
      code: 'NCC_ABC',
      name: 'Công ty TNHH Phân Bón Ánh Dương',
      phone: '0901234567',
      address: '123 Quốc lộ 1A, Cần Thơ',
      totalPurchase: 50000000.0,
      currentDebt: 15000000.0,
      status: 'active',
    );

    const supMienNam = Supplier(
      id: 'SUP_002',
      code: 'NCC_MIENNAM',
      name: 'Công ty CP Giống Cây Trồng Miền Nam',
      phone: '0912345678',
      address: '456 Lê Lợi, TP.HCM',
      totalPurchase: 120000000.0,
      currentDebt: 30000000.0,
      status: 'active',
    );

    const supWalkIn = Supplier(
      id: 'SUP_WALK_IN',
      code: 'NCC_LE',
      name: 'Nhà cung cấp lẻ',
      phone: '',
      address: '',
      totalPurchase: 0.0,
      currentDebt: 0.0,
      status: 'active',
    );

    suppliers[supABC.id] = supABC;
    suppliers[supMienNam.id] = supMienNam;
    suppliers[supWalkIn.id] = supWalkIn;

    // Seed into mock RTDB
    for (final s in suppliers.values) {
      db.seedData('shared_suppliers/${s.id}', {
        'code': s.code,
        'name': s.name,
        'phone': s.phone,
        'totalPurchase': s.totalPurchase,
        'currentDebt': s.currentDebt,
      });
    }

    // 3. Historical Imports for Latest Price Lookup
    final txST26Historical = InventoryTransaction(
      id: 'TX_HIST_01',
      productId: 'PROD_ST26',
      type: TransactionType.import,
      quantity: 5,
      importPrice: 6100000.0,
      date: DateTime(2026, 9, 20, 10, 0),
      note: 'Nhập vụ mùa sớm',
      importCode: 'PN_HIST_001',
      storeId: storeDongThang,
      createdBy: 'admin_test',
    );

    // Notice: historical import is 115,000, while product.costPrice is 120,000.
    final txST25Historical = InventoryTransaction(
      id: 'TX_HIST_02',
      productId: 'PROD_ST25',
      type: TransactionType.import,
      quantity: 20,
      importPrice: 115000.0,
      date: DateTime(2026, 9, 22, 14, 30),
      note: 'Nhập giá ưu đãi',
      importCode: 'PN_HIST_002',
      storeId: storeDongThang,
      createdBy: 'admin_test',
    );

    recordedTransactions.add(txST26Historical);
    recordedTransactions.add(txST25Historical);

    db.seedData('stores/$storeDongThang/inventory_transactions/${txST26Historical.id}', {
      'productId': txST26Historical.productId,
      'type': 'import',
      'quantity': txST26Historical.quantity,
      'importPrice': txST26Historical.importPrice,
      'date': txST26Historical.date.toIso8601String(),
      'importCode': txST26Historical.importCode,
    });

    db.seedData('stores/$storeDongThang/inventory_transactions/${txST25Historical.id}', {
      'productId': txST25Historical.productId,
      'type': 'import',
      'quantity': txST25Historical.quantity,
      'importPrice': txST25Historical.importPrice,
      'date': txST25Historical.date.toIso8601String(),
      'importCode': txST25Historical.importCode,
    });
  }

  // --- USE CASE 1: Save Draft (Strict Invariant: 0 stock mutations, 0 debt mutations) ---
  Future<String> saveDraft(StockInReceipt receipt) async {
    final effectiveStoreId = receipt.storeId ?? storeDongThang;
    final draftReceipt = receipt.copyWith(
      status: 'draft',
      updatedAt: DateTime.now(),
      createdAt: receipt.createdAt ?? DateTime.now(),
    );

    receipts[draftReceipt.id] = draftReceipt;

    // Multi-path write only to stock_in_receipts node
    final rtdbMap = {
      'id': draftReceipt.id,
      'importCode': draftReceipt.importCode,
      'date': draftReceipt.date.toIso8601String(),
      'storeId': effectiveStoreId,
      'supplierId': draftReceipt.supplierId,
      'supplierName': draftReceipt.supplierName,
      'status': 'draft',
      'discount': draftReceipt.discount,
      'paidAmount': draftReceipt.paidAmount ?? 0.0,
      'debtAmount': draftReceipt.debtAmount ?? 0.0,
      'totalAmount': draftReceipt.totalAmount,
      'note': draftReceipt.note,
      'items': draftReceipt.items.map((i) => {
            'productId': i.productId,
            'productName': i.productName,
            'quantity': i.quantity,
            'unitPrice': i.unitPrice,
            'originalPrice': i.originalPrice,
            'discount': i.discount,
            'totalPrice': i.totalPrice,
            'note': i.note,
          }).toList(),
      'createdAt': draftReceipt.createdAt?.toIso8601String(),
      'updatedAt': draftReceipt.updatedAt?.toIso8601String(),
    };

    await db.ref('stores/$effectiveStoreId/stock_in_receipts/${draftReceipt.id}').set(rtdbMap);

    return draftReceipt.id;
  }

  // --- USE CASE 2: Complete Receipt (Atomic Multi-path Updates) ---
  Future<void> completeReceipt(
    StockInReceipt receipt, {
    String paymentMethod = 'cash',
    String? createdBy,
  }) async {
    final effectiveStoreId = receipt.storeId ?? storeDongThang;
    final Map<String, dynamic> updates = {};

    final completedReceipt = receipt.copyWith(
      status: 'completed',
      createdBy: createdBy ?? receipt.createdBy ?? 'admin_test',
      updatedAt: DateTime.now(),
      createdAt: receipt.createdAt ?? DateTime.now(),
    );
    receipts[completedReceipt.id] = completedReceipt;
    receiptAudits[completedReceipt.id] = StockInReceiptAuditRecord(
      receiptId: completedReceipt.id,
      importCode: completedReceipt.importCode,
      paymentMethod: paymentMethod,
    );

    // 1. Receipt document in RTDB
    updates['stores/$effectiveStoreId/stock_in_receipts/${completedReceipt.id}'] = {
      'id': completedReceipt.id,
      'importCode': completedReceipt.importCode,
      'date': completedReceipt.date.toIso8601String(),
      'storeId': effectiveStoreId,
      'supplierId': completedReceipt.supplierId,
      'supplierName': completedReceipt.supplierName,
      'status': 'completed',
      'discount': completedReceipt.discount,
      'paidAmount': completedReceipt.paidAmount,
      'debtAmount': completedReceipt.remainingDebt,
      'netPayable': completedReceipt.effectiveNetPayable,
      'paymentMethod': paymentMethod,
      'items': completedReceipt.items.map((i) => {
            'productId': i.productId,
            'productName': i.productName,
            'quantity': i.quantity,
            'unitPrice': i.unitPrice,
            'totalPrice': i.totalPrice,
          }).toList(),
    };

    // 2. Product Branch Stock increments & Alias synchronization
    for (final item in completedReceipt.items) {
      final p = products[item.productId];
      if (p != null) {
        final currentStock = p.stockInBranch(effectiveStoreId);
        final newStock = currentStock + item.quantity;
        final updatedStocks = Map<String, int>.from(p.branchStocks);
        updatedStocks[effectiveStoreId] = newStock;

        // Alias synchronization
        if (effectiveStoreId == 'store_001') {
          updatedStocks['branch_1'] = newStock;
        } else if (effectiveStoreId == 'store_002') {
          updatedStocks['branch_2'] = newStock;
        } else if (effectiveStoreId == 'branch_1') {
          updatedStocks['store_001'] = newStock;
        } else if (effectiveStoreId == 'branch_2') {
          updatedStocks['store_002'] = newStock;
        }

        // Weighted Average Cost calculation
        final totalOldUnits = currentStock > 0 ? currentStock : 0;
        final newCostPrice = totalOldUnits + item.quantity > 0
            ? ((totalOldUnits * p.costPrice) + (item.quantity * item.unitPrice)) /
                (totalOldUnits + item.quantity)
            : item.unitPrice;

        final updatedProduct = p.copyWith(
          branchStocks: updatedStocks,
          costPrice: newCostPrice,
        );
        products[p.id] = updatedProduct;

        updates['stores/$effectiveStoreId/products/${p.id}/branchStocks'] = updatedStocks;
        updates['stores/$effectiveStoreId/products/${p.id}/costPrice'] = newCostPrice;

        // Record Inventory Transaction
        final tx = InventoryTransaction(
          id: 'TX_IMP_${DateTime.now().millisecondsSinceEpoch}_${item.productId}',
          productId: item.productId,
          type: TransactionType.import,
          quantity: item.quantity,
          importPrice: item.unitPrice,
          date: completedReceipt.date,
          importCode: completedReceipt.importCode,
          storeId: effectiveStoreId,
          supplierId: completedReceipt.supplierId,
          supplierName: completedReceipt.supplierName,
          createdBy: completedReceipt.createdBy,
          note: completedReceipt.note,
        );
        recordedTransactions.add(tx);
        updates['stores/$effectiveStoreId/inventory_transactions/${tx.id}'] = {
          'productId': tx.productId,
          'type': 'import',
          'quantity': tx.quantity,
          'importPrice': tx.importPrice,
          'date': tx.date.toIso8601String(),
          'importCode': tx.importCode,
          'storeId': effectiveStoreId,
        };
      }
    }

    // 3. Supplier Debt & Total Purchase updates
    final supId = completedReceipt.supplierId;
    if (supId != null && supId.isNotEmpty && suppliers.containsKey(supId)) {
      final sup = suppliers[supId]!;
      final newTotalPurchase = sup.totalPurchase + completedReceipt.effectiveNetPayable;
      final newDebt = sup.currentDebt + completedReceipt.remainingDebt;

      final updatedSup = sup.copyWith(
        totalPurchase: newTotalPurchase,
        currentDebt: newDebt,
      );
      suppliers[supId] = updatedSup;

      updates['shared_suppliers/$supId/totalPurchase'] = newTotalPurchase;
      updates['shared_suppliers/$supId/currentDebt'] = newDebt;

      if (completedReceipt.remainingDebt > 0) {
        final debtTx = SupplierDebtTransaction(
          id: 'DTX_${DateTime.now().millisecondsSinceEpoch}',
          supplierId: supId,
          date: completedReceipt.date,
          type: SupplierDebtType.importBill,
          amount: completedReceipt.remainingDebt,
          remainingDebt: newDebt,
          referenceCode: completedReceipt.importCode,
          note: 'Nhập hàng hóa đơn ${completedReceipt.importCode}',
          createdBy: completedReceipt.createdBy ?? 'admin_test',
        );
        recordedDebtTransactions.add(debtTx);
        updates['shared_suppliers/$supId/debt_transactions/${debtTx.id}'] = {
          'amount': debtTx.amount,
          'type': 'import',
          'referenceCode': debtTx.referenceCode,
          'remainingDebt': debtTx.remainingDebt,
        };
      }
    }

    await db.ref().update(updates);
  }

  // --- USE CASE 3: Cancel Receipt (Atomic Multi-path Rollback) ---
  Future<void> cancelReceipt({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {
    assert(reason.trim().isNotEmpty, 'Cancellation reason must be provided');

    // Idempotency check: ignore duplicate cancel calls
    if (receipt.isCancelled) return;

    final Map<String, dynamic> updates = {};
    final cancelledReceipt = receipt.copyWith(
      status: 'cancelled',
      updatedAt: DateTime.now(),
    );
    receipts[cancelledReceipt.id] = cancelledReceipt;
    receiptAudits[cancelledReceipt.id] = StockInReceiptAuditRecord(
      receiptId: cancelledReceipt.id,
      importCode: cancelledReceipt.importCode,
      cancelReason: reason,
      cancelledAt: DateTime.now(),
      cancelledBy: cancelledBy,
    );

    // 1. Update receipt status & cancellation audit fields
    updates['stores/$storeId/stock_in_receipts/${receipt.id}/status'] = 'cancelled';
    updates['stores/$storeId/stock_in_receipts/${receipt.id}/cancelReason'] = reason;
    updates['stores/$storeId/stock_in_receipts/${receipt.id}/cancelledAt'] = DateTime.now().toIso8601String();
    updates['stores/$storeId/stock_in_receipts/${receipt.id}/cancelledBy'] = cancelledBy;

    // 2. Rollback Product Stock
    for (final item in receipt.items) {
      final p = products[item.productId];
      if (p != null) {
        final currentStock = p.stockInBranch(storeId);
        // Note: clamped >= 0, or negative if items already sold
        final rolledBackStock = (currentStock - item.quantity);
        final clampedStock = rolledBackStock < 0 ? rolledBackStock : rolledBackStock;
        final updatedStocks = Map<String, int>.from(p.branchStocks);
        updatedStocks[storeId] = clampedStock;

        // Alias synchronization
        if (storeId == 'store_001') {
          updatedStocks['branch_1'] = clampedStock;
        } else if (storeId == 'store_002') {
          updatedStocks['branch_2'] = clampedStock;
        } else if (storeId == 'branch_1') {
          updatedStocks['store_001'] = clampedStock;
        } else if (storeId == 'branch_2') {
          updatedStocks['store_002'] = clampedStock;
        }

        final updatedProduct = p.copyWith(branchStocks: updatedStocks);
        products[p.id] = updatedProduct;

        updates['stores/$storeId/products/${p.id}/branchStocks'] = updatedStocks;

        // Reversal Inventory Transaction
        final revTx = InventoryTransaction(
          id: 'TX_REV_${DateTime.now().millisecondsSinceEpoch}_${item.productId}',
          productId: item.productId,
          type: TransactionType.export,
          quantity: item.quantity,
          date: DateTime.now(),
          note: 'Hủy phiếu nhập ${receipt.importCode}: $reason',
          importCode: receipt.importCode,
          storeId: storeId,
          createdBy: cancelledBy,
        );
        recordedTransactions.add(revTx);
        updates['stores/$storeId/inventory_transactions/${revTx.id}'] = {
          'productId': revTx.productId,
          'type': 'export',
          'quantity': revTx.quantity,
          'note': revTx.note,
          'importCode': revTx.importCode,
        };
      }
    }

    // 3. Rollback Supplier Debt & Total Purchase
    final supId = receipt.supplierId;
    if (supId != null && supId.isNotEmpty && suppliers.containsKey(supId)) {
      final sup = suppliers[supId]!;
      final newTotalPurchase = (sup.totalPurchase - receipt.effectiveNetPayable).clamp(0.0, double.infinity);
      final newDebt = (sup.currentDebt - receipt.remainingDebt).clamp(0.0, double.infinity);

      final updatedSup = sup.copyWith(
        totalPurchase: newTotalPurchase,
        currentDebt: newDebt,
      );
      suppliers[supId] = updatedSup;

      updates['shared_suppliers/$supId/totalPurchase'] = newTotalPurchase;
      updates['shared_suppliers/$supId/currentDebt'] = newDebt;

      final reversalDebtTx = SupplierDebtTransaction(
        id: 'DTX_REV_${DateTime.now().millisecondsSinceEpoch}',
        supplierId: supId,
        date: DateTime.now(),
        type: SupplierDebtType.adjustment,
        amount: -receipt.remainingDebt,
        remainingDebt: newDebt,
        referenceCode: receipt.importCode,
        note: 'Hủy phiếu nhập ${receipt.importCode}: $reason',
        createdBy: cancelledBy,
      );
      recordedDebtTransactions.add(reversalDebtTx);
      updates['shared_suppliers/$supId/debt_transactions/${reversalDebtTx.id}'] = {
        'amount': reversalDebtTx.amount,
        'type': 'adjustment',
        'remainingDebt': reversalDebtTx.remainingDebt,
        'referenceCode': reversalDebtTx.referenceCode,
      };
    }

    await db.ref().update(updates);
  }

  // --- USE CASE 4: Delete Draft ---
  Future<void> deleteDraft({required String storeId, required String receiptId}) async {
    receipts.remove(receiptId);
    await db.ref('stores/$storeId/stock_in_receipts/$receiptId').remove();
  }

  // --- USE CASE 5: Query Latest Import Cost Price ---
  Future<double?> getLatestImportPrice({required String storeId, required String productId}) async {
    // 1. Query recordedTransactions for latest import
    final matchingTxs = recordedTransactions
        .where((t) => t.type == TransactionType.import && t.productId == productId && t.importPrice != null && t.importPrice! > 0)
        .toList();

    if (matchingTxs.isNotEmpty) {
      matchingTxs.sort((a, b) => b.date.compareTo(a.date));
      return matchingTxs.first.importPrice;
    }

    // 2. Fallback to product.costPrice
    final p = products[productId];
    return p?.costPrice ?? 0.0;
  }

  // --- USE CASE 6: 3-State Filter ---
  List<StockInReceipt> filterReceipts({
    required List<StockInReceipt> receiptsList,
    required String statusFilter,
  }) {
    if (statusFilter == 'all' || statusFilter == 'Tất cả') {
      return receiptsList;
    }
    if (statusFilter == 'completed' || statusFilter == 'Đã hoàn thành') {
      return receiptsList.where((r) => r.isCompleted).toList();
    }
    if (statusFilter == 'draft' || statusFilter == 'Phiếu tạm') {
      return receiptsList.where((r) => r.isDraft).toList();
    }
    if (statusFilter == 'cancelled' || statusFilter == 'Đã hủy') {
      return receiptsList.where((r) => r.isCancelled).toList();
    }
    return receiptsList;
  }
}

// ============================================================================
// 3. FAKE REPOSITORIES & NOTIFIERS FOR RIVERPOD INJECTION
// ============================================================================

class FakeAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  FakeAuthNotifier([UserAccount? user]) : super(user ?? StockInE2ETestHarness.adminUser);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }

  void setUser(UserAccount user) {
    state = user;
  }
}

class FakeSupplierListNotifier extends StateNotifier<AsyncValue<List<Supplier>>> {
  final List<Supplier> _suppliers;
  FakeSupplierListNotifier(this._suppliers) : super(AsyncValue.data(_suppliers));

  Future<void> recordImportDebt({
    required String supplierId,
    required double totalAmount,
    required double paidAmount,
    required String invoiceCode,
  }) async {
    final debt = totalAmount - paidAmount;
    final idx = _suppliers.indexWhere((s) => s.id == supplierId);
    if (idx >= 0) {
      final cur = _suppliers[idx];
      _suppliers[idx] = cur.copyWith(
        currentDebt: cur.currentDebt + debt,
        totalPurchase: cur.totalPurchase + totalAmount,
      );
      state = AsyncValue.data(List.from(_suppliers));
    }
  }
}

// ============================================================================
// 4. WIDGET TEST APPLICATION BUILDER
// ============================================================================

Widget buildStockInTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => FakeAuthNotifier()),
      currentStoreIdProvider.overrideWith((ref) => 'store_001'),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': 'Chi nhánh Đông Thắng',
            'store_002': 'Chi nhánh Thới Bình',
          }),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Scaffold(body: child),
    ),
  );
}

// ============================================================================
// 5. REQUIREMENT-DRIVEN UI CONTRACT WIDGETS (R1, R2, R3, R4)
// ============================================================================

/// R1 Item Card: thumbnail, name, SKU, stock ("Tồn kho: X"), unit price, stepper [-][qty][+], line total.
/// Swipe action exposes delete confirmation dialog ("Xóa hàng hóa này?").
class VisualStockInItemCard extends StatelessWidget {
  final StockInReceiptItem item;
  final int currentStock;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onDelete;

  const VisualStockInItemCard({
    super.key,
    required this.item,
    required this.currentStock,
    required this.onQuantityChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Dismissible(
      key: Key('dismissible_${item.productId}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            key: const Key('delete_confirmation_dialog'),
            title: const Text('Xác nhận xóa'),
            content: const Text('Xóa hàng hóa này khỏi phiếu nhập?'),
            actions: [
              TextButton(
                key: const Key('btn_cancel_delete'),
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                key: const Key('btn_confirm_delete'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Xóa'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        key: Key('item_card_${item.productId}'),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Thumbnail
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.inventory_2_outlined, color: Colors.blueGrey),
              ),
              const SizedBox(width: 12),

              // 2. Info: Name, SKU, Stock, Unit Price
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Mã: ${item.productCode} • Tồn kho: $currentStock',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Đơn giá: ${currencyFormat.format(item.unitPrice)} đ',
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ],
                ),
              ),

              // 3. Stepper & Line Total
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${currencyFormat.format(item.totalPrice)} đ',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: Key('stepper_dec_${item.productId}'),
                          icon: const Icon(Icons.remove, size: 16),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          padding: EdgeInsets.zero,
                          onPressed: item.quantity > 1
                              ? () => onQuantityChanged(item.quantity - 1)
                              : () {
                                  // Prompt delete confirmation when reaching 0
                                  showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      key: const Key('delete_confirmation_dialog'),
                                      title: const Text('Xác nhận xóa'),
                                      content: const Text('Xóa hàng hóa này khỏi phiếu nhập?'),
                                      actions: [
                                        TextButton(
                                          key: const Key('btn_cancel_delete'),
                                          onPressed: () => Navigator.of(ctx).pop(false),
                                          child: const Text('Hủy'),
                                        ),
                                        ElevatedButton(
                                          key: const Key('btn_confirm_delete'),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                          onPressed: () {
                                            Navigator.of(ctx).pop(true);
                                            onDelete();
                                          },
                                          child: const Text('Xóa'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                        ),
                        Text(
                          '${item.quantity}',
                          key: Key('stepper_qty_${item.productId}'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        IconButton(
                          key: Key('stepper_inc_${item.productId}'),
                          icon: const Icon(Icons.add, size: 16),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          padding: EdgeInsets.zero,
                          onPressed: () => onQuantityChanged(item.quantity + 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// R1 Sticky Bottom Summary Bar: "Tổng tiền hàng", "X mặt hàng • Số lượng: Y", "Lưu tạm", "Tiếp tục".
class StickyBottomSummaryBar extends StatelessWidget {
  final double totalAmount;
  final int itemCount;
  final int totalQuantity;
  final VoidCallback onSaveDraft;
  final VoidCallback onContinue;
  final bool isEnabled;

  const StickyBottomSummaryBar({
    super.key,
    required this.totalAmount,
    required this.itemCount,
    required this.totalQuantity,
    required this.onSaveDraft,
    required this.onContinue,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Container(
      key: const Key('sticky_bottom_summary_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tổng tiền hàng', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      '${currencyFormat.format(totalAmount)} đ',
                      key: const Key('bottom_bar_total_amount'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue),
                    ),
                  ],
                ),
                Text(
                  '$itemCount mặt hàng • Số lượng: $totalQuantity',
                  key: const Key('bottom_bar_item_count'),
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('btn_save_draft'),
                    onPressed: isEnabled ? onSaveDraft : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Colors.blue),
                    ),
                    child: const Text('Lưu tạm', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('btn_continue'),
                    onPressed: isEnabled ? onContinue : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Tiếp tục', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// R2 Product Edit Modal Bottom Sheet: `< SKU`, thumbnail, "Tồn: X", quantity, latest cost price, discount, subtotal, numpad, "Xong".
class StockInProductEditSheet extends StatefulWidget {
  final Product product;
  final int branchStock;
  final double preFilledPrice;
  final Function(int qty, double unitPrice, double discount, String note) onDone;

  const StockInProductEditSheet({
    super.key,
    required this.product,
    required this.branchStock,
    required this.preFilledPrice,
    required this.onDone,
  });

  @override
  State<StockInProductEditSheet> createState() => _StockInProductEditSheetState();
}

class _StockInProductEditSheetState extends State<StockInProductEditSheet> {
  late int _quantity;
  late double _originalPrice;
  double _discount = 0.0;
  String _note = '';

  @override
  void initState() {
    super.initState();
    _quantity = 1;
    _originalPrice = widget.preFilledPrice;
  }

  double get netUnitPrice => (_originalPrice - _discount).clamp(0.0, double.infinity);
  double get lineTotal => netUnitPrice * _quantity;

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Container(
      key: const Key('product_edit_sheet'),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: < SKU
          Row(
            children: [
              IconButton(
                key: const Key('btn_sheet_back'),
                icon: const Icon(Icons.arrow_back_ios, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Text(
                '< ${widget.product.code}',
                key: const Key('sheet_header_sku'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Tồn: ${widget.branchStock}',
                  key: const Key('sheet_stock_badge'),
                  style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Product Details
          Text(widget.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 16),

          // Stepper for Quantity
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Số lượng nhập', style: TextStyle(fontWeight: FontWeight.w500)),
              Row(
                children: [
                  IconButton(
                    key: const Key('sheet_stepper_dec'),
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.blue),
                    onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  ),
                  Text(
                    '$_quantity',
                    key: const Key('sheet_qty_text'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    key: const Key('sheet_stepper_inc'),
                    icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                    onPressed: () => setState(() => _quantity++),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Unit Price & Discount
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Đơn giá', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    TextFormField(
                      key: const Key('sheet_input_price'),
                      initialValue: currencyFormat.format(_originalPrice),
                      keyboardType: TextInputType.number,
                      onChanged: (val) {
                        final parsed = double.tryParse(val.replaceAll('.', '').replaceAll(',', '')) ?? 0.0;
                        setState(() => _originalPrice = parsed);
                      },
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Giảm giá', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    TextFormField(
                      key: const Key('sheet_input_discount'),
                      initialValue: '0',
                      keyboardType: TextInputType.number,
                      onChanged: (val) {
                        final parsed = double.tryParse(val.replaceAll('.', '').replaceAll(',', '')) ?? 0.0;
                        setState(() => _discount = parsed);
                      },
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Real-time calculated Giá nhập & Thành tiền
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Giá nhập (Đơn giá - Giảm)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      '${currencyFormat.format(netUnitPrice)} đ',
                      key: const Key('sheet_calculated_net_price'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Thành tiền', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      '${currencyFormat.format(lineTotal)} đ',
                      key: const Key('sheet_calculated_total'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Note Field
          TextFormField(
            key: const Key('sheet_input_note'),
            decoration: const InputDecoration(
              labelText: 'Thêm ghi chú hàng hóa',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (val) => _note = val,
          ),
          const SizedBox(height: 16),

          // Done Button
          ElevatedButton(
            key: const Key('btn_sheet_done'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () {
              widget.onDone(_quantity, netUnitPrice, _discount, _note);
              Navigator.of(context).pop();
            },
            child: const Text('Xong', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// R3 PopScope Exit Dialog: 3 choices ("Lưu tạm", "Rời khỏi", "Ở lại")
class ExitReceiptDialog extends StatelessWidget {
  final VoidCallback onSaveDraft;
  final VoidCallback onExitDiscard;
  final VoidCallback onStay;

  const ExitReceiptDialog({
    super.key,
    required this.onSaveDraft,
    required this.onExitDiscard,
    required this.onStay,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('exit_receipt_dialog'),
      title: const Text('Xác nhận thoát'),
      content: const Text(
        'Phiếu nhập kho chưa được hoàn thành. Bạn có muốn lưu tạm để tiếp tục sau không?',
      ),
      actions: [
        TextButton(
          key: const Key('dialog_choice_stay'),
          onPressed: onStay,
          child: const Text('Ở lại'),
        ),
        TextButton(
          key: const Key('dialog_choice_exit'),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: onExitDiscard,
          child: const Text('Rời khỏi'),
        ),
        ElevatedButton(
          key: const Key('dialog_choice_draft'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          onPressed: onSaveDraft,
          child: const Text('Lưu tạm', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

/// R4 Cancel Receipt Dialog with mandatory reason field for Admin/Supervisor
class CancelReceiptDialog extends StatefulWidget {
  final Function(String reason) onConfirmCancel;

  const CancelReceiptDialog({
    super.key,
    required this.onConfirmCancel,
  });

  @override
  State<CancelReceiptDialog> createState() => _CancelReceiptDialogState();
}

class _CancelReceiptDialogState extends State<CancelReceiptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('cancel_receipt_dialog'),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('Hủy phiếu nhập kho'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hành động này sẽ hoàn trả tồn kho và công nợ nhà cung cấp liên quan. Vui lòng nhập lý do hủy:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('cancel_reason_input'),
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Lý do hủy (bắt buộc)',
                border: OutlineInputBorder(),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Vui lòng nhập lý do hủy phiếu';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('btn_cancel_dialog_close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
        ElevatedButton(
          key: const Key('btn_confirm_cancel'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            if (_formKey.currentState?.validate() == true) {
              widget.onConfirmCancel(_reasonController.text.trim());
              Navigator.of(context).pop();
            }
          },
          child: const Text('Xác nhận hủy', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

/// R2 Accounting Numpad: 4-column touch keypad (1-9, ., 0, 000, ⌫, Nhập)
class AccountingNumpadWidget extends StatelessWidget {
  final ValueChanged<String> onKeyPress;
  final VoidCallback onEnter;

  const AccountingNumpadWidget({
    super.key,
    required this.onKeyPress,
    required this.onEnter,
  });

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['1', '2', '3', 'backspace'],
      ['4', '5', '6', 'clear'],
      ['7', '8', '9', '000'],
      ['.', '0', '00', 'enter'],
    ];

    return Container(
      key: const Key('accounting_numpad'),
      padding: const EdgeInsets.all(8),
      color: Colors.grey.shade100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: keys.map((row) {
          return Row(
            children: row.map((k) {
              Widget content;
              Key buttonKey;
              if (k == 'backspace') {
                buttonKey = const Key('numpad_backspace');
                content = const Icon(Icons.backspace_outlined, size: 20);
              } else if (k == 'enter') {
                buttonKey = const Key('numpad_enter');
                content = const Text('Nhập', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue));
              } else {
                buttonKey = Key('numpad_$k');
                content = Text(k, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600));
              }

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Material(
                    color: k == 'enter' ? Colors.blue.shade50 : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    elevation: 1,
                    child: InkWell(
                      key: buttonKey,
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        if (k == 'enter') {
                          onEnter();
                        } else {
                          onKeyPress(k);
                        }
                      },
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        child: content,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

/// R1 Step 2: Payment & Supplier Confirmation View
class StockInPaymentConfirmationView extends StatefulWidget {
  final StockInReceipt receipt;
  final List<Supplier> suppliers;
  final Function({
    required String? supplierId,
    required double discount,
    required double paidAmount,
    required String paymentMethod,
    required String note,
  }) onComplete;
  final VoidCallback onSaveDraft;
  final VoidCallback onViewItems;

  const StockInPaymentConfirmationView({
    super.key,
    required this.receipt,
    required this.suppliers,
    required this.onComplete,
    required this.onSaveDraft,
    required this.onViewItems,
  });

  @override
  State<StockInPaymentConfirmationView> createState() =>
      _StockInPaymentConfirmationViewState();
}

class _StockInPaymentConfirmationViewState
    extends State<StockInPaymentConfirmationView> {
  String? _selectedSupplierId;
  late double _discount;
  late double _paidAmount;
  String _paymentMethod = 'cash'; // 'cash', 'transfer', 'card'
  late TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _selectedSupplierId = widget.receipt.supplierId;
    _discount = widget.receipt.discount;
    _paidAmount = widget.receipt.paidAmount ?? widget.receipt.totalAmount;
    _noteController = TextEditingController(text: widget.receipt.note);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  double get netPayable => (widget.receipt.totalAmount - _discount).clamp(0.0, double.infinity);
  double get remainingDebt => (netPayable - _paidAmount).clamp(0.0, double.infinity);

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thanh toán & Nhà cung cấp'),
        actions: [
          TextButton(
            key: const Key('btn_payment_save_draft'),
            onPressed: widget.onSaveDraft,
            child: const Text('Lưu tạm', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Link to view items
            ListTile(
              key: const Key('btn_view_receipt_items'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt_outlined, color: Colors.blue),
              title: Text(
                'Xem hàng trong phiếu (${widget.receipt.itemCount} mặt hàng)',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onViewItems,
            ),
            const Divider(),

            // Supplier Selection
            const Text('Nhà cung cấp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('dropdown_supplier'),
              value: _selectedSupplierId,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              hint: const Text('Chọn nhà cung cấp'),
              items: widget.suppliers.map((s) {
                return DropdownMenuItem<String>(
                  value: s.id,
                  child: Text(
                    '${s.name} (${s.code})',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedSupplierId = val),
            ),
            const SizedBox(height: 16),

            // Financial Summary Card
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tổng tiền hàng:'),
                        Text(
                          '${currencyFormat.format(widget.receipt.totalAmount)} đ',
                          key: const Key('text_total_goods_amount'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Giảm giá phiếu:'),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            key: const Key('input_receipt_discount'),
                            initialValue: _discount > 0 ? currencyFormat.format(_discount) : '0',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            onChanged: (val) {
                              final parsed = double.tryParse(val.replaceAll('.', '').replaceAll(',', '')) ?? 0.0;
                              setState(() => _discount = parsed);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cần trả NCC:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          '${currencyFormat.format(netPayable)} đ',
                          key: const Key('text_net_payable'),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        const Text('Tiền trả NCC:'),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            key: const Key('input_paid_amount'),
                            initialValue: currencyFormat.format(_paidAmount),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            onChanged: (val) {
                              final parsed = double.tryParse(val.replaceAll('.', '').replaceAll(',', '')) ?? 0.0;
                              setState(() => _paidAmount = parsed);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tính vào công nợ:', style: TextStyle(color: Colors.red)),
                        Text(
                          '${currencyFormat.format(remainingDebt)} đ',
                          key: const Key('text_remaining_debt'),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 15),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Payment Method
            const Text('Phương thức thanh toán', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  key: const Key('payment_cash'),
                  label: const Text('Tiền mặt'),
                  selected: _paymentMethod == 'cash',
                  onSelected: (sel) {
                    if (sel) setState(() => _paymentMethod = 'cash');
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  key: const Key('payment_transfer'),
                  label: const Text('Chuyển khoản'),
                  selected: _paymentMethod == 'transfer',
                  onSelected: (sel) {
                    if (sel) setState(() => _paymentMethod = 'transfer');
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  key: const Key('payment_card'),
                  label: const Text('Thẻ'),
                  selected: _paymentMethod == 'card',
                  onSelected: (sel) {
                    if (sel) setState(() => _paymentMethod = 'card');
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Note
            TextFormField(
              key: const Key('input_receipt_note'),
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Ghi chú phiếu nhập',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            // Complete Button
            ElevatedButton(
              key: const Key('btn_payment_complete'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                // Invariant: If debt is incurred, supplier is required
                if (remainingDebt > 0 && (_selectedSupplierId == null || _selectedSupplierId!.isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      key: Key('snackbar_supplier_required'),
                      content: Text('Vui lòng chọn Nhà Cung Cấp để ghi nợ'),
                    ),
                  );
                  return;
                }

                widget.onComplete(
                  supplierId: _selectedSupplierId,
                  discount: _discount,
                  paidAmount: _paidAmount,
                  paymentMethod: _paymentMethod,
                  note: _noteController.text.trim(),
                );
              },
              child: const Text('Hoàn thành', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

/// R3 Distinct Status Badges on Stock-In Receipts
class StockInReceiptStatusBadge extends StatelessWidget {
  final String status;

  const StockInReceiptStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    Key badgeKey;

    final norm = status.toLowerCase().trim();
    if (norm == 'draft' || norm == 'phiếu tạm') {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFB45309);
      label = 'Phiếu tạm';
      badgeKey = const Key('badge_draft');
    } else if (norm == 'cancelled' || norm == 'đã hủy') {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFFB91C1C);
      label = 'Đã hủy';
      badgeKey = const Key('badge_cancelled');
    } else {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF15803D);
      label = 'Đã hoàn thành';
      badgeKey = const Key('badge_completed');
    }

    return Container(
      key: badgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

/// R3 3-State Filter Bar: "Tất cả", "Đã hoàn thành", "Phiếu tạm", "Đã hủy"
class StockInReceiptsFilterBar extends StatelessWidget {
  final String selectedStatus;
  final ValueChanged<String> onStatusChanged;

  const StockInReceiptsFilterBar({
    super.key,
    required this.selectedStatus,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    const filters = [
      {'key': 'all', 'label': 'Tất cả', 'widgetKey': 'filter_all'},
      {'key': 'completed', 'label': 'Đã hoàn thành', 'widgetKey': 'filter_completed'},
      {'key': 'draft', 'label': 'Phiếu tạm', 'widgetKey': 'filter_draft'},
      {'key': 'cancelled', 'label': 'Đã hủy', 'widgetKey': 'filter_cancelled'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: filters.map((f) {
          final isSelected = selectedStatus == f['key'] || selectedStatus == f['label'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              key: Key(f['widgetKey']!),
              label: Text(f['label']!),
              selected: isSelected,
              onSelected: (_) => onStatusChanged(f['key']!),
            ),
          );
        }).toList(),
      ),
    );
  }
}

