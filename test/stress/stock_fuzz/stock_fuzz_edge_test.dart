// Deterministic edge cases + regression tests for bugs found by the stock fuzz.
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/stock_transfer_use_cases.dart';
import 'package:stores/application/inventory/inter_store_transfer_service.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/stock_transfer.dart';
import 'package:stores/domain/repositories/stock_transfer_repository.dart';

import 'fuzz_support.dart';

void main() {
  setUpAll(initFuzzLocale);

  late Harness h;
  setUp(() => h = Harness(threeBranches: false));

  void seed(String store, String id, Object stocks,
          {double cost = 100, bool withName = true}) =>
      h.db.seed('stores/$store/products/$id', {
        'id': id,
        if (withName) 'name': 'P $id',
        'code': 'C$id',
        'price': 200.0,
        'costPrice': cost,
        'category': 'c',
        'branchStocks': stocks,
      });

  int own(String store, String id) =>
      h.entityAt(store, id)!.stockInBranch(store);

  StockTransfer draft(List<StockTransferItem> items,
          {String from = 'store_001',
          String to = 'store_002',
          String id = ''}) =>
      StockTransfer(
          id: id,
          code: '',
          status: StockTransferStatus.draft,
          sourceStoreId: from,
          sourceStoreName: 'A',
          targetStoreId: to,
          targetStoreName: 'B',
          items: items,
          createdAt: DateTime(2026, 1, 1));

  StockTransferItem it(String id, int q) => StockTransferItem(
      productId: id, name: 'P $id', code: 'C$id', quantity: q);

  StockInReceipt receipt(
          String id, String store, List<StockInReceiptItem> items,
          {String? supplier, double? paid, double discount = 0}) =>
      StockInReceipt(
          id: id,
          importCode: 'PN$id',
          date: DateTime(2026, 8, 1),
          storeId: store,
          items: items,
          status: 'draft',
          supplierId: supplier,
          paidAmount: paid,
          discount: discount);

  StockInReceiptItem line(String p, int q, double price) => StockInReceiptItem(
      transactionId: 't', productId: p, quantity: q, unitPrice: price);

  group('transfer regressions', () {
    test(
        'duplicate product lines are deducted by the SUM (was: last line only)',
        () async {
      seed('store_001', 'p1', {'store_001': 10, 'store_002': 0});
      final t = await h.create.execute(draft([it('p1', 3), it('p1', 4)]));
      expect(own('store_001', 'p1'), 3);
      expect(t.totalQuantity, 7);
      // and over-asking via duplicates is rejected as a whole
      await expectLater(h.create.execute(draft([it('p1', 2), it('p1', 2)])),
          throwsA(isA<StockTransferException>()));
      expect(own('store_001', 'p1'), 3);
    });

    test(
        'legacy in-transit slip with duplicate lines: receive/cancel stay exact',
        () async {
      seed('store_001', 'p1', {'store_001': 0, 'store_002': 0});
      for (final id in ['A', 'B']) {
        h.db.seed(
            'stock_transfers/$id',
            StockTransfer(
              id: id,
              code: 'TRF$id',
              status: StockTransferStatus.inTransit,
              sourceStoreId: 'store_001',
              sourceStoreName: 'A',
              targetStoreId: 'store_002',
              targetStoreName: 'B',
              items: [it('p1', 3), it('p1', 3)],
              createdAt: DateTime(2026, 1, 1),
            ).toMap());
        h.db.seed('stock_transfer_pending/store_002/$id', true);
      }
      await h.receive.execute('A', receivedByProduct: {'p1': 3});
      expect(own('store_002', 'p1'), 3, reason: 'declared 3 must not become 6');
      await h.cancelTr.execute('B');
      expect(own('store_001', 'p1'), 6, reason: 'cancel refunds the full 3+3');
    });

    test('alias store ids are normalised: slip, pending index, product paths',
        () async {
      seed('store_001', 'p1', {'store_001': 10, 'store_002': 0});
      final t = await h.create
          .execute(draft([it('p1', 4)], from: 'branch_1', to: 'branch_2'));
      expect(t.sourceStoreId, 'store_001');
      expect(t.targetStoreId, 'store_002');
      expect(h.db.read('stock_transfer_pending/store_002/${t.id}'), true);
      expect(h.db.read('stock_transfer_pending/branch_2'), isNull);
      await h.receive.execute(t.id, receivedByProduct: {'p1': 4});
      expect(h.db.read('stores/branch_2'), isNull);
      expect(h.db.read('stores/branch_1'), isNull);
      expect(own('store_002', 'p1'), 4);
      expect(h.db.read('stock_transfer_pending/store_002/${t.id}'), isNull);
      // legacy slip that was stored with an alias target is still received OK
      h.db.seed(
          'stock_transfers/L',
          StockTransfer(
                  id: 'L',
                  code: 'TRFL',
                  status: StockTransferStatus.inTransit,
                  sourceStoreId: 'store_001',
                  sourceStoreName: 'A',
                  targetStoreId: 'branch_2',
                  targetStoreName: 'B',
                  items: [it('p1', 2)],
                  createdAt: DateTime(2026, 1, 1))
              .toMap());
      h.db.seed('stock_transfer_pending/branch_2/L', true);
      await h.receive.execute('L', receivedByProduct: {'p1': 2});
      expect(own('store_002', 'p1'), 6);
      expect(prune(h.db.read('stock_transfer_pending')), isEmpty);
      expect(h.db.read('stores/branch_2'), isNull);
    });

    test('same store through an alias is rejected', () async {
      seed('store_001', 'p1', {'store_001': 10});
      for (final pair in [
        ['store_001', 'branch_1'],
        ['branch_2', 'store_002'],
        ['ĐT', 'store_001'],
      ]) {
        await expectLater(
            h.create.execute(draft([it('p1', 1)], from: pair[0], to: pair[1])),
            throwsA(isA<StockTransferException>()));
      }
      expect(own('store_001', 'p1'), 10);
    });

    test('cancel keeps the target copy of the source stock in sync', () async {
      seed('store_001', 'p1', {'store_001': 10, 'store_002': 5});
      seed('store_002', 'p1', {'store_001': 10, 'store_002': 5});
      final t = await h.create.execute(draft([it('p1', 4)]));
      expect(h.entityAt('store_002', 'p1')!.stockInBranch('store_001'), 6);
      await h.cancelTr.execute(t.id);
      expect(h.entityAt('store_002', 'p1')!.stockInBranch('store_001'), 10);
      expect(own('store_001', 'p1'), 10);
    });

    test('product missing at target: receive creates the record', () async {
      seed('store_001', 'p1', {'store_001': 10, 'store_002': 0});
      final t = await h.create.execute(draft([it('p1', 5)]));
      expect(h.db.read('stores/store_002/products/p1'), isNull);
      await h.receive.execute(t.id, receivedByProduct: {'p1': 3});
      expect(own('store_002', 'p1'), 3);
      expect(h.db.read('stores/store_002/products/p1/name'), 'P p1');
      // 2 units short are NOT refunded (in transit / lost by design)
      expect(own('store_001', 'p1'), 5);
    });

    test('concurrent receives from two devices credit once', () async {
      seed('store_001', 'p1', {'store_001': 10, 'store_002': 0});
      final t = await h.create.execute(draft([it('p1', 5)]));
      final other = ReceiveStockTransferUseCase(h.db, h.repo, h.dispatcher);
      final res = await Future.wait([
        h.receive.execute(t.id, receivedByProduct: {'p1': 5}).then((_) => true,
            onError: (_) => false),
        other.execute(t.id, receivedByProduct: {'p1': 5}).then((_) => true,
            onError: (_) => false),
      ]);
      expect(res.where((e) => e).length, 1);
      expect(own('store_002', 'p1'), 5);
    });

    test('weird branchStocks keys / value types', () async {
      seed('store_001', 'p1', {
        'ĐT': '12',
        'TB': null,
        'weird': 'abc',
        ' store_003 ': 4,
        'branch_9': 1.0
      });
      final t = await h.create.execute(draft([it('p1', 5)]));
      expect(own('store_001', 'p1'), 7);
      await h.receive.execute(t.id, receivedByProduct: {'p1': 5});
      expect(own('store_002', 'p1'), 5);
      expect(own('store_001', 'p1'), 7);
      final raw = h.db.read('stores/store_001/products/p1/branchStocks') as Map;
      expect(raw['store_001'], raw['branch_1']);
    });

    test('legacy scalar `stock` record can be transferred', () async {
      h.db.seed('stores/store_001/products/p1',
          {'id': 'p1', 'name': 'L', 'price': 10, 'costPrice': 5, 'stock': 9});
      final t = await h.create.execute(draft([it('p1', 4)]));
      expect(own('store_001', 'p1'), 5);
      await h.cancelTr.execute(t.id);
      expect(own('store_001', 'p1'), 9);
    });

    test('huge quantities (1e6+) are exact through transfer', () async {
      seed('store_001', 'p1', {'store_001': 7000000, 'store_002': 2000000});
      final t = await h.create.execute(draft([it('p1', 5500000)]));
      expect(own('store_001', 'p1'), 1500000);
      await h.receive.execute(t.id, receivedByProduct: {'p1': 5500000});
      expect(
          own('store_002', 'p1'), 5500000); // no target record: starts from 0
    });

    test('300-item slip: create, receive and cancel are fast (<3s each)',
        () async {
      for (var i = 0; i < 300; i++) {
        seed('store_001', 'p$i', {'store_001': 50, 'store_002': 0});
      }
      final items = [for (var i = 0; i < 300; i++) it('p$i', 5)];
      final sw = Stopwatch()..start();
      final t = await h.create.execute(draft(items));
      expect(sw.elapsedMilliseconds, lessThan(3000));
      sw.reset();
      final t2 = await h.create.execute(draft(items));
      await h.cancelTr.execute(t2.id);
      expect(sw.elapsedMilliseconds, lessThan(3000));
      sw.reset();
      await h.receive.execute(t.id,
          receivedByProduct: {for (var i = 0; i < 300; i++) 'p$i': 5});
      expect(sw.elapsedMilliseconds, lessThan(3000));
      expect(own('store_002', 'p299'), 5);
      expect(own('store_001', 'p299'), 45);
      expect(h.db.read(StockTransferRepository.pendingIndexPath('store_002')),
          anyOf(isNull, isEmpty));
    });
  });

  group('instant transfer service (stale Product snapshot)', () {
    test('uses RTDB stock, not the stale snapshot', () async {
      seed('store_001', 'p1', {'store_001': 10, 'store_002': 0});
      final stale = h.entityAt('store_001', 'p1')!;
      // 8 units sold after the snapshot was taken
      h.db.seed('stores/store_001/products/p1/branchStocks',
          {'store_001': 2, 'store_002': 0, 'branch_1': 2});
      final svc = InterStoreTransferService(h.db);
      expect(
          await svc.transferProduct(
              sourceStoreId: 'store_001',
              targetStoreId: 'store_002',
              product: stale,
              quantity: 5),
          isNotNull);
      expect(own('store_001', 'p1'), 2);
      expect(
          await svc.transferProduct(
              sourceStoreId: 'branch_1',
              targetStoreId: 'branch_2',
              product: stale,
              quantity: 2),
          isNull);
      expect(h.db.read('stores/branch_1'), isNull);
      expect(own('store_002', 'p1'), 2);
    });

    test('stock above 999,999 is not truncated', () async {
      seed('store_001', 'p1', {'store_001': 3000000, 'store_002': 0});
      final snap = h.entityAt('store_001', 'p1')!;
      expect(
          await InterStoreTransferService(h.db).transferProduct(
              sourceStoreId: 'store_001',
              targetStoreId: 'store_002',
              product: snap,
              quantity: 10),
          isNull);
      expect(own('store_001', 'p1'), 2999990);
    });
  });

  group('stock-in regressions', () {
    test('completing the same receipt twice does not add stock twice',
        () async {
      seed('store_001', 'p1', {'store_001': 5});
      h.productRepo.scope = 'store_001';
      final r = receipt('R1', 'store_001', [line('p1', 10, 100)]);
      await h.complete.execute(r);
      await expectLater(h.complete.execute(r), throwsA(isA<StateError>()));
      expect(own('store_001', 'p1'), 15);
    });

    test('two devices cancelling one receipt roll back once', () async {
      seed('store_001', 'p1', {'store_001': 5}, cost: 100);
      h.db.seed('shared_suppliers/S1',
          {'id': 'S1', 'name': 'S', 'currentDebt': 0.0, 'totalPurchase': 0.0});
      h.productRepo.scope = 'store_001';
      final done = await h.complete.execute(receipt(
          'R1', 'store_001', [line('p1', 10, 100)],
          supplier: 'S1', paid: 0));
      final res = await Future.wait([
        h.cancelIn
            .execute(
                storeId: 'store_001',
                receipt: done,
                reason: 'x',
                cancelledBy: 'a')
            .then((_) => true, onError: (_) => false),
        h.cancelIn
            .execute(
                storeId: 'store_001',
                receipt: done,
                reason: 'y',
                cancelledBy: 'b')
            .then((_) => true, onError: (_) => false),
      ]);
      expect(res.where((e) => e).length, 1);
      expect(own('store_001', 'p1'), 5);
      expect(h.db.read('shared_suppliers/S1/currentDebt'), 0);
    });

    test('failed write releases the receipt so a retry succeeds', () async {
      seed('store_001', 'p1', {'store_001': 5});
      h.productRepo.scope = 'store_001';
      final r = receipt('R1', 'store_001', [line('p1', 10, 100)]);
      h.db.failNextUpdate = true;
      await expectLater(h.complete.execute(r), throwsA(anything));
      expect(own('store_001', 'p1'), 5);
      await h.complete.execute(r);
      expect(own('store_001', 'p1'), 15);
    });

    test(
        'alias store id does not create stores/branch_x nodes or stub products',
        () async {
      seed('store_002', 'p1', {'store_002': 5});
      h.productRepo.scope = 'store_002';
      final done = await h.complete
          .execute(receipt('R1', 'branch_2', [line('p1', 3, 10)]));
      expect(done.storeId, 'store_002');
      expect(h.db.read('stores/branch_1'), isNull);
      expect(h.db.read('stores/branch_2'), isNull);
      expect(h.db.read('stores/store_001/products/p1'), isNull,
          reason:
              'must not create a nameless stub in a branch without the product');
      expect(h.notifRepo.added.single.storeId, 'store_002');
    });

    test('cancel does not clamp stock to 999,999', () async {
      seed('store_001', 'p1', {'store_001': 2000000});
      h.productRepo.scope = 'store_001';
      final done = await h.complete
          .execute(receipt('R1', 'store_001', [line('p1', 100, 1)]));
      await h.cancelIn.execute(
          storeId: 'store_001', receipt: done, reason: 'x', cancelledBy: 'a');
      expect(own('store_001', 'p1'), 2000000);
    });

    test('cancel restores cost 0 (rounding must not strand the receipt cost)',
        () async {
      seed('store_001', 'p1', {'store_001': 3}, cost: 0);
      h.productRepo.scope = 'store_001';
      final done = await h.complete
          .execute(receipt('R1', 'store_001', [line('p1', 7, 1234.5678)]));
      await h.cancelIn.execute(
          storeId: 'store_001', receipt: done, reason: 'x', cancelledBy: 'a');
      expect(h.entityAt('store_001', 'p1')!.costPrice, closeTo(0, 1e-9));
    });

    test('stock-in at one branch never clobbers another branch\'s own stock',
        () async {
      // store_003 holds a stale view of store_001; stock-in at store_003 must
      // not write that stale value into store_001's record.
      seed(
          'store_001', 'p1', {'store_001': 82, 'store_002': 0, 'store_003': 0});
      seed('store_003', 'p1', {'store_001': 0, 'store_002': 0, 'store_003': 6});
      h.productRepo.scope = 'store_003';
      await h.complete.execute(receipt('R1', 'store_003', [line('p1', 4, 10)]));
      expect(own('store_001', 'p1'), 82);
      expect(own('store_003', 'p1'), 10);
    });

    test('staff-visible notification bodies never contain money (1e15 totals)',
        () async {
      seed('store_001', 'p1', {'store_001': 1});
      h.productRepo.scope = 'store_001';
      await h.complete
          .execute(receipt('R1', 'store_001', [line('p1', 1000000, 1e9)]));
      h.checkNotifications(1, 'huge stock-in');
      expect(h.violations, isEmpty);
    });
  });
}
