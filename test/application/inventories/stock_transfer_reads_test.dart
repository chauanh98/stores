import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/stock_transfer_use_cases.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/stock_transfer.dart';

import 'package:stores/domain/repositories/stock_transfer_repository.dart';

import '../../support/fake_rtdb.dart';

/// Egress tests: transfer use cases must never read a whole product doc
/// (which can hold Base64 images) on the common path.
void main() {
  const src = 'store_001';
  const dst = 'store_002';
  final big = 'data:image/png;base64,${'A' * 2000}';

  late FakeRtdb db;
  late FakeStockTransferRepository repo;

  void seed(String store, String id, Map<String, int> stocks,
          {bool image = true}) =>
      db.seed('stores/$store/products/$id', {
        'id': id,
        'name': 'SP $id',
        'code': 'C$id',
        'price': 500.0,
        'costPrice': 300.0 + (int.tryParse(id.substring(1)) ?? 0),
        'category': 'cat',
        'branchStocks': stocks,
        if (image) 'imageUrl': big,
      });

  int stockOf(String store, String id) => ProductModel.fromMap(
          db.read('stores/$store/products/$id') as Map, store)
      .toEntity()
      .stockInBranch(store);

  bool isFullProductRead(String p) =>
      RegExp(r'^stores/[^/]+/products/[^/]+$').hasMatch(p);

  StockTransfer draft(int n, {int qty = 2}) => StockTransfer(
        id: '',
        code: '',
        status: StockTransferStatus.draft,
        sourceStoreId: src,
        sourceStoreName: 'A',
        targetStoreId: dst,
        targetStoreName: 'B',
        items: [
          for (var i = 0; i < n; i++)
            StockTransferItem(
                productId: 'p$i',
                name: 'SP p$i',
                code: 'Cp$i',
                quantity: qty,
                imageUrl: 'https://x/p$i.png')
        ],
        createdAt: DateTime(2026, 1, 1),
      );

  setUp(() {
    db = FakeRtdb();
    repo = FakeStockTransferRepository(db);
  });

  test('create: no full-product read, <=3 tiny reads/item, same results',
      () async {
    const n = 45; // > 2 chunks
    for (var i = 0; i < n; i++) {
      seed(src, 'p$i', {src: 10 + i, dst: 0});
      if (i.isEven) seed(dst, 'p$i', {src: 10 + i, dst: i});
    }
    db.getPaths.clear();
    final t = await CreateStockTransferUseCase(db, repo, null).execute(draft(n));
    final productReads =
        db.getPaths.where((p) => p.contains('/products/')).toList();
    expect(productReads.any(isFullProductRead), isFalse);
    // before: 3 FULL docs per item; now 3 one-field reads (2 when target missing
    // + up to 3 cheap existence probes for the missing one)
    expect(productReads.length, lessThanOrEqualTo(n * 6));
    expect(productReads.where((p) => p.endsWith('/branchStocks')).length, n * 2);
    expect(db.updateCalls, 1); // still one atomic multi-path update
    for (var i = 0; i < n; i++) {
      expect(stockOf(src, 'p$i'), 10 + i - 2);
      if (i.isEven) {
        // target record synced with source stock, own stock untouched
        expect(stockOf(dst, 'p$i'), i);
        final bs = db.read('stores/$dst/products/p$i/branchStocks') as Map;
        expect(bs['store_001'], 10 + i - 2);
      } else {
        expect(db.read('stores/$dst/products/p$i'), isNull);
      }
      expect(db.read('stores/$src/products/p$i/imageUrl'), big); // untouched
    }
    final saved = await repo.getById(t.id);
    expect(saved!.items.map((e) => e.unitPrice),
        [for (var i = 0; i < n; i++) 300.0 + i]);
    expect(saved.items.first.imageUrl, 'https://x/p0.png');
    expect(
        db.read(StockTransferRepository.pendingIndexPath(dst, t.id)), true);
  });

  test('create: insufficient stock keeps first-in-order error, no write',
      () async {
    for (var i = 0; i < 30; i++) {
      seed(src, 'p$i', {src: i == 25 || i == 3 ? 1 : 10, dst: 0});
    }
    await expectLater(
        CreateStockTransferUseCase(db, repo, null).execute(draft(30)),
        throwsA(predicate((e) => e.toString().contains('SP p3'))));
    expect(db.updateCalls, 0);
  });

  test('receive: existing target = 2 tiny reads/item; missing target = 1 full',
      () async {
    for (var i = 0; i < 4; i++) {
      seed(src, 'p$i', {src: 10, dst: 0});
      if (i < 2) seed(dst, 'p$i', {src: 10, dst: 5});
    }
    final t = await CreateStockTransferUseCase(db, repo, null).execute(draft(4));
    db.getPaths.clear();
    await ReceiveStockTransferUseCase(db, repo, null)
        .execute(t.id, receivedByProduct: {for (var i = 0; i < 4; i++) 'p$i': 2});
    final reads = db.getPaths.where((p) => p.contains('/products/')).toList();
    final full = reads.where(isFullProductRead).toList();
    expect(full.length, 2); // only the 2 products missing at target
    expect(full.every((p) => p.startsWith('stores/$src/')), isTrue);
    expect(reads.where((p) => p.endsWith('/branchStocks')).length, 4 * 2);
    for (var i = 0; i < 2; i++) {
      expect(stockOf(dst, 'p$i'), 7);
    }
    for (var i = 2; i < 4; i++) {
      expect(stockOf(dst, 'p$i'), 2); // product created at target
      expect(db.read('stores/$dst/products/p$i/name'), 'SP p$i');
    }
    expect(db.read(StockTransferRepository.pendingIndexPath(dst, t.id)), isNull);
    expect(db.read('stock_transfers/${t.id}/status'), 'received');
  });

  test('cancel: 2 tiny reads/item (source + target sync) and stock restored', () async {
    for (var i = 0; i < 25; i++) {
      seed(src, 'p$i', {src: 10, dst: 0});
    }
    final t = await CreateStockTransferUseCase(db, repo, null).execute(draft(25));
    db.getPaths.clear();
    await CancelStockTransferUseCase(db, repo, null).execute(t.id);
    final reads = db.getPaths.where((p) => p.contains('/products/')).toList();
    expect(reads.any(isFullProductRead), isFalse);
    expect(reads.length, 50); // source branchStocks + target branchStocks probe
    for (var i = 0; i < 25; i++) {
      expect(stockOf(src, 'p$i'), 10);
    }
    expect(db.read('stock_transfers/${t.id}/status'), 'cancelled');
  });
}
