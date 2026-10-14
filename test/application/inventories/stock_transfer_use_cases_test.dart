import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/stock_transfer_use_cases.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/stock_transfer.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../../support/fake_rtdb.dart';

class _FakeNotifRepo implements NotificationRepository {
  final List<NotificationItem> added = [];
  @override
  Future<void> addNotification(NotificationItem n) async => added.add(n);
  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {}
  @override
  Future<void> markAllAsRead(String storeId) async {}
  @override
  Future<void> markAsRead(
      {required String storeId, required String id}) async {}
  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
          {int limit = 50}) =>
      Stream.value(added);
}

void main() {
  const src = 'store_001';
  const dst = 'store_002';
  const user = UserAccount(
      username: 'u1', displayName: 'Khánh Đăng', role: 'admin', storeId: src);

  late FakeRtdb db;
  late FakeStockTransferRepository repo;
  late _FakeNotifRepo notifRepo;
  late NotificationDispatcher dispatcher;

  Map<String, dynamic> productMap(String id, Map<String, int> stocks) => {
        'id': id,
        'name': 'SP $id',
        'code': 'C$id',
        'price': 500.0,
        'costPrice': 300.0,
        'category': 'cat',
        'branchStocks': stocks,
      };

  void seedProduct(String store, String id, Map<String, int> stocks) =>
      db.seed('stores/$store/products/$id', productMap(id, stocks));

  int stockOf(String store, String id) {
    final v = db.read('stores/$store/products/$id');
    if (v is! Map) return -1;
    return ProductModel.fromMap(v, store).toEntity().stockInBranch(store);
  }

  StockTransfer draft(List<StockTransferItem> items,
          {String from = src, String to = dst}) =>
      StockTransfer(
        id: '',
        code: '',
        status: StockTransferStatus.draft,
        sourceStoreId: from,
        sourceStoreName: 'CN Gửi',
        targetStoreId: to,
        targetStoreName: 'CN Nhận',
        items: items,
        createdAt: DateTime(2026, 1, 1),
      );

  StockTransferItem item(String id, int qty) => StockTransferItem(
      productId: id, name: 'SP $id', code: 'C$id', quantity: qty);

  CreateStockTransferUseCase creator() =>
      CreateStockTransferUseCase(db, repo, dispatcher);
  ReceiveStockTransferUseCase receiver() =>
      ReceiveStockTransferUseCase(db, repo, dispatcher);

  setUp(() {
    db = FakeRtdb();
    repo = FakeStockTransferRepository(db);
    notifRepo = _FakeNotifRepo();
    dispatcher = NotificationDispatcher(notifRepo);
    seedProduct(src, 'p1', {src: 10, dst: 0});
    seedProduct(src, 'p2', {src: 5, dst: 0});
  });

  group('applyStoreStock', () {
    test('clamps negative to 0 and syncs aliases for store_002', () {
      final m = applyStoreStock({'store_001': 4}, dst, -3);
      expect(m['store_002'], 0);
      expect(m['branch_2'], 0);
      expect(m['store_001'], 4);
    });
  });

  group('CreateStockTransferUseCase', () {
    test('multi-item: deducts source, writes in-transit doc, export tx',
        () async {
      final t = await creator()
          .execute(draft([item('p1', 3), item('p2', 2)]), user: user);

      expect(t.code, 'TRF000001');
      expect(t.isInTransit, true);
      expect(stockOf(src, 'p1'), 7);
      expect(stockOf(src, 'p2'), 3);

      final saved = await repo.getById(t.id);
      expect(saved!.status, StockTransferStatus.inTransit);
      expect(saved.totalQuantity, 5);
      expect(saved.items.every((i) => i.receivedQuantity == 0), true);
      expect(saved.items.first.unitPrice, 300); // cost price snapshot

      final txs = db.read('stores/$src/inventory_transactions') as Map;
      expect(txs.length, 2);
      expect(txs.values.every((v) => v['type'] == 'export'), true);
      expect(txs.values.every((v) => v['transferCode'] == 'TRF000001'), true);
    });

    test('does NOT touch target stock while in transit', () async {
      seedProduct(dst, 'p1', {src: 10, dst: 4});
      await creator().execute(draft([item('p1', 3)]), user: user);
      expect(stockOf(dst, 'p1'), 4);
      expect(db.read('stores/$dst/inventory_transactions'), isNull);
    });

    test('notifies BOTH stores, without prices in the body', () async {
      await creator().execute(draft([item('p1', 3)]), user: user);
      expect(notifRepo.added.length, 2);
      expect(notifRepo.added.map((n) => n.storeId).toSet(), {src, dst});
      for (final n in notifRepo.added) {
        expect(n.type, NotificationType.stockTransfer);
        expect(n.targetRoute, 'transfer_detail');
        expect(n.title, contains('TRF000001'));
        expect(RegExp(r'\d[\d.,]*\s?đ').hasMatch(n.body), false);
      }
    });

    test('rejects same store (and alias of same store)', () async {
      expect(() => creator().execute(draft([item('p1', 1)], to: src)),
          throwsA(isA<StockTransferException>()));
      expect(() => creator().execute(draft([item('p1', 1)], to: 'branch_1')),
          throwsA(isA<StockTransferException>()));
    });

    test('rejects empty items, zero qty, empty store ids', () async {
      expect(() => creator().execute(draft([])),
          throwsA(isA<StockTransferException>()));
      expect(() => creator().execute(draft([item('p1', 0)])),
          throwsA(isA<StockTransferException>()));
      expect(() => creator().execute(draft([item('p1', 1)], to: '')),
          throwsA(isA<StockTransferException>()));
    });

    test('insufficient stock aborts whole slip atomically', () async {
      await expectLater(
          creator().execute(draft([item('p1', 3), item('p2', 99)])),
          throwsA(isA<StockTransferException>()));
      expect(stockOf(src, 'p1'), 10, reason: 'no partial deduction');
      expect(db.updateCalls, 0);
      expect(notifRepo.added, isEmpty);
    });

    test('unknown product is rejected', () async {
      await expectLater(creator().execute(draft([item('nope', 1)])),
          throwsA(isA<StockTransferException>()));
    });

    test('notification failure never breaks the transfer', () async {
      final failing = NotificationDispatcher(_ThrowingNotifRepo());
      final t = await CreateStockTransferUseCase(db, repo, failing)
          .execute(draft([item('p1', 1)]), user: user);
      expect(t.isInTransit, true);
      expect(stockOf(src, 'p1'), 9);
    });
  });

  group('ReceiveStockTransferUseCase', () {
    Future<StockTransfer> create2() =>
        creator().execute(draft([item('p1', 2), item('p2', 4)]), user: user);

    test('full receive credits target by sent quantities', () async {
      final t = await create2();
      notifRepo.added.clear();
      final done = await receiver()
          .execute(t.id, receivedByProduct: {'p1': 2, 'p2': 4}, user: user);

      expect(done.isReceived, true);
      expect(done.receivedSummary, '6/6');
      expect(stockOf(dst, 'p1'), 2);
      expect(stockOf(dst, 'p2'), 4);
      final imports = (db.read('stores/$dst/inventory_transactions') as Map)
          .values
          .where((v) => v['type'] == 'import');
      expect(imports.length, 2);
    });

    test('partial receive (2 sent, 1 received) credits only 1', () async {
      final t = await create2();
      final done = await receiver().execute(t.id,
          receivedByProduct: {'p1': 1, 'p2': 4},
          receiveNote: ' thiếu 1 ',
          user: user);
      expect(stockOf(dst, 'p1'), 1);
      expect(done.items.first.receivedQuantity, 1);
      expect(done.receiveNote, 'thiếu 1');
      expect(done.totalReceivedQuantity, 5);
      // shortfall is NOT auto-refunded to source
      expect(stockOf(src, 'p1'), 8);
    });

    test('zero received for an item writes no import for it', () async {
      final t = await create2();
      await receiver().execute(t.id, receivedByProduct: {'p1': 0, 'p2': 4});
      expect(db.read('stores/$dst/products/p1')?['branchStocks']?[dst] ?? 0, 0);
      final txs = (db.read('stores/$dst/inventory_transactions') as Map);
      expect(txs.length, 1);
    });

    test('over-receive is clamped to quantity sent; negatives to 0', () async {
      final t = await create2();
      final done = await receiver()
          .execute(t.id, receivedByProduct: {'p1': 99, 'p2': -5});
      expect(done.items[0].receivedQuantity, 2);
      expect(done.items[1].receivedQuantity, 0);
      expect(stockOf(dst, 'p1'), 2);
    });

    test('adds to existing target stock', () async {
      seedProduct(dst, 'p1', {src: 8, dst: 5});
      final t = await creator().execute(draft([item('p1', 2)]), user: user);
      await receiver().execute(t.id, receivedByProduct: {'p1': 2});
      expect(stockOf(dst, 'p1'), 7);
    });

    test('creates the product at target when missing', () async {
      final t = await creator().execute(draft([item('p1', 2)]), user: user);
      expect(db.read('stores/$dst/products/p1'), isNull);
      await receiver().execute(t.id, receivedByProduct: {'p1': 2});
      expect(db.read('stores/$dst/products/p1'), isNotNull);
      expect(stockOf(dst, 'p1'), 2);
    });

    test('notifies both stores when received', () async {
      final t = await create2();
      notifRepo.added.clear();
      await receiver()
          .execute(t.id, receivedByProduct: {'p1': 1, 'p2': 4}, user: user);
      expect(notifRepo.added.length, 2);
      expect(notifRepo.added.map((n) => n.storeId).toSet(), {src, dst});
      expect(notifRepo.added.first.title, contains('Nhận chuyển hàng'));
      expect(notifRepo.added.first.body, contains('5/6'));
    });

    test('cannot receive twice / unknown / draft', () async {
      final t = await create2();
      await receiver().execute(t.id, receivedByProduct: {'p1': 2, 'p2': 4});
      await expectLater(receiver().execute(t.id, receivedByProduct: {'p1': 2}),
          throwsA(isA<StockTransferException>()));
      expect(stockOf(dst, 'p1'), 2, reason: 'no double credit');
      await expectLater(receiver().execute('missing', receivedByProduct: {}),
          throwsA(isA<StockTransferException>()));
    });
  });

  group('Race conditions & money integrity', () {
    test('double receive (two devices) credits target exactly once', () async {
      final t = await creator().execute(draft([item('p1', 3)]), user: user);
      final results = await Future.wait([
        receiver()
            .execute(t.id, receivedByProduct: {'p1': 3}, user: user)
            .then((_) => 'ok')
            .catchError((_) => 'rejected'),
        receiver()
            .execute(t.id, receivedByProduct: {'p1': 3}, user: user)
            .then((_) => 'ok')
            .catchError((_) => 'rejected'),
      ]);
      expect(results.where((r) => r == 'ok').length, 1);
      expect(stockOf(dst, 'p1'), 3, reason: 'never double credit');
    });

    test('receive and cancel racing: exactly one wins, stock consistent',
        () async {
      final t = await creator().execute(draft([item('p1', 4)]), user: user);
      final results = await Future.wait([
        receiver()
            .execute(t.id, receivedByProduct: {'p1': 4})
            .then((_) => 'receive')
            .catchError((_) => 'x'),
        CancelStockTransferUseCase(db, repo, null)
            .execute(t.id)
            .then((_) => 'cancel')
            .catchError((_) => 'x'),
      ]);
      expect(results.where((r) => r != 'x').length, 1);
      final src1 = stockOf(src, 'p1');
      final dst1 = stockOf(dst, 'p1');
      // total units in the system never changes (10): no loss, no duplication
      expect(src1 + (dst1 < 0 ? 0 : dst1), 10);
    });

    test('double cancel restores source stock once', () async {
      final t = await creator().execute(draft([item('p1', 4)]), user: user);
      await Future.wait([
        CancelStockTransferUseCase(db, repo, null)
            .execute(t.id)
            .catchError((_) {}),
        CancelStockTransferUseCase(db, repo, null)
            .execute(t.id)
            .catchError((_) {}),
      ]);
      expect(stockOf(src, 'p1'), 10);
    });

    test('same draft sent twice only deducts once', () async {
      final saved = await SaveStockTransferDraftUseCase(db, repo, null)
          .execute(draft([item('p1', 3)]));
      final r = await Future.wait([
        creator()
            .execute(saved, user: user)
            .then((_) => 'ok')
            .catchError((_) => 'x'),
        creator()
            .execute(saved, user: user)
            .then((_) => 'ok')
            .catchError((_) => 'x'),
      ]);
      expect(r.where((e) => e == 'ok').length, 1);
      expect(stockOf(src, 'p1'), 7);
    });

    test('failed write releases the claim so receive can be retried', () async {
      final t = await creator().execute(draft([item('p1', 3)]), user: user);
      db.failNextUpdate = true;
      await expectLater(receiver().execute(t.id, receivedByProduct: {'p1': 3}),
          throwsA(anything));
      expect(
          (db.read('stock_transfers/${t.id}') as Map)['status'], 'in_transit');
      final done = await receiver().execute(t.id, receivedByProduct: {'p1': 3});
      expect(done.isReceived, true);
      expect(stockOf(dst, 'p1'), 3);
    });

    test('value math: sent/received value and fractional cost price', () async {
      db.seed('stores/$src/products/f1', {
        ...productMap('f1', {src: 10, dst: 0}),
        'costPrice': 1234.5,
      });
      final t = await creator().execute(draft([item('f1', 3)]), user: user);
      expect(t.totalValue, 3703.5);
      final done = await receiver().execute(t.id, receivedByProduct: {'f1': 1});
      expect(done.totalReceivedValue, 1234.5);
      expect(done.totalValue, 3703.5, reason: 'sent value is never rewritten');
    });

    test('unit price snapshot ignores client-supplied price', () async {
      final tampered = draft([
        StockTransferItem(
            productId: 'p1', name: 'x', code: 'x', unitPrice: 1, quantity: 1)
      ]);
      final t = await creator().execute(tampered, user: user);
      expect(t.items.first.unitPrice, 300, reason: 'server cost price wins');
    });

    test('inventory is conserved across create+partial receive', () async {
      final t = await creator().execute(draft([item('p1', 5)]), user: user);
      await receiver().execute(t.id, receivedByProduct: {'p1': 3});
      // 10 -> source 5, target 3, 2 units "lost in transit" (documented)
      expect(stockOf(src, 'p1'), 5);
      expect(stockOf(dst, 'p1'), 3);
    });
  });

  group('Pending-incoming index (bandwidth: badge reads ids only)', () {
    int pending(String store) {
      final v = db.read('stock_transfer_pending/$store');
      return v is Map ? v.length : 0;
    }

    test('create adds target index entry; receive removes it', () async {
      final t = await creator().execute(draft([item('p1', 1)]), user: user);
      expect(pending(dst), 1);
      expect(pending(src), 0);
      expect(await repo.watchPendingIncomingCount(dst).first, 1);
      await receiver().execute(t.id, receivedByProduct: {'p1': 1});
      expect(pending(dst), 0);
      expect(await repo.watchPendingIncomingCount(dst).first, 0);
    });

    test('cancel removes the index entry; draft never adds one', () async {
      final d = await SaveStockTransferDraftUseCase(db, repo, null)
          .execute(draft([item('p1', 1)]));
      expect(pending(dst), 0);
      final t = await creator().execute(d, user: user);
      expect(pending(dst), 1);
      await CancelStockTransferUseCase(db, repo, null).execute(t.id);
      expect(pending(dst), 0);
    });

    test('failed receive keeps the slip pending', () async {
      final t = await creator().execute(draft([item('p1', 1)]), user: user);
      db.failNextUpdate = true;
      await expectLater(
          receiver().execute(t.id, receivedByProduct: {'p1': 1}),
          throwsA(anything));
      expect(pending(dst), 1);
    });

    test('several slips are counted independently', () async {
      await creator().execute(draft([item('p1', 1)]), user: user);
      await creator().execute(draft([item('p2', 1)]), user: user);
      expect(pending(dst), 2);
    });
  });

  group('Item images', () {
    test('url image is stored on the slip, base64 image is not', () async {
      db.seed('stores/$src/products/img1', {
        ...productMap('img1', {src: 5, dst: 0}),
        'imageUrl': 'https://cdn/x.png',
      });
      db.seed('stores/$src/products/img2', {
        ...productMap('img2', {src: 5, dst: 0}),
        'imageUrl': 'data:image/png;base64,AAAA',
      });
      final t = await creator()
          .execute(draft([item('img1', 1), item('img2', 1)]), user: user);
      final saved = await repo.getById(t.id);
      expect(saved!.items[0].imageUrl, 'https://cdn/x.png');
      expect(saved.items[1].imageUrl, isNull);
      expect(db.read('stock_transfers/${t.id}').toString(),
          isNot(contains('base64')));
    });
  });

  group('Draft & Cancel', () {
    test('draft saves without changing stock or notifying', () async {
      final saved = await SaveStockTransferDraftUseCase(db, repo, null)
          .execute(draft([item('p1', 3)]));
      expect(saved.isDraft, true);
      expect(saved.id, isNotEmpty);
      expect(stockOf(src, 'p1'), 10);
      expect(notifRepo.added, isEmpty);
      await expectLater(
          SaveStockTransferDraftUseCase(db, repo, null).execute(draft([])),
          throwsA(isA<StockTransferException>()));
    });

    test('draft can be completed later (keeps same id)', () async {
      final saved = await SaveStockTransferDraftUseCase(db, repo, null)
          .execute(draft([item('p1', 3)]));
      final t = await creator().execute(saved, user: user);
      expect(t.id, saved.id);
      expect(t.code, startsWith('TRF'));
      expect(stockOf(src, 'p1'), 7);
    });

    test('cancel in-transit restores source stock', () async {
      final t = await creator().execute(draft([item('p1', 3)]), user: user);
      expect(stockOf(src, 'p1'), 7);
      await CancelStockTransferUseCase(db, repo, null).execute(t.id);
      expect(stockOf(src, 'p1'), 10);
      final c = await repo.getById(t.id);
      expect(c!.status, StockTransferStatus.cancelled);
    });

    test('cancel is rejected once received', () async {
      final t = await creator().execute(draft([item('p1', 3)]), user: user);
      await receiver().execute(t.id, receivedByProduct: {'p1': 3});
      await expectLater(
          CancelStockTransferUseCase(db, repo, null).execute(t.id),
          throwsA(isA<StockTransferException>()));
      expect(stockOf(src, 'p1'), 7);
    });

    test('cancelled slip can no longer be received', () async {
      final t = await creator().execute(draft([item('p1', 3)]), user: user);
      await CancelStockTransferUseCase(db, repo, null).execute(t.id);
      await expectLater(receiver().execute(t.id, receivedByProduct: {'p1': 3}),
          throwsA(isA<StockTransferException>()));
      expect(stockOf(dst, 'p1'), -1);
    });
  });
}

class _ThrowingNotifRepo extends _FakeNotifRepo {
  @override
  Future<void> addNotification(NotificationItem n) async =>
      throw Exception('boom');
}
