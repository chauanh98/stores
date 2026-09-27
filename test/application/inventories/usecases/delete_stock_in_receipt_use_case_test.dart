import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/delete_stock_in_receipt_use_case.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/repositories/stock_in_receipt_repository.dart';

class MockStockInReceiptRepository implements StockInReceiptRepository {
  final Map<String, StockInReceipt> receipts = {};
  int deleteCount = 0;

  @override
  Future<String> saveDraft(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
    return receipt.id;
  }

  @override
  Future<void> updateDraft(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
  }

  @override
  Future<void> deleteDraft(
      {required String storeId, required String receiptId}) async {
    deleteCount++;
    receipts.remove(receiptId);
  }

  @override
  Future<void> cancelReceipt({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {}

  @override
  Stream<List<StockInReceipt>> watchReceipts(String storeId) =>
      Stream.value(receipts.values.toList());

  @override
  Future<List<StockInReceipt>> fetchReceipts(String storeId) async =>
      receipts.values.toList();

  @override
  Future<StockInReceipt?> getReceiptById(
          {required String storeId, required String receiptId}) async =>
      receipts[receiptId];

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
  }

  @override
  Future<void> deleteReceipt(
      {required String storeId, required String receiptId}) async {
    deleteCount++;
    receipts.remove(receiptId);
  }

  @override
  Future<double?> getLatestImportPrice(
          {required String storeId, required String productId}) async =>
      null;
}

void main() {
  group('DeleteStockInReceiptUseCase Tests', () {
    late MockStockInReceiptRepository mockRepo;
    late DeleteStockInReceiptUseCase useCase;

    setUp(() {
      mockRepo = MockStockInReceiptRepository();
      useCase = DeleteStockInReceiptUseCase(mockRepo);
    });

    test('Deletes a draft receipt from repository successfully', () async {
      final draft = StockInReceipt(
        id: 'draft_delete_me',
        importCode: 'PN_DRAFT_DEL',
        date: DateTime.now(),
        status: 'draft',
        items: const [],
      );
      mockRepo.receipts['draft_delete_me'] = draft;

      await useCase.execute(storeId: 'store_001', receipt: draft);

      expect(mockRepo.deleteCount, 1);
      expect(mockRepo.receipts.containsKey('draft_delete_me'), isFalse);
    });

    test('Deletes a cancelled receipt from repository successfully', () async {
      final cancelled = StockInReceipt(
        id: 'cancelled_delete_me',
        importCode: 'PN_CANCEL_DEL',
        date: DateTime.now(),
        status: 'cancelled',
        cancelReason: 'Đã hủy',
        items: const [],
      );
      mockRepo.receipts['cancelled_delete_me'] = cancelled;

      await useCase.execute(storeId: 'store_001', receipt: cancelled);

      expect(mockRepo.deleteCount, 1);
      expect(mockRepo.receipts.containsKey('cancelled_delete_me'), isFalse);
    });

    test(
        'SAFETY INVARIANT: Throws StateError when attempting to delete completed receipt',
        () async {
      final completed = StockInReceipt(
        id: 'completed_no_delete',
        importCode: 'PN_COMPLETED',
        date: DateTime.now(),
        status: 'completed',
        items: const [],
      );
      mockRepo.receipts['completed_no_delete'] = completed;

      expect(
        () => useCase.execute(storeId: 'store_001', receipt: completed),
        throwsA(isA<StateError>()),
      );
      expect(mockRepo.deleteCount, 0);
      expect(mockRepo.receipts.containsKey('completed_no_delete'), isTrue);
    });
  });
}
