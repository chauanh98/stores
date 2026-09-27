import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_receipt_card.dart';

void main() {
  group('Adversarial Verification Suite: Stock-in Receipts', () {
    // -------------------------------------------------------------------------
    // 1. Edge Cases in Grouping Algorithm
    // -------------------------------------------------------------------------
    group('1. Edge Cases in groupTransactionsToReceipts', () {
      test('Empty transaction list returns empty const list', () {
        final result =
            groupTransactionsToReceipts(transactions: <InventoryTransaction>[]);
        expect(result, isEmpty);
      });

      test(
          'Non-import transactions (export, audit, waste) are strictly ignored',
          () {
        final transactions = <InventoryTransaction>[
          InventoryTransaction(
            id: 'tx_export_1',
            productId: 'prod_001',
            type: TransactionType.export,
            quantity: 5,
            importPrice: 100000,
            date: DateTime(2026, 9, 21, 8, 0),
            note: 'Export',
            importCode: 'PN_FAKE_EXPORT',
          ),
          InventoryTransaction(
            id: 'tx_audit_1',
            productId: 'prod_002',
            type: TransactionType.inventoryAudit,
            quantity: 10,
            importPrice: 200000,
            date: DateTime(2026, 9, 21, 8, 30),
            note: 'Audit balance',
            importCode: 'PN_FAKE_AUDIT',
          ),
          InventoryTransaction(
            id: 'tx_waste_1',
            productId: 'prod_003',
            type: TransactionType.inventoryAudit,
            quantity: 2,
            importPrice: 50000,
            date: DateTime(2026, 9, 21, 9, 0),
            note: 'Discrepancy adjustment',
            importCode: 'PN_FAKE_WASTE',
          ),
        ];

        final receipts =
            groupTransactionsToReceipts(transactions: transactions);
        expect(receipts, isEmpty,
            reason: 'Non-import transactions must never generate receipts');
      });

      test(
          'Mixed list with 100 non-import and 3 import transactions isolates imports only',
          () {
        final List<InventoryTransaction> transactions = [];
        final baseDate = DateTime(2026, 9, 21, 10, 0);

        // 100 export / audit transactions
        for (int i = 0; i < 100; i++) {
          transactions.add(InventoryTransaction(
            id: 'tx_noise_$i',
            productId: 'prod_noise_$i',
            type: i.isEven
                ? TransactionType.export
                : TransactionType.inventoryAudit,
            quantity: i + 1,
            importPrice: 10000.0 * (i + 1),
            date: baseDate.add(Duration(minutes: i)),
            note: 'Noise transaction $i',
            importCode: 'PN_NOISE_$i',
          ));
        }

        // 3 legitimate import transactions sharing the same importCode
        transactions.addAll([
          InventoryTransaction(
            id: 'tx_import_1',
            productId: 'prod_valid_1',
            type: TransactionType.import,
            quantity: 4,
            importPrice: 250000,
            date: baseDate.add(const Duration(hours: 2)),
            note: 'Import - Valid 1',
            importCode: 'PN_LEGIT_001',
            supplierId: 'NCC_LEGIT',
            supplierName: 'Nội Thất Tân Cổ Điển',
          ),
          InventoryTransaction(
            id: 'tx_import_2',
            productId: 'prod_valid_2',
            type: TransactionType.import,
            quantity: 6,
            importPrice: 150000,
            date: baseDate.add(const Duration(hours: 2, minutes: 1)),
            note: 'Import - Valid 2',
            importCode: 'PN_LEGIT_001',
            supplierId: 'NCC_LEGIT',
            supplierName: 'Nội Thất Tân Cổ Điển',
          ),
          InventoryTransaction(
            id: 'tx_import_3',
            productId: 'prod_valid_3',
            type: TransactionType.import,
            quantity: 10,
            importPrice: 80000,
            date: baseDate.add(const Duration(hours: 2, minutes: 2)),
            note: 'Import - Valid 3',
            importCode: 'PN_LEGIT_001',
            supplierId: 'NCC_LEGIT',
            supplierName: 'Nội Thất Tân Cổ Điển',
          ),
        ]);

        final receipts =
            groupTransactionsToReceipts(transactions: transactions);

        expect(receipts.length, 1);
        final r = receipts.first;
        expect(r.importCode, 'PN_LEGIT_001');
        expect(r.itemCount, 3);
        // Quantities: 4 + 6 + 10 = 20
        expect(r.totalQuantity, 20);
        // Total: (4 * 250,000) + (6 * 150,000) + (10 * 80,000) = 1,000,000 + 900,000 + 800,000 = 2,700,000
        expect(r.totalAmount, 2700000.0);
        expect(r.items.map((it) => it.productId),
            ['prod_valid_1', 'prod_valid_2', 'prod_valid_3']);
      });

      test(
          'Missing product in catalog falls back gracefully to note and productId',
          () {
        final now = DateTime(2026, 9, 21, 11, 0);
        final transactions = <InventoryTransaction>[
          InventoryTransaction(
            id: 'tx_note_fallback',
            productId: 'PROD_GHOST_1',
            type: TransactionType.import,
            quantity: 2,
            importPrice: 1200000,
            date: now,
            note: 'Import - Sofa Giường Nỉ Thông Minh',
            importCode: 'PN_NOTE_01',
          ),
          InventoryTransaction(
            id: 'tx_no_note_fallback',
            productId: 'PROD_GHOST_2',
            type: TransactionType.import,
            quantity: 5,
            importPrice: 300000,
            date: now,
            note: 'Không theo format chuẩn',
            importCode: 'PN_NOTE_02',
          ),
          InventoryTransaction(
            id: 'tx_empty_note_fallback',
            productId: 'PROD_GHOST_3',
            type: TransactionType.import,
            quantity: 1,
            importPrice: null,
            // missing import price as well
            date: now,
            note: '',
            importCode: 'PN_NOTE_03',
          ),
        ];

        final receipts = groupTransactionsToReceipts(
          transactions: transactions,
          products: [], // Empty catalog
        );

        expect(receipts.length, 3);

        // 1. Fallback from "Import - [Name]" note
        final r1 = receipts.firstWhere((r) => r.importCode == 'PN_NOTE_01');
        expect(r1.items.first.productName, 'Sofa Giường Nỉ Thông Minh');
        expect(r1.items.first.productCode, '');
        expect(r1.items.first.imageUrl, isNull);

        // 2. Fallback to "Sản phẩm [productId]" when note does not start with "Import - "
        final r2 = receipts.firstWhere((r) => r.importCode == 'PN_NOTE_02');
        expect(r2.items.first.productName, 'Sản phẩm PROD_GHOST_2');

        // 3. Fallback when both product and importPrice are missing (defaults to 0.0)
        final r3 = receipts.firstWhere((r) => r.importCode == 'PN_NOTE_03');
        expect(r3.items.first.productName, 'Sản phẩm PROD_GHOST_3');
        expect(r3.items.first.importPrice, 0.0);
        expect(r3.totalAmount, 0.0);
      });

      test('Missing supplierId defaults to paid in full (debt = 0)', () {
        final now = DateTime(2026, 9, 21, 11, 30);
        final transactions = <InventoryTransaction>[
          InventoryTransaction(
            id: 'tx_no_supplier',
            productId: 'p1',
            type: TransactionType.import,
            quantity: 3,
            importPrice: 500000,
            date: now,
            note: 'Nhập lẻ không có nhà cung cấp',
            supplierId: null,
            supplierName: null,
            importCode: 'PN_NO_SUP',
          ),
        ];

        final receipts =
            groupTransactionsToReceipts(transactions: transactions);
        expect(receipts.length, 1);
        final r = receipts.first;
        expect(r.supplierId, isNull);
        expect(r.supplierName, isNull);
        expect(r.totalAmount, 1500000.0);
        expect(r.paidAmount, 1500000.0);
        expect(r.debtAmount, 0.0);
      });

      test(
          'Missing importCode falls back to tx.id and generates valid PN_ code',
          () {
        final now = DateTime(2026, 9, 21, 12, 0);
        final transactions = <InventoryTransaction>[
          InventoryTransaction(
            id: 'tx_orphan_1',
            productId: 'p1',
            type: TransactionType.import,
            quantity: 2,
            importPrice: 100000,
            date: now,
            note: 'Orphan 1',
            importCode: null,
          ),
          InventoryTransaction(
            id: 'tx_orphan_2',
            productId: 'p2',
            type: TransactionType.import,
            quantity: 1,
            importPrice: 200000,
            date: now.add(const Duration(seconds: 10)),
            note: 'Orphan 2',
            importCode: '   ', // whitespace only
          ),
        ];

        final receipts =
            groupTransactionsToReceipts(transactions: transactions);
        // Each orphan transaction should form its own receipt without colliding
        expect(receipts.length, 2);
        expect(receipts.map((r) => r.id),
            containsAll(['tx_orphan_1', 'tx_orphan_2']));
        for (final r in receipts) {
          expect(r.importCode.startsWith('PN_'), isTrue);
        }
      });

      test(
          'Multi-item group with sparse header fields resolves metadata from any item',
          () {
        final now = DateTime(2026, 9, 21, 12, 30);
        const importCode = 'PN_SPARSE_01';

        final transactions = <InventoryTransaction>[
          // tx1 has storeId but null supplier
          InventoryTransaction(
            id: 'tx_sp_1',
            productId: 'p1',
            type: TransactionType.import,
            quantity: 1,
            importPrice: 100000,
            date: now,
            note: 'Item 1',
            storeId: 'store_002',
            supplierId: null,
            createdBy: null,
            importCode: importCode,
          ),
          // tx2 has supplier but null storeId
          InventoryTransaction(
            id: 'tx_sp_2',
            productId: 'p2',
            type: TransactionType.import,
            quantity: 2,
            importPrice: 200000,
            date: now.add(const Duration(minutes: 5)),
            note: 'Item 2',
            storeId: null,
            supplierId: 'NCC_SPARSE',
            supplierName: 'Gỗ Đồng Kỵ',
            createdBy: 'staff_thoi_binh',
            createdByName: 'Nhân viên Thới Bình',
            importCode: importCode,
          ),
        ];

        final receipts =
            groupTransactionsToReceipts(transactions: transactions);
        expect(receipts.length, 1);
        final r = receipts.first;
        expect(r.storeId, 'store_002');
        expect(r.supplierId, 'NCC_SPARSE');
        expect(r.supplierName, 'Gỗ Đồng Kỵ');
        expect(r.createdBy, 'staff_thoi_binh');
        expect(r.createdByName, 'Nhân viên Thới Bình');
        expect(r.date, now.add(const Duration(minutes: 5)),
            reason: 'Latest date in group is used');
      });
    });

    // -------------------------------------------------------------------------
    // 2. 1000 Items Single Batch Stress Test & Performance Harness
    // -------------------------------------------------------------------------
    group('2. 1000 Items Batch Stress & Performance', () {
      test(
          '1000 items in a single import batch: verifies execution time, sums, and memory sanity',
          () {
        const int itemCount = 1000;
        const String importCode = 'PN_STRESS_1000_ITEMS';
        final baseDate = DateTime(2026, 9, 21, 8, 0);

        final List<InventoryTransaction> transactions = [];
        final List<Product> products = [];
        int expectedTotalQuantity = 0;
        double expectedTotalAmount = 0.0;

        for (int i = 0; i < itemCount; i++) {
          final prodId = 'prod_stress_$i';
          final prodCode = 'SKU_${i.toString().padLeft(4, '0')}';
          final qty = (i % 20) + 1; // 1 to 20 units
          final unitPrice = ((i % 10) + 1) * 150000.0; // 150k to 1.5M VND
          final lineTotal = qty * unitPrice;

          expectedTotalQuantity += qty;
          expectedTotalAmount += lineTotal;

          products.add(Product(
            id: prodId,
            code: prodCode,
            name: 'Sản phẩm Nội Thất Mẫu $i',
            price: unitPrice * 1.5,
            costPrice: unitPrice,
            branchStocks: const {'store_001': 100},
            category: 'Nội thất',
            unit: 'Cái',
          ));

          transactions.add(InventoryTransaction(
            id: 'tx_stress_$i',
            productId: prodId,
            type: TransactionType.import,
            quantity: qty,
            importPrice: unitPrice,
            date: baseDate.add(Duration(seconds: i)),
            importCode: importCode,
            storeId: 'store_001',
            supplierId: 'NCC_MASSIVE',
            supplierName: 'Tổng Kho Gỗ Miền Tây',
            note: 'Stress test item #$i',
          ));
        }

        // Measure execution time
        final stopwatch = Stopwatch()..start();
        final receipts = groupTransactionsToReceipts(
          transactions: transactions,
          products: products,
        );
        stopwatch.stop();

        // 1. Grouping verification
        expect(receipts.length, 1);
        final r = receipts.first;

        // 2. Performance benchmark: 1000 items should complete well within 150ms in Dart VM
        expect(stopwatch.elapsedMilliseconds, lessThan(150),
            reason:
                'Grouping 1000 items took ${stopwatch.elapsedMilliseconds}ms, should be < 150ms');

        // 3. Exact sums verification
        expect(r.itemCount, itemCount);
        expect(r.totalQuantity, expectedTotalQuantity);
        expect(r.totalAmount, closeTo(expectedTotalAmount, 0.001));
        expect(r.paidAmount, closeTo(expectedTotalAmount, 0.001));
        expect(r.debtAmount, 0.0);

        // 4. Integrity check on first and last items
        expect(r.items.first.productId, 'prod_stress_0');
        expect(r.items.first.productCode, 'SKU_0000');
        expect(r.items.first.productName, 'Sản phẩm Nội Thất Mẫu 0');

        expect(r.items.last.productId, 'prod_stress_999');
        expect(r.items.last.productCode, 'SKU_0999');
        expect(r.items.last.productName, 'Sản phẩm Nội Thất Mẫu 999');
      });

      test(
          'Scale test: 1,000 transactions partitioned into 100 receipts correctly sorts chronologically',
          () {
        const int receiptCount = 100;
        const int itemsPerReceipt = 10;
        final List<InventoryTransaction> transactions = [];
        final baseDate = DateTime(2026, 1, 1);

        for (int r = 0; r < receiptCount; r++) {
          final receiptDate =
              baseDate.add(Duration(days: (r * 37) % 365, hours: r));
          final code = 'PN_BATCH_${r.toString().padLeft(3, '0')}';

          for (int item = 0; item < itemsPerReceipt; item++) {
            transactions.add(InventoryTransaction(
              id: 'tx_${r}_$item',
              productId: 'prod_$item',
              type: TransactionType.import,
              quantity: item + 1,
              importPrice: 100000,
              date: receiptDate.add(Duration(seconds: item)),
              note: 'Batch item',
              importCode: code,
              supplierId: 'NCC_BATCH',
            ));
          }
        }

        // Shuffle input list to stress-test ordering and grouping
        transactions.shuffle();

        final stopwatch = Stopwatch()..start();
        final receipts =
            groupTransactionsToReceipts(transactions: transactions);
        stopwatch.stop();

        expect(receipts.length, receiptCount);
        expect(stopwatch.elapsedMilliseconds, lessThan(150));

        // Verify strictly descending chronological order
        for (int i = 0; i < receipts.length - 1; i++) {
          final current = receipts[i].date;
          final next = receipts[i + 1].date;
          expect(
              current.isAfter(next) || current.isAtSameMomentAs(next), isTrue,
              reason:
                  'Receipt $i ($current) must be >= receipt ${i + 1} ($next)');
        }

        // Verify every receipt has exactly 10 items
        for (final r in receipts) {
          expect(r.itemCount, itemsPerReceipt);
        }
      });
    });

    // -------------------------------------------------------------------------
    // 3. Vietnamese Diacritics & Unaccented Search Stress Tests
    // -------------------------------------------------------------------------
    group('3. Vietnamese Unaccented Search Verification', () {
      final now = DateTime(2026, 9, 21, 14, 0);

      final rSofa = StockInReceipt(
        id: 'r_sofa',
        importCode: 'PN_SOFA_2026',
        date: now,
        supplierName: 'Công ty Cổ phần Đồ Gỗ Đồng Kỵ',
        note: 'Giao đợt 1 hàng phòng khách cao cấp',
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'p_sofa',
            quantity: 2,
            importPrice: 18000000,
            productName: 'Sofa Văng Nỉ Nhung Chữ L',
            productCode: 'SF-NN-01',
            note: 'Màu xám lông chuột',
          ),
        ],
      );

      final rGiuong = StockInReceipt(
        id: 'r_giuong',
        importCode: 'PN_GIUONG_2026',
        date: now,
        supplierName: 'Cửa Hàng Thần Tài Thổ Địa Phước Lộc',
        note: 'Bàn thờ và giường ngủ gia đình',
        items: const [
          StockInReceiptItem(
            transactionId: 't2',
            productId: 'p_giuong',
            quantity: 3,
            importPrice: 12000000,
            productName: 'Giường Ngủ Gỗ Sồi Nga 1m8',
            productCode: 'GN-SO-18',
            note: 'Hàng xuất khẩu',
          ),
          StockInReceiptItem(
            transactionId: 't3',
            productId: 'p_bantho',
            quantity: 1,
            importPrice: 8500000,
            productName: 'Bàn Thờ Treo Tường Chung Cư',
            productCode: 'BT-TT-01',
            note: 'Mẫu hiện đại',
          ),
        ],
      );

      final rNem = StockInReceipt(
        id: 'r_nem',
        importCode: 'PN_NEM_2026',
        date: now,
        supplierName: 'Công ty TNHH Đệm Kymdan Việt Nam',
        note: 'Chăn ga gối đệm phòng ngủ',
        items: const [
          StockInReceiptItem(
            transactionId: 't4',
            productId: 'p_nem',
            quantity: 5,
            importPrice: 4500000,
            productName: 'Nệm Cao Su Non Gấp 3 Thông Hơi',
            productCode: 'NCS-G3',
            note: 'Bảo hành 10 năm',
          ),
        ],
      );

      final testReceipts = [rSofa, rGiuong, rNem];

      void expectMatch(String query, List<String> expectedIds) {
        final filter =
            StockInReceiptsFilterState.defaults().copyWith(searchQuery: query);
        final matched = filterStockInReceipts(testReceipts, filter);
        expect(matched.map((r) => r.id).toList(), expectedIds,
            reason:
                'Query "$query" failed to match expected receipts: $expectedIds');
      }

      test(
          'matches supplierName with or without Vietnamese accents and mixed cases',
          () {
        // Accented exact
        expectMatch('Đồng Kỵ', ['r_sofa']);
        // Unaccented lowercase
        expectMatch('dong ky', ['r_sofa']);
        // Unaccented uppercase
        expectMatch('DONG KY', ['r_sofa']);
        // Special Vietnamese letter D with crossbar (đ / Đ)
        expectMatch('do go', ['r_sofa']);
        // Supplier with multiple words
        expectMatch('than tai tho dia', ['r_giuong']);
        expectMatch('kymdan viet nam', ['r_nem']);
      });

      test(
          'matches productName across different items with Vietnamese variations',
          () {
        // "sofa vang" -> matches "Sofa Văng Nỉ Nhung Chữ L"
        expectMatch('sofa vang', ['r_sofa']);
        // "giuong ngu go soi" -> matches "Giường Ngủ Gỗ Sồi Nga 1m8"
        expectMatch('giuong ngu go soi', ['r_giuong']);
        // "ban tho treo tuong" -> matches "Bàn Thờ Treo Tường Chung Cư"
        expectMatch('ban tho treo tuong', ['r_giuong']);
        // "nem cao su non" -> matches "Nệm Cao Su Non Gấp 3 Thông Hơi"
        expectMatch('nem cao su non', ['r_nem']);
      });

      test('matches item note and receipt note with unaccented text', () {
        // In item note: "mau xam long chuot"
        expectMatch('xam long chuot', ['r_sofa']);
        // In item note: "hang xuat khau"
        expectMatch('xuat khau', ['r_giuong']);
        // In receipt note: "chan ga goi dem"
        expectMatch('chan ga goi dem', ['r_nem']);
        // In receipt note: "phong khach cao cap"
        expectMatch('phong khach cao cap', ['r_sofa']);
      });

      test('matches productCode (SKU) and importCode case-insensitively', () {
        expectMatch('sf-nn-01', ['r_sofa']);
        expectMatch('GN-SO-18', ['r_giuong']);
        expectMatch('pn_nem_2026', ['r_nem']);
      });

      test(
          'handles leading, trailing, and excessive internal whitespaces gracefully',
          () {
        expectMatch('   sofa    vang   ', ['r_sofa']);
        expectMatch('   nem   cao   su   ', ['r_nem']);
      });

      test('non-matching query returns empty list', () {
        expectMatch('tủ lạnh toshiba', []);
        expectMatch('máy giặt electrolux', []);
        expectMatch('xe máy honda', []);
      });
    });

    // -------------------------------------------------------------------------
    // 4. Supplier Debt & Hostile Financial Scenarios
    // -------------------------------------------------------------------------
    group('4. Supplier Debt Financial Resilience', () {
      final now = DateTime(2026, 9, 21, 15, 0);

      test('clamps paidAmount to 0 when debtAmount is greater than totalAmount',
          () {
        final transactions = <InventoryTransaction>[
          InventoryTransaction(
            id: 'tx_over_debt',
            productId: 'p1',
            type: TransactionType.import,
            quantity: 1,
            importPrice: 5000000,
            // Total = 5,000,000
            date: now,
            note: 'Over debt import',
            supplierId: 'NCC001',
            importCode: 'PN_OVER_DEBT',
          ),
        ];

        final debts = [
          SupplierDebtTransaction(
            id: 'DTX_OVER',
            supplierId: 'NCC001',
            date: now,
            type: SupplierDebtType.importBill,
            amount: 8000000,
            // Recorded debt is 8,000,000 > 5,000,000
            remainingDebt: 8000000,
            referenceCode: 'PN_OVER_DEBT',
          ),
        ];

        final receipts = groupTransactionsToReceipts(
          transactions: transactions,
          debtTransactions: debts,
        );

        expect(receipts.length, 1);
        final r = receipts.first;
        expect(r.totalAmount, 5000000.0);
        expect(r.debtAmount, 8000000.0);
        expect(r.paidAmount, 0.0, reason: 'Paid amount must never be negative');
      });

      test(
          'prioritizes importBill debt over payment/other debt transactions sharing referenceCode',
          () {
        final transactions = <InventoryTransaction>[
          InventoryTransaction(
            id: 'tx_mult_debts',
            productId: 'p1',
            type: TransactionType.import,
            quantity: 2,
            importPrice: 10000000,
            // Total = 20,000,000
            date: now,
            note: 'Multi debts import',
            supplierId: 'NCC001',
            importCode: 'PN_MULTI_DEBT',
          ),
        ];

        final debts = [
          SupplierDebtTransaction(
            id: 'DTX_PAYMENT',
            supplierId: 'NCC001',
            date: now,
            type: SupplierDebtType.payment,
            // Payment transaction (not the bill debt)
            amount: 5000000,
            remainingDebt: 0,
            referenceCode: 'PN_MULTI_DEBT',
          ),
          SupplierDebtTransaction(
            id: 'DTX_BILL',
            supplierId: 'NCC001',
            date: now,
            type: SupplierDebtType.importBill,
            // The actual import bill debt
            amount: 12000000,
            remainingDebt: 12000000,
            referenceCode: 'PN_MULTI_DEBT',
          ),
        ];

        final receipts = groupTransactionsToReceipts(
          transactions: transactions,
          debtTransactions: debts,
        );

        expect(receipts.length, 1);
        final r = receipts.first;
        expect(r.debtAmount, 12000000.0);
        expect(r.paidAmount, 8000000.0); // 20M - 12M = 8M
      });
    });

    // -------------------------------------------------------------------------
    // 5. Extreme Numerical Bounds & Type Safety
    // -------------------------------------------------------------------------
    group('5. Numerical Bounds and Special Character Inputs', () {
      test('handles zero quantity and zero price without NaN or exception', () {
        final now = DateTime(2026, 9, 21, 16, 0);
        final transactions = <InventoryTransaction>[
          InventoryTransaction(
            id: 'tx_zero_qty',
            productId: 'p1',
            type: TransactionType.import,
            quantity: 0,
            importPrice: 1000000,
            date: now,
            note: 'Zero qty',
            importCode: 'PN_ZERO',
          ),
          InventoryTransaction(
            id: 'tx_zero_price',
            productId: 'p2',
            type: TransactionType.import,
            quantity: 5,
            importPrice: 0.0,
            date: now,
            note: 'Zero price',
            importCode: 'PN_ZERO',
          ),
        ];

        final receipts =
            groupTransactionsToReceipts(transactions: transactions);
        expect(receipts.length, 1);
        final r = receipts.first;
        expect(r.totalQuantity, 5);
        expect(r.totalAmount, 0.0);
        expect(r.paidAmount, 0.0);
        expect(r.debtAmount, 0.0);
      });

      test(
          'handles huge monetary values (billions VND) with full double precision',
          () {
        final now = DateTime(2026, 9, 21, 16, 30);
        final transactions = <InventoryTransaction>[
          InventoryTransaction(
            id: 'tx_huge',
            productId: 'p_expensive',
            type: TransactionType.import,
            quantity: 100,
            importPrice: 150000000.0,
            // 150 Million VND each => 15 Billion VND total
            date: now,
            note: 'Huge monetary value',
            importCode: 'PN_BILLION',
          ),
        ];

        final receipts =
            groupTransactionsToReceipts(transactions: transactions);
        expect(receipts.length, 1);
        final r = receipts.first;
        expect(r.totalAmount, 15000000000.0); // 15 Billion
        expect(r.paidAmount, 15000000000.0);
        expect(r.totalQuantity, 100);
      });

      test('handles unusual symbols in importCode (hyphens, slashes, hashes)',
          () {
        final now = DateTime(2026, 9, 21, 17, 0);
        const weirdCode = 'PN#2026/09-SPECIAL@BRANCH_1!';
        final transactions = <InventoryTransaction>[
          InventoryTransaction(
            id: 'tx_weird',
            productId: 'p1',
            type: TransactionType.import,
            quantity: 1,
            importPrice: 100000,
            date: now,
            note: 'Weird code item',
            importCode: weirdCode,
          ),
        ];

        final receipts =
            groupTransactionsToReceipts(transactions: transactions);
        expect(receipts.length, 1);
        expect(receipts.first.importCode, weirdCode);
        expect(receipts.first.id, weirdCode);
      });
    });

    // -------------------------------------------------------------------------
    // 6. Regex & Injection Search Resilience
    // -------------------------------------------------------------------------
    group('6. Regex and Special Character Search Injection Resilience', () {
      final now = DateTime(2026, 9, 21, 17, 30);
      final r = StockInReceipt(
        id: 'r_regex',
        importCode: 'PN(2026)[SPECIAL]',
        date: now,
        supplierName: 'Công ty Cổ phần Thế Giới Số (Digiworld)',
        note: 'Ghi chú có ký tự * + ? ^ \$ \\ /',
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'p1',
            quantity: 1,
            importPrice: 1000000,
            productName: 'Bàn Trà (Mẫu mới 2026) [Cao Cấp]',
            productCode: 'BT(01)+PRO',
            note: 'Phụ kiện: ốc vít * 10 con',
          ),
        ],
      );

      final receipts = [r];

      void checkQueryNoCrash(String query, bool shouldMatch) {
        final filter =
            StockInReceiptsFilterState.defaults().copyWith(searchQuery: query);
        final result = filterStockInReceipts(receipts, filter);
        if (shouldMatch) {
          expect(result.length, 1,
              reason: 'Expected query "$query" to match receipt');
        } else {
          expect(result.length, 0,
              reason: 'Expected query "$query" to yield 0 matches');
        }
      }

      test(
          'search query with parenthesis does not trigger Regex FormatException',
          () {
        checkQueryNoCrash('PN(2026)', true);
        checkQueryNoCrash('(Digiworld)', true);
        checkQueryNoCrash('(Mẫu mới', true);
        checkQueryNoCrash('((((((((', false);
      });

      test('search query with square brackets and glob symbols does not crash',
          () {
        checkQueryNoCrash('[SPECIAL]', true);
        checkQueryNoCrash('[Cao Cấp]', true);
        checkQueryNoCrash('[[[[[', false);
        checkQueryNoCrash('*', true);
        checkQueryNoCrash('+', true);
        checkQueryNoCrash('? ^ \$', true);
        checkQueryNoCrash('\\', true);
      });
    });

    // -------------------------------------------------------------------------
    // 7. Comprehensive Vietnamese Diacritics & Tone Matrix
    // -------------------------------------------------------------------------
    group('7. Comprehensive Vietnamese Diacritics & Tone Matrix', () {
      final now = DateTime(2026, 9, 21, 18, 0);

      // Construct receipts containing every Vietnamese vowel in various tones
      final rTone1 = StockInReceipt(
        id: 'r_tone_1',
        importCode: 'PN_TONE_1',
        date: now,
        supplierName: 'Xưởng Gỗ Mỹ Nghệ Đắc Lắc',
        // ă, ắ
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'p1',
            quantity: 1,
            importPrice: 5000000,
            productName: 'Trường Kỷ Gỗ Gụ Cẩn Ốc Xà Cừ',
            // ư, ờ, ỷ, ụ, ẩ, ố, à, ừ
            productCode: 'TK-GG-01',
          ),
        ],
      );

      final rTone2 = StockInReceipt(
        id: 'r_tone_2',
        importCode: 'PN_TONE_2',
        date: now,
        supplierName: 'Đồ Gỗ Mỹ Nghệ Phước Lộc Thọ',
        // ô, ỗ, ỹ, ệ, ướ, ộ
        items: const [
          StockInReceiptItem(
            transactionId: 't2',
            productId: 'p2',
            quantity: 2,
            importPrice: 3200000,
            productName: 'Ghế Cao Thắp Nhang Có Tay Vịn',
            // ế, ắp, ị
            productCode: 'GC-TN-02',
          ),
          StockInReceiptItem(
            transactionId: 't3',
            productId: 'p3',
            quantity: 1,
            importPrice: 4500000,
            productName: 'Xích Đu Giọt Nước Mây Nhựa Đôi',
            // í, đu, ọ, ướ, ự, ô
            productCode: 'XD-GN-03',
          ),
        ],
      );

      final receipts = [rTone1, rTone2];

      test(
          'unaccented queries match full spectrum of Vietnamese tones accurately',
          () {
        // "truong ky go gu" matches "Trường Kỷ Gỗ Gụ Cẩn Ốc Xà Cừ"
        final f1 = StockInReceiptsFilterState.defaults()
            .copyWith(searchQuery: 'truong ky go gu');
        expect(
            filterStockInReceipts(receipts, f1).map((r) => r.id), ['r_tone_1']);

        // "can oc xa cu" matches "Cẩn Ốc Xà Cừ"
        final f2 = StockInReceiptsFilterState.defaults()
            .copyWith(searchQuery: 'can oc xa cu');
        expect(
            filterStockInReceipts(receipts, f2).map((r) => r.id), ['r_tone_1']);

        // "ghe cao thap nhang" matches "Ghế Cao Thắp Nhang Có Tay Vịn"
        final f3 = StockInReceiptsFilterState.defaults()
            .copyWith(searchQuery: 'ghe cao thap nhang');
        expect(
            filterStockInReceipts(receipts, f3).map((r) => r.id), ['r_tone_2']);

        // "xich du giot nuoc" matches "Xích Đu Giọt Nước Mây Nhựa Đôi"
        final f4 = StockInReceiptsFilterState.defaults()
            .copyWith(searchQuery: 'xich du giot nuoc');
        expect(
            filterStockInReceipts(receipts, f4).map((r) => r.id), ['r_tone_2']);

        // "phuoc loc tho" matches supplier
        final f5 = StockInReceiptsFilterState.defaults()
            .copyWith(searchQuery: 'phuoc loc tho');
        expect(
            filterStockInReceipts(receipts, f5).map((r) => r.id), ['r_tone_2']);

        // "dac lac" matches "Đắc Lắc"
        final f6 = StockInReceiptsFilterState.defaults()
            .copyWith(searchQuery: 'dac lac');
        expect(
            filterStockInReceipts(receipts, f6).map((r) => r.id), ['r_tone_1']);
      });
    });

    // -------------------------------------------------------------------------
    // 8. Filter State Deserialization & Robustness Under Malformed Payloads
    // -------------------------------------------------------------------------
    group('8. Malformed JSON Serialization Robustness', () {
      test('deserializes safely from corrupted or missing fields', () {
        // Corrupted range name
        final f1 = StockInReceiptsFilterState.fromJson(
            {'timeRange': 'NON_EXISTENT_ENUM_VALUE'});
        expect(f1.timeRange, OverviewTimeRange.thisMonth);

        // Corrupted dates
        final f2 = StockInReceiptsFilterState.fromJson({
          'timeRange': 'custom',
          'customStartDate': 'not-a-valid-iso-date',
          'customEndDate': 123456,
        });
        expect(f2.customDateRange, isNull);

        // Numeric supplierId and storeId handled without crash
        final f3 = StockInReceiptsFilterState.fromJson({
          'supplierId': 98765,
          'storeId': 1002,
        });
        expect(f3.supplierId, '98765');
        expect(f3.storeId, '1002');

        // Completely empty JSON map
        final f4 = StockInReceiptsFilterState.fromJson({});
        expect(f4.timeRange, OverviewTimeRange.thisMonth);
        expect(f4.supplierId, isNull);
        expect(f4.storeId, 'all');
        expect(f4.searchQuery, '');
      });
    });

    // -------------------------------------------------------------------------
    // 9. 10,000 Receipts In-Memory Filtering Benchmark
    // -------------------------------------------------------------------------
    group('9. High-Throughput 10,000 Receipts Filtering Benchmark', () {
      test('filters 10,000 receipts in memory within 50ms', () {
        const int receiptCount = 10000;
        final baseDate = DateTime(2026, 9, 21);
        final List<StockInReceipt> massiveList =
            List.generate(receiptCount, (i) {
          return StockInReceipt(
            id: 'receipt_$i',
            importCode: 'PN_${i.toString().padLeft(5, '0')}',
            date: baseDate.subtract(Duration(hours: i % 720)),
            storeId: i % 2 == 0 ? 'store_001' : 'store_002',
            supplierId: 'NCC_${i % 10}',
            supplierName: 'Nhà cung cấp số ${i % 10}',
            note: 'Lô hàng $i',
            items: [
              StockInReceiptItem(
                transactionId: 't_$i',
                productId: 'prod_${i % 50}',
                productName: 'Mẫu sản phẩm ${i % 50}',
                productCode: 'SKU_${i % 50}',
                quantity: (i % 10) + 1,
                importPrice: 100000.0,
              ),
            ],
          );
        });

        final filter = StockInReceiptsFilterState.defaults().copyWith(
          timeRange: OverviewTimeRange.thisMonth,
          storeId: 'store_001',
          supplierId: 'NCC_2',
          searchQuery: 'mau san pham 2',
        );

        final stopwatch = Stopwatch()..start();
        final filtered = filterStockInReceipts(massiveList, filter);
        stopwatch.stop();

        expect(filtered.isNotEmpty, isTrue);
        expect(stopwatch.elapsedMilliseconds, lessThan(100),
            reason:
                'Filtering 10,000 receipts took ${stopwatch.elapsedMilliseconds}ms, should be < 100ms');

        // Verify filtered results adhere to all criteria
        for (final r in filtered) {
          expect(r.storeId, 'store_001');
          expect(r.supplierId, 'NCC_2');
        }
      });
    });

    // -------------------------------------------------------------------------
    // 10. Presentation & Widget Stress Test (StockInReceiptCard)
    // -------------------------------------------------------------------------
    group('10. StockInReceiptCard Presentation & Cost Security Stress', () {
      final baseDate = DateTime(2026, 9, 21, 10, 0);

      // 1000 items receipt
      final List<StockInReceiptItem> thousandItems = List.generate(1000, (i) {
        return StockInReceiptItem(
          transactionId: 'tx_c_$i',
          productId: 'prod_c_$i',
          productName: 'Món hàng $i',
          productCode: 'C_$i',
          quantity: 1,
          importPrice: 1000000.0,
        );
      });

      final stressReceipt = StockInReceipt(
        id: 'r_stress_card',
        importCode: 'PN_MASSIVE_1000',
        date: baseDate,
        storeId: 'store_001',
        supplierId: 'NCC001',
        supplierName: 'Công ty TNHH Nội Thất Sang Trọng',
        createdBy: 'admin_test',
        createdByName: 'Quản trị viên',
        note: 'Phiếu nhập quy mô 1000 mặt hàng',
        items: thousandItems,
        // Total = 1 Billion VND
        paidAmount: 700000000.0,
        debtAmount: 300000000.0,
      );

      testWidgets(
          'StockInReceiptCard renders 1000 items receipt cleanly without overflow',
          (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: StockInReceiptCard(
                  receipt: stressReceipt,
                  canViewCostPrice: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check import code
        expect(find.textContaining('PN_MASSIVE_1000'), findsOneWidget);
        // Check supplier
        expect(find.text('Công ty TNHH Nội Thất Sang Trọng'), findsOneWidget);
        // Check items count badge
        expect(find.text('1000 mặt hàng • 1000 sp'), findsOneWidget);
        // Check total amount is displayed (1.000.000.000)
        expect(find.textContaining('1.000.000.000'), findsOneWidget);
        // Zero RenderFlex errors
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'StockInReceiptCard securely masks 1 Billion VND cost when canViewCostPrice is false',
          (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: StockInReceiptCard(
                  receipt: stressReceipt,
                  canViewCostPrice: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Masked bullet indicator must appear
        expect(find.text('••••••'), findsOneWidget);
        // Billion amount must NOT be rendered anywhere in widget tree
        expect(find.textContaining('1.000.000.000'), findsNothing);
        expect(find.textContaining('700.000.000'), findsNothing);
        expect(find.textContaining('300.000.000'), findsNothing);
      });
    });
  });
}
