import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';

void main() {
  group('StockInReceipt Entity Tests', () {
    final now = DateTime(2026, 9, 27, 8, 30);
    const item1 = StockInReceiptItem(
      transactionId: 'tx_1',
      productId: 'p_001',
      quantity: 5,
      unitPrice: 90000,
      originalPrice: 100000,
      discount: 10000,
      discountPercentage: 10,
      productName: 'Lúa giống ST25',
      productCode: 'ST25',
    );
    const item2 = StockInReceiptItem(
      transactionId: 'tx_2',
      productId: 'p_002',
      quantity: 2,
      unitPrice: 200000,
      productName: 'Phân bón NPK',
    );

    test('Status helpers evaluate correctly for draft status', () {
      final receiptDraft = StockInReceipt(
        id: 'draft_1',
        importCode: 'PN_D1',
        date: now,
        status: 'draft',
        items: const [item1],
      );
      expect(receiptDraft.isDraft, isTrue);
      expect(receiptDraft.isCompleted, isFalse);
      expect(receiptDraft.isCancelled, isFalse);

      final receiptPhieuTam = StockInReceipt(
        id: 'draft_2',
        importCode: 'PN_D2',
        date: now,
        status: 'Phiếu tạm',
        items: const [item1],
      );
      expect(receiptPhieuTam.isDraft, isTrue);
      expect(receiptPhieuTam.isCompleted, isFalse);
      expect(receiptPhieuTam.isCancelled, isFalse);
    });

    test('Status helpers evaluate correctly for cancelled status', () {
      final receiptCancelled = StockInReceipt(
        id: 'cancel_1',
        importCode: 'PN_C1',
        date: now,
        status: 'cancelled',
        cancelReason: 'Nhập nhầm số lượng',
        cancelledAt: now,
        cancelledBy: 'admin',
        items: const [item1],
      );
      expect(receiptCancelled.isCancelled, isTrue);
      expect(receiptCancelled.isDraft, isFalse);
      expect(receiptCancelled.isCompleted, isFalse);
      expect(receiptCancelled.cancelReason, 'Nhập nhầm số lượng');
      expect(receiptCancelled.cancelledBy, 'admin');

      final receiptDaHuy = StockInReceipt(
        id: 'cancel_2',
        importCode: 'PN_C2',
        date: now,
        status: 'Đã hủy',
        items: const [item1],
      );
      expect(receiptDaHuy.isCancelled, isTrue);
      expect(receiptDaHuy.isCompleted, isFalse);
    });

    test('Status helpers evaluate correctly for completed status', () {
      final receiptCompleted1 = StockInReceipt(
        id: 'comp_1',
        importCode: 'PN_001',
        date: now,
        status: 'Đã nhập hàng',
        items: const [item1],
      );
      expect(receiptCompleted1.isCompleted, isTrue);
      expect(receiptCompleted1.isDraft, isFalse);
      expect(receiptCompleted1.isCancelled, isFalse);

      final receiptCompleted2 = StockInReceipt(
        id: 'comp_2',
        importCode: 'PN_002',
        date: now,
        status: 'completed',
        items: const [item1],
      );
      expect(receiptCompleted2.isCompleted, isTrue);

      final receiptCompleted3 = StockInReceipt(
        id: 'comp_3',
        importCode: 'PN_003',
        date: now,
        status: 'Đã hoàn thành',
        items: const [item1],
      );
      expect(receiptCompleted3.isCompleted, isTrue);
    });

    test('Default paymentMethod is cash', () {
      final receipt = StockInReceipt(
        id: 'r_default',
        importCode: 'PN_DEF',
        date: now,
        items: const [item1],
      );
      expect(receipt.paymentMethod, 'cash');
    });

    test(
        'Calculations: totalQuantity, totalAmount, effectiveNetPayable, remainingDebt',
        () {
      // item1: 5 * 90,000 = 450,000
      // item2: 2 * 200,000 = 400,000
      // totalAmount = 850,000
      final receipt = StockInReceipt(
        id: 'r_calc',
        importCode: 'PN_CALC',
        date: now,
        discount: 50000,
        paidAmount: 300000,
        items: const [item1, item2],
      );

      expect(receipt.totalQuantity, 7);
      expect(receipt.itemCount, 2);
      expect(receipt.totalAmount, 850000.0);
      expect(receipt.effectiveNetPayable, 800000.0); // 850,000 - 50,000
      expect(receipt.remainingDebt, 500000.0); // 800,000 - 300,000
    });

    test('StockInReceiptItem getters: subtotal and totalDiscount', () {
      // item1: qty=5, unitPrice=90,000, origPrice=100,000, discount=10,000
      expect(item1.effectiveOriginalPrice, 100000.0);
      expect(item1.totalPrice, 450000.0);
      expect(item1.subtotal, 500000.0);
      expect(item1.totalDiscount, 50000.0);

      // item2: qty=2, unitPrice=200,000, origPrice null, discount=0
      expect(item2.effectiveOriginalPrice, 200000.0);
      expect(item2.totalPrice, 400000.0);
      expect(item2.subtotal, 400000.0);
      expect(item2.totalDiscount, 0.0);

      // item3 with discount but no origPrice
      const item3 = StockInReceiptItem(
        transactionId: 'tx_3',
        productId: 'p_003',
        quantity: 3,
        unitPrice: 80000,
        discount: 20000,
      );
      expect(item3.effectiveOriginalPrice, 100000.0); // 80,000 + 20,000
      expect(item3.subtotal, 300000.0);
      expect(item3.totalDiscount, 60000.0);
    });

    test('Serialization toMap and fromMap round-trip preserves all fields', () {
      final original = StockInReceipt(
        id: 'r_roundtrip',
        importCode: 'PN_ROUNDTRIP',
        date: now,
        storeId: 'store_001',
        branchName: 'Chi nhánh Đông Thắng',
        supplierId: 'sup_001',
        supplierName: 'Công ty ABC',
        supplierPhone: '0901234567',
        createdBy: 'usr_01',
        createdByName: 'Nguyễn Văn A',
        note: 'Phiếu kiểm hàng',
        items: const [item1, item2],
        discount: 20000,
        paidAmount: 500000,
        status: 'cancelled',
        paymentMethod: 'Tiền mặt',
        cancelReason: 'Sai chứng từ',
        cancelledAt: now,
        cancelledBy: 'supervisor_1',
        createdAt: now.subtract(const Duration(hours: 1)),
        updatedAt: now,
      );

      final map = original.toMap();
      final reconstructed = StockInReceipt.fromMap(map);

      expect(reconstructed.id, original.id);
      expect(reconstructed.importCode, original.importCode);
      expect(reconstructed.date, original.date);
      expect(reconstructed.storeId, original.storeId);
      expect(reconstructed.branchName, original.branchName);
      expect(reconstructed.supplierId, original.supplierId);
      expect(reconstructed.supplierName, original.supplierName);
      expect(reconstructed.supplierPhone, original.supplierPhone);
      expect(reconstructed.createdBy, original.createdBy);
      expect(reconstructed.createdByName, original.createdByName);
      expect(reconstructed.note, original.note);
      expect(reconstructed.status, original.status);
      expect(reconstructed.paymentMethod, original.paymentMethod);
      expect(reconstructed.cancelReason, original.cancelReason);
      expect(reconstructed.cancelledAt, original.cancelledAt);
      expect(reconstructed.cancelledBy, original.cancelledBy);
      expect(reconstructed.totalAmount, original.totalAmount);
      expect(reconstructed.discount, original.discount);
      expect(reconstructed.paidAmount, original.paidAmount);
      expect(reconstructed.items.length, 2);
      expect(reconstructed.items.first.productId, 'p_001');
      expect(reconstructed.items.first.unitPrice, 90000.0);
    });

    test('copyWith updates fields without side effects', () {
      final original = StockInReceipt(
        id: 'r_copy',
        importCode: 'PN_COPY',
        date: now,
        status: 'draft',
        paymentMethod: 'cash',
        items: const [item1],
      );

      final updated = original.copyWith(
        status: 'completed',
        paymentMethod: 'Chuyển khoản',
        cancelReason: 'Không hủy',
      );

      expect(updated.id, original.id);
      expect(updated.status, 'completed');
      expect(updated.paymentMethod, 'Chuyển khoản');
      expect(updated.cancelReason, 'Không hủy');
      expect(original.status, 'draft');
      expect(original.paymentMethod, 'cash');
    });

    test(
        'StockInReceiptItem.toMap excludes base64 data:image URIs to prevent bandwidth blowup',
        () {
      const normalItem = StockInReceiptItem(
        transactionId: 'tx_normal',
        productId: 'p_normal',
        quantity: 1,
        unitPrice: 10000,
        imageUrl: 'https://storage.googleapis.com/bucket/image.png',
      );
      final normalMap = normalItem.toMap();
      expect(normalMap['imageUrl'],
          equals('https://storage.googleapis.com/bucket/image.png'));

      const base64Item = StockInReceiptItem(
        transactionId: 'tx_b64',
        productId: 'p_b64',
        quantity: 1,
        unitPrice: 10000,
        imageUrl: 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBD...',
      );
      final base64Map = base64Item.toMap();
      expect(base64Map.containsKey('imageUrl'), isFalse);
    });
  });
}
