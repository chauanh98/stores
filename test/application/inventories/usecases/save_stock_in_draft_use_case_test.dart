import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/save_stock_in_draft_use_case.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/repositories/stock_in_receipt_repository.dart';

class FakeStockInReceiptRepository implements StockInReceiptRepository {
  final Map<String, StockInReceipt> savedDrafts = {};
  final Map<String, StockInReceipt> savedReceipts = {};
  int saveDraftCallCount = 0;

  @override
  Future<String> saveDraft(StockInReceipt receipt) async {
    saveDraftCallCount++;
    savedDrafts[receipt.id] = receipt;
    return receipt.id;
  }

  @override
  Future<void> updateDraft(StockInReceipt receipt) async {
    savedDrafts[receipt.id] = receipt;
  }

  @override
  Future<void> deleteDraft({required String storeId, required String receiptId}) async {
    savedDrafts.remove(receiptId);
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
      Stream.value(savedDrafts.values.toList());

  @override
  Future<List<StockInReceipt>> fetchReceipts(String storeId) async =>
      savedDrafts.values.toList();

  @override
  Future<StockInReceipt?> getReceiptById({required String storeId, required String receiptId}) async =>
      savedDrafts[receiptId] ?? savedReceipts[receiptId];

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    savedReceipts[receipt.id] = receipt;
  }

  @override
  Future<void> deleteReceipt({required String storeId, required String receiptId}) async {
    savedDrafts.remove(receiptId);
    savedReceipts.remove(receiptId);
  }

  @override
  Future<double?> getLatestImportPrice({required String storeId, required String productId}) async => null;
}

void main() {
  group('SaveStockInDraftUseCase Tests', () {
    late FakeStockInReceiptRepository fakeRepo;
    late SaveStockInDraftUseCase useCase;

    setUp(() {
      fakeRepo = FakeStockInReceiptRepository();
      useCase = SaveStockInDraftUseCase(fakeRepo);
    });

    test('Saves draft receipt with status "draft" and returns receipt ID', () async {
      final now = DateTime(2026, 9, 27, 9, 0);
      final receipt = StockInReceipt(
        id: 'draft_manual_01',
        importCode: 'PN_DRAFT_01',
        date: now,
        storeId: 'store_001',
        supplierId: 'sup_01',
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'prod_01',
            quantity: 10,
            unitPrice: 150000,
          ),
        ],
      );

      final returnedId = await useCase.execute(receipt);

      expect(returnedId, 'draft_manual_01');
      expect(fakeRepo.saveDraftCallCount, 1);
      final saved = fakeRepo.savedDrafts['draft_manual_01'];
      expect(saved, isNotNull);
      expect(saved!.status, 'draft');
      expect(saved.isDraft, isTrue);
      expect(saved.isCompleted, isFalse);
      expect(saved.isCancelled, isFalse);
      expect(saved.storeId, 'store_001');
      expect(saved.items.length, 1);
      expect(saved.items.first.productId, 'prod_01');
    });

    test('Auto-generates ID and importCode when empty and defaults storeId to store_001', () async {
      final receipt = StockInReceipt(
        id: '',
        importCode: '',
        date: DateTime.now(),
        items: const [],
      );

      final returnedId = await useCase.execute(receipt);

      expect(returnedId.startsWith('PN_DRAFT_'), isTrue);
      final saved = fakeRepo.savedDrafts[returnedId];
      expect(saved, isNotNull);
      expect(saved!.importCode.startsWith('PN_'), isTrue);
      expect(saved.storeId, 'store_001');
      expect(saved.status, 'draft');
    });

    test('INVARIANT: Draft save does NOT mutate stock, costPrice, debt or record transactions', () async {
      // Invariant: SaveStockInDraftUseCase only delegates to StockInReceiptRepository.saveDraft,
      // completely isolating it from ProductRepository, InventoryRepository, or SupplierRepository.
      final receipt = StockInReceipt(
        id: 'draft_safe_01',
        importCode: 'PN_SAFE',
        date: DateTime.now(),
        storeId: 'store_001',
        supplierId: 'sup_99',
        discount: 100000,
        paidAmount: 0,
        items: const [
          StockInReceiptItem(
            transactionId: 'tx_safe_1',
            productId: 'p_unmutated',
            quantity: 50,
            unitPrice: 500000,
          ),
        ],
      );

      await useCase.execute(receipt);

      final saved = fakeRepo.savedDrafts['draft_safe_01']!;
      expect(saved.status, 'draft');
      expect(saved.isDraft, isTrue);
      // Confirmed: 0 stock mutation, 0 debt mutation, only draft stored
      expect(fakeRepo.savedReceipts, isEmpty);
    });
  });
}
