import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';

void main() {
  group('StockInReceipt Grouping Logic Tests', () {
    const tProduct1 = Product(
      id: 'prod_001',
      name: 'Bàn Ăn 6 Ghế Gỗ Sồi',
      code: 'BA006',
      price: 6500000,
      costPrice: 4000000,
      branchStocks: {'store_001': 5},
      category: 'Bàn ghế',
      unit: 'Bộ',
      imageUrl: 'https://example.com/ba006.jpg',
    );

    const tProduct2 = Product(
      id: 'prod_002',
      name: 'Ghế Ăn Bọc Nệm',
      code: 'GA002',
      price: 850000,
      costPrice: 500000,
      branchStocks: {'store_001': 20},
      category: 'Bàn ghế',
      unit: 'Cái',
    );

    test('returns empty list when input transactions list is empty', () {
      final result = groupTransactionsToReceipts(transactions: []);
      expect(result, isEmpty);
    });

    test('filters out non-import transactions (exports and audits)', () {
      final transactions = [
        InventoryTransaction(
          id: 'tx_export_1',
          productId: 'prod_001',
          type: TransactionType.export,
          quantity: 2,
          date: DateTime(2026, 9, 21, 10, 0),
          note: 'Export for order',
        ),
        InventoryTransaction(
          id: 'tx_audit_1',
          productId: 'prod_002',
          type: TransactionType.inventoryAudit,
          quantity: 1,
          date: DateTime(2026, 9, 21, 10, 5),
          note: 'Audit balance',
        ),
      ];

      final result = groupTransactionsToReceipts(transactions: transactions);
      expect(result, isEmpty);
    });

    test(
        'groups multiple transactions sharing the same importCode into one receipt',
        () {
      final now = DateTime(2026, 9, 21, 14, 30);
      const importCode = 'PN_1726912345678';

      final transactions = [
        InventoryTransaction(
          id: 'tx_01',
          productId: 'prod_001',
          type: TransactionType.import,
          quantity: 3,
          importPrice: 4200000,
          date: now,
          note: 'Import - Bàn Ăn 6 Ghế Gỗ Sồi',
          storeId: 'store_001',
          supplierId: 'NCC001',
          supplierName: 'Nội Thất Minh Long',
          createdBy: 'admin',
          createdByName: 'Quản trị viên',
          importCode: importCode,
        ),
        InventoryTransaction(
          id: 'tx_02',
          productId: 'prod_002',
          type: TransactionType.import,
          quantity: 12,
          importPrice: 480000,
          date: now.add(const Duration(seconds: 1)),
          note: 'Import - Ghế Ăn Bọc Nệm',
          storeId: 'store_001',
          supplierId: 'NCC001',
          supplierName: 'Nội Thất Minh Long',
          createdBy: 'admin',
          createdByName: 'Quản trị viên',
          importCode: importCode,
        ),
      ];

      final receipts = groupTransactionsToReceipts(
        transactions: transactions,
        products: [tProduct1, tProduct2],
      );

      expect(receipts.length, 1);
      final receipt = receipts.first;

      expect(receipt.id, importCode);
      expect(receipt.importCode, importCode);
      expect(receipt.storeId, 'store_001');
      expect(receipt.supplierId, 'NCC001');
      expect(receipt.supplierName, 'Nội Thất Minh Long');
      expect(receipt.createdBy, 'admin');
      expect(receipt.createdByName, 'Quản trị viên');
      expect(receipt.itemCount, 2);
      expect(receipt.totalQuantity, 15); // 3 + 12

      // Total amount: (3 * 4,200,000) + (12 * 480,000) = 12,600,000 + 5,760,000 = 18,360,000
      expect(receipt.totalAmount, 18360000.0);

      // Verify item details enrichment
      final item1 = receipt.items.firstWhere((i) => i.productId == 'prod_001');
      expect(item1.productName, 'Bàn Ăn 6 Ghế Gỗ Sồi');
      expect(item1.productCode, 'BA006');
      expect(item1.imageUrl, 'https://example.com/ba006.jpg');
      expect(item1.unit, 'Bộ');
      expect(item1.quantity, 3);
      expect(item1.importPrice, 4200000.0);
      expect(item1.totalPrice, 12600000.0);

      final item2 = receipt.items.firstWhere((i) => i.productId == 'prod_002');
      expect(item2.productName, 'Ghế Ăn Bọc Nệm');
      expect(item2.productCode, 'GA002');
      expect(item2.unit, 'Cái');
      expect(item2.quantity, 12);
      expect(item2.importPrice, 480000.0);
      expect(item2.totalPrice, 5760000.0);

      // Paid in full by default when no debt record exists
      expect(receipt.paidAmount, 18360000.0);
      expect(receipt.debtAmount, 0.0);
    });

    test('falls back to transaction id when importCode is null or empty', () {
      final now = DateTime(2026, 9, 20, 11, 0);

      final transactions = [
        InventoryTransaction(
          id: 'tx_legacy_01',
          productId: 'prod_001',
          type: TransactionType.import,
          quantity: 2,
          importPrice: 4000000,
          date: now,
          note: 'Lô hàng cũ không có importCode',
          importCode: null,
        ),
      ];

      final receipts = groupTransactionsToReceipts(transactions: transactions);
      expect(receipts.length, 1);
      expect(receipts.first.id, 'tx_legacy_01');
      expect(receipts.first.importCode.startsWith('PN_'), isTrue);
      expect(receipts.first.totalQuantity, 2);
    });

    test('correctly matches debt from SupplierDebtTransaction', () {
      final now = DateTime(2026, 9, 21, 15, 0);
      const importCode = 'PN_DEBT_123';

      final transactions = [
        InventoryTransaction(
          id: 'tx_d1',
          productId: 'prod_001',
          type: TransactionType.import,
          quantity: 2,
          importPrice: 5000000,
          // Total = 10,000,000
          date: now,
          note: 'Import with debt',
          supplierId: 'NCC001',
          supplierName: 'Digiworld',
          importCode: importCode,
        ),
      ];

      final debts = [
        SupplierDebtTransaction(
          id: 'DTX_01',
          supplierId: 'NCC001',
          date: now,
          type: SupplierDebtType.importBill,
          amount: 4000000,
          // Debt recorded = 4,000,000 (Paid = 6,000,000)
          remainingDebt: 4000000,
          referenceCode: importCode,
        ),
      ];

      final receipts = groupTransactionsToReceipts(
        transactions: transactions,
        products: [tProduct1],
        debtTransactions: debts,
      );

      expect(receipts.length, 1);
      final r = receipts.first;
      expect(r.totalAmount, 10000000.0);
      expect(r.debtAmount, 4000000.0);
      expect(r.paidAmount, 6000000.0);
    });

    test(
        'extracts fallback product name from note when product not in catalogue',
        () {
      final now = DateTime(2026, 9, 21, 9, 0);

      final transactions = [
        InventoryTransaction(
          id: 'tx_unk',
          productId: 'prod_unknown_99',
          type: TransactionType.import,
          quantity: 5,
          importPrice: 150000,
          date: now,
          note: 'Import - Tủ Quần Áo 3 Cánh',
          importCode: 'PN_UNKNOWN',
        ),
      ];

      final receipts = groupTransactionsToReceipts(
        transactions: transactions,
        products: [], // Empty products catalog
      );

      expect(receipts.length, 1);
      expect(receipts.first.items.first.productName, 'Tủ Quần Áo 3 Cánh');
    });

    test('sorts receipts descending by date (latest first)', () {
      final d1 = DateTime(2026, 9, 10);
      final d2 = DateTime(2026, 9, 21);
      final d3 = DateTime(2026, 9, 15);

      final transactions = [
        InventoryTransaction(
          id: 'tx1',
          productId: 'prod_001',
          type: TransactionType.import,
          quantity: 1,
          date: d1,
          note: 'Import 1',
          importCode: 'PN_D1',
        ),
        InventoryTransaction(
          id: 'tx2',
          productId: 'prod_001',
          type: TransactionType.import,
          quantity: 1,
          date: d2,
          note: 'Import 2',
          importCode: 'PN_D2',
        ),
        InventoryTransaction(
          id: 'tx3',
          productId: 'prod_001',
          type: TransactionType.import,
          quantity: 1,
          date: d3,
          note: 'Import 3',
          importCode: 'PN_D3',
        ),
      ];

      final receipts = groupTransactionsToReceipts(transactions: transactions);
      expect(receipts.length, 3);
      expect(receipts[0].importCode, 'PN_D2');
      expect(receipts[1].importCode, 'PN_D3');
      expect(receipts[2].importCode, 'PN_D1');
    });

    test(
        'StockInReceipt and StockInReceiptItem copyWith and equality work properly',
        () {
      final now = DateTime(2026, 9, 21);
      const item = StockInReceiptItem(
        transactionId: 't1',
        productId: 'p1',
        quantity: 5,
        importPrice: 100000,
      );

      final itemCopy = item.copyWith(quantity: 10);
      expect(itemCopy.quantity, 10);
      expect(itemCopy.totalPrice, 1000000.0);

      final receipt = StockInReceipt(
        id: 'r1',
        importCode: 'PN_1',
        date: now,
        items: [item],
      );

      final receiptCopy = receipt.copyWith(note: 'Updated Note');
      expect(receiptCopy.note, 'Updated Note');
      expect(receiptCopy.totalAmount, 500000.0);
    });
  });
}
