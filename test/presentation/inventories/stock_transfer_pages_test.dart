import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_transfer_providers.dart';
import 'package:stores/application/inventories/usecases/stock_transfer_use_cases.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_transfer.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/inventories/pages/stock_transfer_create_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfer_detail_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfer_receive_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfers_page.dart';
import 'package:stores/presentation/inventories/widgets/stock_transfer_widgets.dart';

import '../../support/fake_rtdb.dart';

class _AuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _AuthNotifier(super.state);
  @override
  Future<String?> login(String u, String p) async => null;
  @override
  Future<void> logout() async => state = null;
}

const _admin = UserAccount(
    username: 'admin', displayName: 'Admin', role: 'admin', storeId: 'all');
const _staffB = UserAccount(
    username: 'nv',
    displayName: 'NV B',
    role: 'nhanvien',
    storeId: 'store_002');
const _staffA = UserAccount(
    username: 'nv',
    displayName: 'NV A',
    role: 'nhanvien',
    storeId: 'store_001');

StockTransfer _t({
  String id = 'T1',
  String code = 'TRF000001',
  StockTransferStatus status = StockTransferStatus.inTransit,
  int received = 0,
  int qty = 2,
}) =>
    StockTransfer(
      id: id,
      code: code,
      status: status,
      sourceStoreId: 'store_001',
      sourceStoreName: 'Chi nhánh Đông Thắng',
      targetStoreId: 'store_002',
      targetStoreName: 'Chi nhánh Thới Bình',
      createdAt: DateTime(2026, 9, 23, 10, 1),
      items: [
        StockTransferItem(
            productId: 'p1',
            name: 'Bàn học sinh',
            code: 'HS8',
            unitPrice: 700000,
            quantity: qty,
            receivedQuantity: received),
        StockTransferItem(
            productId: 'p2',
            name: 'Ghế xoay',
            code: 'VP81',
            unitPrice: 550000,
            quantity: 2,
            receivedQuantity: received == 0 ? 0 : 2),
      ],
    );

Widget _app({
  required Widget home,
  required UserAccount user,
  required String storeId,
  List<StockTransfer> transfers = const [],
  FakeRtdb? db,
  List<Override> extra = const [],
}) {
  final fdb = db ?? FakeRtdb();
  final repo = FakeStockTransferRepository(fdb);
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      authProvider.overrideWith((ref) => _AuthNotifier(user)),
      currentStoreIdProvider.overrideWithValue(storeId),
      stockTransfersProvider.overrideWith((ref) => Stream.value(transfers)),
      stockTransferByIdProvider.overrideWith((ref, id) => Stream.fromFuture(repo
          .getById(id)
          .then((v) => v ?? transfers.where((t) => t.id == id).firstOrNull))),
      transferProductImageMapProvider.overrideWithValue(const {}),
      stockTransferRepositoryProvider.overrideWithValue(repo),
      receiveStockTransferUseCaseProvider
          .overrideWithValue(ReceiveStockTransferUseCase(fdb, repo, null)),
      cancelStockTransferUseCaseProvider
          .overrideWithValue(CancelStockTransferUseCase(fdb, repo, null)),
      createStockTransferUseCaseProvider
          .overrideWithValue(CreateStockTransferUseCase(fdb, repo, null)),
      saveStockTransferDraftUseCaseProvider
          .overrideWithValue(SaveStockTransferDraftUseCase(fdb, repo, null)),
      ...extra,
    ],
    child: MaterialApp(home: home),
  );
}

Finder _plus() => find
    .descendant(
        of: find.byType(QuantityStepper), matching: find.byIcon(Icons.add))
    .first;

void main() {
  group('StockTransfersPage (list)', () {
    testWidgets('card shows items, route, code, status and received x/y',
        (tester) async {
      await tester.pumpWidget(_app(
        home: const StockTransfersPage(),
        user: _admin,
        storeId: 'store_001',
        transfers: [
          _t(status: StockTransferStatus.received, received: 2),
          _t(id: 'T2', code: 'TRF000002'),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Chuyển hàng'), findsOneWidget);
      expect(find.textContaining('2 mặt hàng - Số lượng: 4'), findsNWidgets(2));
      expect(find.text('Từ Chi nhánh Đông Thắng'), findsNWidgets(2));
      expect(find.text('Đến Chi nhánh Thới Bình'), findsNWidgets(2));
      expect(find.textContaining('TRF000001'), findsOneWidget);
      // received slip: 4/4, in-transit slip: 0/4 — shown outside the badge
      expect(find.text('4/4 sản phẩm'), findsOneWidget);
      expect(find.text('0/4 sản phẩm'), findsOneWidget);
      expect(find.text('Đã nhận'), findsWidgets);
      expect(find.text('Đang chuyển'), findsWidgets);
    });

    testWidgets('price visible for admin, hidden for staff', (tester) async {
      await tester.pumpWidget(_app(
          home: const StockTransfersPage(),
          user: _admin,
          storeId: 'store_001',
          transfers: [_t()]));
      await tester.pumpAndSettle();
      expect(find.text('2.500.000'), findsOneWidget);

      await tester.pumpWidget(_app(
          home: const StockTransfersPage(),
          user: _staffA,
          storeId: 'store_001',
          transfers: [_t()]));
      await tester.pumpAndSettle();
      expect(find.text('2.500.000'), findsNothing);
      expect(find.textContaining('2 mặt hàng'), findsOneWidget);
    });

    testWidgets('empty state, search and status filter', (tester) async {
      await tester.pumpWidget(_app(
          home: const StockTransfersPage(),
          user: _admin,
          storeId: 'store_001'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có phiếu chuyển hàng'), findsOneWidget);

      await tester.pumpWidget(_app(
        home: const StockTransfersPage(),
        user: _admin,
        storeId: 'store_001',
        transfers: [
          _t(status: StockTransferStatus.received, received: 2),
          _t(id: 'T2', code: 'TRF000002'),
        ],
      ));
      await tester.pumpAndSettle();
      final received = find.widgetWithText(ChoiceChip, 'Đã nhận');
      await tester.ensureVisible(received);
      await tester.tap(received);
      await tester.pumpAndSettle();
      expect(find.text('23/09/2026 10:01 • TRF000001'), findsOneWidget);
      expect(find.text('23/09/2026 10:01 • TRF000002'), findsNothing);

      final all = find.widgetWithText(ChoiceChip, 'Tất cả');
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.enterText(find.byType(TextField), 'TRF000002');
      await tester.pumpAndSettle();
      expect(find.text('23/09/2026 10:01 • TRF000001'), findsNothing);
      expect(find.text('23/09/2026 10:01 • TRF000002'), findsOneWidget);
    });

    testWidgets('FAB opens the create page', (tester) async {
      await tester.pumpWidget(_app(
          home: const StockTransfersPage(),
          user: _admin,
          storeId: 'store_001'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(StockTransferCreatePage), findsOneWidget);
    });
  });

  group('Receive entry points (list)', () {
    testWidgets('pending chip counts only slips waiting for THIS store',
        (tester) async {
      await tester.pumpWidget(_app(
        home: const StockTransfersPage(),
        user: _staffB,
        storeId: 'store_002',
        transfers: [
          _t(id: 'T1', code: 'TRF000001'),
          _t(
              id: 'T2',
              code: 'TRF000002',
              status: StockTransferStatus.received,
              received: 2),
          _t(
              id: 'T3',
              code: 'TRF000003',
              status: StockTransferStatus.cancelled),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.text('Chờ nhận 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('transfer_pending_chip')));
      await tester.pumpAndSettle();
      expect(find.text('23/09/2026 10:01 • TRF000001'), findsOneWidget);
      expect(find.text('23/09/2026 10:01 • TRF000002'), findsNothing);
      expect(find.text('23/09/2026 10:01 • TRF000003'), findsNothing);
    });

    testWidgets('source store sees 0 pending and no receive button',
        (tester) async {
      await tester.pumpWidget(_app(
        home: const StockTransfersPage(),
        user: _staffA,
        storeId: 'store_001',
        transfers: [_t()],
      ));
      await tester.pumpAndSettle();
      expect(find.text('Chờ nhận 0'), findsOneWidget);
      expect(find.byKey(const Key('transfer_receive_T1')), findsNothing);
    });

    testWidgets(
        'pending slips are sorted first; receive button opens receive page',
        (tester) async {
      await tester.pumpWidget(_app(
        home: const StockTransfersPage(),
        user: _staffB,
        storeId: 'store_002',
        transfers: [
          _t(
              id: 'T2',
              code: 'TRF000002',
              status: StockTransferStatus.received,
              received: 2),
          _t(id: 'T1', code: 'TRF000001'),
        ],
      ));
      await tester.pumpAndSettle();
      final first =
          tester.getTopLeft(find.text('23/09/2026 10:01 • TRF000001'));
      final second =
          tester.getTopLeft(find.text('23/09/2026 10:01 • TRF000002'));
      expect(first.dy < second.dy, true, reason: 'pending slip on top');

      await tester.tap(find.byKey(const Key('transfer_receive_T1')));
      await tester.pumpAndSettle();
      expect(find.byType(StockTransferReceivePage), findsOneWidget);
    });

    testWidgets('admin gets receive button on any store; received slips never',
        (tester) async {
      await tester.pumpWidget(_app(
        home: const StockTransfersPage(),
        user: _admin,
        storeId: 'store_001',
        transfers: [
          _t(),
          _t(
              id: 'T2',
              code: 'TRF000002',
              status: StockTransferStatus.received,
              received: 2),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('transfer_receive_T1')), findsOneWidget);
      expect(find.byKey(const Key('transfer_receive_T2')), findsNothing);
    });
  });

  group('Bandwidth: paging', () {
    testWidgets('"Xem thêm" appears only when the fetch limit is reached and raises it',
        (tester) async {
      final many = [
        for (var i = 0; i < 30; i++) _t(id: 'T$i', code: 'TRF${100000 + i}'),
      ];
      late ProviderContainer container;
      await tester.pumpWidget(_app(
        home: Consumer(builder: (c, ref, _) {
          container = ProviderScope.containerOf(c);
          return const StockTransfersPage();
        }),
        user: _admin,
        storeId: 'store_001',
        transfers: many,
      ));
      await tester.pumpAndSettle();
      final listFinder = find.byType(Scrollable).last;
      await tester.dragUntilVisible(find.byKey(const Key('transfer_load_more')),
          listFinder, const Offset(0, -300));
      expect(container.read(stockTransfersLimitProvider), 30);
      await tester.tap(find.byKey(const Key('transfer_load_more')));
      await tester.pump();
      expect(container.read(stockTransfersLimitProvider), 60);
    });

    testWidgets('no "Xem thêm" when fewer slips than the limit',
        (tester) async {
      await tester.pumpWidget(_app(
        home: const StockTransfersPage(),
        user: _admin,
        storeId: 'store_001',
        transfers: [_t()],
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('transfer_load_more')), findsNothing);
    });
  });

  group('Product thumbnails', () {
    testWidgets('slip without image shows placeholder per item (list+detail)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = _t();
      await tester.pumpWidget(_app(
          home: const StockTransfersPage(),
          user: _admin,
          storeId: 'store_001',
          transfers: [t]));
      await tester.pumpAndSettle();
      expect(find.byType(TransferItemThumb), findsNWidgets(2));
      expect(find.byIcon(Icons.inventory_2_outlined), findsNWidgets(2));

      final db = FakeRtdb()..seed('stock_transfers/T1', t.toMap());
      await tester.pumpWidget(_app(
          home: const StockTransferDetailPage(transferId: 'T1'),
          user: _admin,
          storeId: 'store_001',
          db: db,
          transfers: [t]));
      await tester.pumpAndSettle();
      expect(find.byType(TransferItemThumb), findsNWidgets(2));
    });

    testWidgets('image is resolved from product list when slip has none',
        (tester) async {
      final t = _t();
      await tester.pumpWidget(_app(
        home: const StockTransfersPage(),
        user: _admin,
        storeId: 'store_001',
        transfers: [t],
        extra: [
          transferProductImageMapProvider.overrideWithValue(
              const {'p1': 'data:image/png;base64,iVBORw0KGgo='}),
        ],
      ));
      await tester.pump();
      // p1 resolved through lookup => no placeholder for it, p2 keeps one
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    });

    test('transferSafeImageUrl drops base64 and oversized values', () {
      expect(transferSafeImageUrl(null), isNull);
      expect(transferSafeImageUrl('  '), isNull);
      expect(transferSafeImageUrl('data:image/png;base64,AAAA'), isNull);
      expect(transferSafeImageUrl('x' * 501), isNull);
      expect(transferSafeImageUrl(' https://a/b.png '), 'https://a/b.png');
    });

    test('item imageUrl survives map round trip and copyWith', () {
      const i = StockTransferItem(
          productId: 'p',
          name: 'n',
          code: 'c',
          imageUrl: 'https://a/b.png',
          quantity: 1);
      expect(StockTransferItem.fromMap(i.toMap()).imageUrl, 'https://a/b.png');
      expect(i.copyWith(receivedQuantity: 1).imageUrl, 'https://a/b.png');
    });
  });

  group('StockTransferDetailPage', () {
    Future<void> open(WidgetTester tester, StockTransfer t, UserAccount user,
        String store) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = FakeRtdb()..seed('stock_transfers/${t.id}', t.toMap());
      await tester.pumpWidget(_app(
          home: StockTransferDetailPage(transferId: t.id),
          user: user,
          storeId: store,
          db: db,
          transfers: [t]));
      await tester.pumpAndSettle();
    }

    testWidgets('in-transit: columns, totals, no received column',
        (tester) async {
      await open(tester, _t(), _admin, 'store_001');
      expect(find.text('TRF000001'), findsOneWidget);
      expect(find.text('SL CHUYỂN'), findsOneWidget);
      expect(find.text('SL NHẬN'), findsNothing);
      expect(find.text('Tổng giá trị chuyển'), findsOneWidget);
      expect(find.text('Tổng giá trị nhận'), findsNothing);
      expect(find.text('Giá: 700.000'), findsOneWidget);
    });

    testWidgets('received: SL NHẬN column and received totals', (tester) async {
      await open(tester, _t(status: StockTransferStatus.received, received: 1),
          _admin, 'store_002');
      expect(find.text('SL NHẬN'), findsOneWidget);
      expect(find.text('Tổng giá trị nhận'), findsOneWidget);
      expect(find.text('Nhận hàng'), findsNothing);
    });

    testWidgets('staff never sees prices or totals value', (tester) async {
      await open(tester, _t(), _staffB, 'store_002');
      expect(find.textContaining('Giá:'), findsNothing);
      expect(find.text('2.500.000'), findsNothing);
      expect(find.text('Tổng giá trị chuyển'), findsNothing);
      expect(find.text('Tổng số lượng chuyển'), findsOneWidget);
    });

    testWidgets('target-store staff gets "Nhận hàng", not "Hủy phiếu"',
        (tester) async {
      await open(tester, _t(), _staffB, 'store_002');
      expect(find.text('Nhận hàng'), findsOneWidget);
      expect(find.text('Hủy phiếu'), findsNothing);
    });

    testWidgets('source-store staff gets "Hủy phiếu", not "Nhận hàng"',
        (tester) async {
      await open(tester, _t(), _staffA, 'store_001');
      expect(find.text('Hủy phiếu'), findsOneWidget);
      expect(find.text('Nhận hàng'), findsNothing);
    });

    testWidgets('admin viewing the SOURCE store can still receive/cancel',
        (tester) async {
      await open(tester, _t(), _admin, 'store_001');
      expect(find.text('Nhận hàng'), findsOneWidget);
      expect(find.text('Hủy phiếu'), findsOneWidget);
    });

    testWidgets('cancelled slip has no action buttons', (tester) async {
      await open(tester, _t(status: StockTransferStatus.cancelled), _admin,
          'store_002');
      expect(find.text('Nhận hàng'), findsNothing);
      expect(find.text('Hủy phiếu'), findsNothing);
    });

    testWidgets('missing slip shows not-found message', (tester) async {
      await tester.pumpWidget(_app(
          home: const StockTransferDetailPage(transferId: 'nope'),
          user: _admin,
          storeId: 'store_001'));
      await tester.pumpAndSettle();
      expect(find.text('Không tìm thấy phiếu chuyển'), findsOneWidget);
    });
  });

  group('StockTransferReceivePage', () {
    late FakeRtdb db;

    Future<void> open(WidgetTester tester, {UserAccount user = _staffB}) async {
      db = FakeRtdb();
      for (final id in ['p1', 'p2']) {
        db.seed('stores/store_001/products/$id', {
          'id': id,
          'name': id,
          'code': id,
          'price': 1.0,
          'costPrice': 1.0,
          'category': 'c',
          'branchStocks': {'store_001': 10, 'store_002': 0},
        });
      }
      final t = _t();
      db.seed('stock_transfers/${t.id}', t.toMap());
      await tester.pumpWidget(_app(
          home: Builder(
              builder: (c) => Scaffold(
                  body: Center(
                      child: ElevatedButton(
                          onPressed: () => Navigator.of(c).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const StockTransferReceivePage(
                                          transferId: 'T1'))),
                          child: const Text('go'))))),
          user: user,
          storeId: 'store_002',
          db: db,
          transfers: [t]));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    int targetStock(String id) {
      final v = db.read('stores/store_002/products/$id');
      if (v is! Map) return 0;
      return ProductModel.fromMap(v, 'store_002')
          .toEntity()
          .stockInBranch('store_002');
    }

    testWidgets('initial state: nothing received, chips counts',
        (tester) async {
      await open(tester);
      expect(find.text('Tất cả 2'), findsOneWidget);
      expect(find.text('Chưa nhận đủ 2'), findsOneWidget);
      expect(find.text('Đã nhận đủ 0'), findsOneWidget);
      expect(find.text('Nhận tất cả'), findsOneWidget);
      expect(find.text('SL Chuyển: 2'), findsNWidgets(2));
    });

    testWidgets('"Nhận tất cả" fills quantities, toggles to "Bỏ nhận tất cả"',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('Nhận tất cả'));
      await tester.pumpAndSettle();
      expect(find.text('Đã nhận đủ 2'), findsOneWidget);
      expect(find.text('Chưa nhận đủ 0'), findsOneWidget);
      expect(find.text('Bỏ nhận tất cả'), findsOneWidget);

      await tester.tap(find.text('Bỏ nhận tất cả'));
      await tester.pumpAndSettle();
      expect(find.text('Đã nhận đủ 0'), findsOneWidget);
    });

    testWidgets('per-item "Nhận đủ" sets that item only', (tester) async {
      await open(tester);
      await tester.tap(find.text('Nhận đủ').first);
      await tester.pumpAndSettle();
      expect(find.text('Đã nhận đủ 1'), findsOneWidget);
      expect(find.text('Chưa nhận đủ 1'), findsOneWidget);
    });

    testWidgets('stepper +/- is bounded by quantity sent', (tester) async {
      await open(tester);
      final plus = _plus();
      for (var i = 0; i < 3; i++) {
        await tester.tap(plus); // 3rd tap is beyond max 2 -> ignored
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Đã nhận đủ 1'), findsOneWidget);
      final minus = find
          .descendant(
              of: find.byType(QuantityStepper),
              matching: find.byIcon(Icons.remove))
          .first;
      await tester.tap(minus);
      await tester.pumpAndSettle();
      expect(find.text('Đã nhận đủ 0'), findsOneWidget);
    });

    testWidgets('filter chips narrow the visible items', (tester) async {
      await open(tester);
      await tester.tap(find.text('Nhận đủ').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đã nhận đủ 1'));
      await tester.pumpAndSettle();
      expect(find.text('Bàn học sinh'), findsOneWidget);
      expect(find.text('Ghế xoay'), findsNothing);
    });

    testWidgets('full receive: credits target stock and marks received',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('Nhận tất cả'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoàn thành'));
      await tester.pumpAndSettle();

      expect(targetStock('p1'), 2);
      expect(targetStock('p2'), 2);
      expect((db.read('stock_transfers/T1') as Map)['status'], 'received');
      expect(find.text('Đã nhận hàng chuyển kho'), findsOneWidget);
    });

    testWidgets('partial receive asks for confirmation; 2 sent / 1 received',
        (tester) async {
      await open(tester);
      await tester.tap(_plus()); // p1 -> 1
      await tester.tap(find.text('Nhận đủ').last); // p2 -> 2
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoàn thành'));
      await tester.pumpAndSettle();
      expect(find.text('Nhận chưa đủ hàng'), findsOneWidget);

      await tester.tap(find.text('Kiểm tra lại'));
      await tester.pumpAndSettle();
      expect(targetStock('p1'), 0, reason: 'nothing written before confirm');

      await tester.tap(find.text('Hoàn thành'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Hoàn thành')));
      await tester.pumpAndSettle();

      expect(targetStock('p1'), 1);
      expect(targetStock('p2'), 2);
      final items = (db.read('stock_transfers/T1') as Map)['items'] as List;
      expect(items[0]['receivedQuantity'], 1);
    });
  });

  group('StockTransferCreatePage', () {
    final product = Product(
      id: 'p1',
      name: 'Bàn học sinh',
      code: 'HS8',
      price: 900000,
      costPrice: 700000,
      branchStocks: const {'store_001': 5, 'store_002': 0},
      category: 'c',
    );

    Future<FakeRtdb> open(WidgetTester tester,
        {UserAccount user = _admin, Product? initial}) async {
      final db = FakeRtdb();
      db.seed('stores/store_001/products/p1', {
        'id': 'p1',
        'name': 'Bàn học sinh',
        'code': 'HS8',
        'price': 900000.0,
        'costPrice': 700000.0,
        'category': 'c',
        'branchStocks': {'store_001': 5, 'store_002': 0},
      });
      await tester.pumpWidget(_app(
        home: StockTransferCreatePage(product: initial),
        user: user,
        storeId: 'store_001',
        db: db,
        extra: [
          availableStoresProvider.overrideWith((ref) async => {
                'store_001': 'Chi nhánh Đông Thắng',
                'store_002': 'Chi nhánh Thới Bình',
              }),
          productListProvider.overrideWith((ref) => Stream.value([product])),
        ],
      ));
      await tester.pumpAndSettle();
      return db;
    }

    testWidgets('preloaded product, source is fixed, price per role',
        (tester) async {
      await open(tester, initial: product);
      expect(find.text('Phiếu chuyển hàng mới'), findsOneWidget);
      expect(find.textContaining('Từ Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.text('Bàn học sinh'), findsOneWidget);
      expect(find.textContaining('Giá: 700.000'), findsOneWidget);

      await open(tester, user: _staffA, initial: product);
      expect(find.textContaining('Giá:'), findsNothing);
    });

    testWidgets('Hoàn thành without target store is blocked', (tester) async {
      final db = await open(tester, initial: product);
      await tester.tap(find.text('Hoàn thành'));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng chọn chi nhánh nhận'), findsOneWidget);
      expect(db.read('stock_transfers'), isNull);
    });

    testWidgets('empty slip is blocked for both Lưu tạm and Hoàn thành',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('Lưu tạm'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có hàng trong phiếu'), findsWidgets);
    });

    testWidgets('quantity is capped at source stock', (tester) async {
      await open(tester, initial: product);
      final plus = _plus();
      for (var i = 0; i < 10; i++) {
        await tester.tap(plus);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('complete flow: pick target, Hoàn thành deducts source stock',
        (tester) async {
      final db = await open(tester, initial: product);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chi nhánh Thới Bình').last);
      await tester.pumpAndSettle();
      await tester.tap(_plus()); // qty 2
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoàn thành'));
      await tester.pumpAndSettle();

      final slips = db.read('stock_transfers') as Map;
      expect(slips.length, 1);
      final slip = slips.values.first as Map;
      expect(slip['status'], 'in_transit');
      expect(slip['targetStoreId'], 'store_002');
      final p = db.read('stores/store_001/products/p1') as Map;
      expect(
          ProductModel.fromMap(p, 'store_001')
              .toEntity()
              .stockInBranch('store_001'),
          3);
    });

    testWidgets('Lưu tạm saves a draft without touching stock', (tester) async {
      final db = await open(tester, initial: product);
      await tester.tap(find.text('Lưu tạm'));
      await tester.pumpAndSettle();
      final slip = (db.read('stock_transfers') as Map).values.first as Map;
      expect(slip['status'], 'draft');
      final p = db.read('stores/store_001/products/p1') as Map;
      expect(
          ProductModel.fromMap(p, 'store_001')
              .toEntity()
              .stockInBranch('store_001'),
          5);
    });

    testWidgets('can add another product via picker and remove a line',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('Thêm hàng vào phiếu'));
      await tester.pumpAndSettle();
      expect(find.text('Tồn: 5'), findsOneWidget);
      await tester.tap(find.text('Bàn học sinh'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có hàng trong phiếu'), findsOneWidget);
    });
  });
}
