import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_transfer_providers.dart';
import 'package:stores/application/inventories/usecases/stock_transfer_use_cases.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_transfer.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/inventories/pages/stock_transfer_create_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfer_detail_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfer_receive_page.dart';
import 'package:stores/presentation/inventories/pages/stock_transfers_page.dart';

import '../../support/fake_rtdb.dart';

class _Auth extends StateNotifier<UserAccount?> implements AuthNotifier {
  _Auth(super.state);
  @override
  Future<String?> login(String u, String p) async => null;
  @override
  Future<void> logout() async => state = null;
}

const _admin = UserAccount(
    username: 'a', displayName: 'Admin', role: 'admin', storeId: 'all');
const _staff = UserAccount(
    username: 's', displayName: 'NV', role: 'nhanvien', storeId: 'store_002');

const _longName =
    'Bộ bàn ăn bên oval mặt nguyên tấm cực kỳ dài - 8 ghế bọc da cao cấp nhập khẩu màu nâu đậm';
const _longStore =
    'Chi nhánh Thành phố Hồ Chí Minh - Quận Bình Thạnh - Phường 25';

StockTransfer _slip(
    {int items = 3,
    StockTransferStatus status = StockTransferStatus.inTransit,
    int received = 0}) {
  return StockTransfer(
    id: 'T1',
    code: 'TRF000123',
    status: status,
    sourceStoreId: 'store_001',
    sourceStoreName: _longStore,
    targetStoreId: 'store_002',
    targetStoreName: 'Chi nhánh Thới Bình',
    createdAt: DateTime(2026, 9, 23, 10, 1),
    createdByName: 'Khánh Đăng',
    note: 'Ghi chú khá dài để kiểm tra việc xuống dòng trên màn hình rất nhỏ',
    items: [
      for (var i = 0; i < items; i++)
        StockTransferItem(
            productId: 'p$i',
            name: i == 0 ? _longName : 'Sản phẩm $i',
            code: 'MA-$i-RAT-DAI-DE-KIEM-TRA',
            unitPrice: 123456789,
            quantity: 1000000,
            receivedQuantity: received),
    ],
  );
}

Widget _host(Widget home, UserAccount user, StockTransfer slip,
    {double textScale = 1}) {
  final db = FakeRtdb()..seed('stock_transfers/${slip.id}', slip.toMap());
  final repo = FakeStockTransferRepository(db);
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      authProvider.overrideWith((ref) => _Auth(user)),
      currentStoreIdProvider.overrideWithValue('store_002'),
      stockTransfersProvider
          .overrideWith((ref) => Stream.value([slip, slip.copyWith(id: 'T2')])),
      stockTransferByIdProvider.overrideWith((ref, id) => Stream.value(slip)),
      stockTransferRepositoryProvider.overrideWithValue(repo),
      receiveStockTransferUseCaseProvider
          .overrideWithValue(ReceiveStockTransferUseCase(db, repo, null)),
      cancelStockTransferUseCaseProvider
          .overrideWithValue(CancelStockTransferUseCase(db, repo, null)),
      createStockTransferUseCaseProvider
          .overrideWithValue(CreateStockTransferUseCase(db, repo, null)),
      saveStockTransferDraftUseCaseProvider
          .overrideWithValue(SaveStockTransferDraftUseCase(db, repo, null)),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': _longStore,
            'store_002': 'Chi nhánh Thới Bình',
          }),
      productListProvider.overrideWith((ref) => Stream.value([
            Product(
              id: 'p0',
              name: _longName,
              code: 'MA-0-RAT-DAI-DE-KIEM-TRA',
              price: 1,
              costPrice: 123456789,
              branchStocks: const {'store_002': 999999},
              category: 'c',
            ),
          ])),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

const _screens = <String, Size>{
  'phone-small 320x568': Size(320, 568),
  'phone 360x640': Size(360, 640),
  'phone-large 412x915': Size(412, 915),
  'tablet 768x1024': Size(768, 1024),
  'desktop 1280x800': Size(1280, 800),
};

void main() {
  setUp(() {});
  final pages = <String, Widget Function()>{
    'list': () => const StockTransfersPage(),
    'detail': () => const StockTransferDetailPage(transferId: 'T1'),
    'receive': () => const StockTransferReceivePage(transferId: 'T1'),
    'create': () => StockTransferCreatePage(
          product: Product(
            id: 'p0',
            name: _longName,
            code: 'MA-0-RAT-DAI-DE-KIEM-TRA',
            price: 1,
            costPrice: 123456789,
            branchStocks: const {'store_002': 999999},
            category: 'c',
          ),
        ),
  };

  for (final entry in _screens.entries) {
    for (final scale in [1.0, 1.8]) {
      for (final page in pages.entries) {
        for (final user in [_admin, _staff]) {
          testWidgets(
              '${page.key} @ ${entry.key} x$scale as ${user.role}: no overflow/crash',
              (tester) async {
            tester.view.physicalSize = entry.value;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
                _host(page.value(), user, _slip(), textScale: scale));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }

  group('huge numbers & big slips', () {
    testWidgets('received slip with max quantities renders (no overflow)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(
          const StockTransferDetailPage(transferId: 'T1'),
          _admin,
          _slip(status: StockTransferStatus.received, received: 1000000),
          textScale: 1.5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 3 items * 1,000,000 * 123,456,789 = 370,370,367,000,000 (no int overflow)
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(
          find.text('370.370.367.000.000', skipOffstage: false), findsWidgets);
    });

    testWidgets('300-item slip builds lazily (not all rows at once)',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(
          const StockTransferDetailPage(transferId: 'T1'),
          _admin,
          _slip(items: 300)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sản phẩm ').evaluate().length, lessThan(40),
          reason: 'only visible rows should be built');
      await tester.pumpWidget(_host(
          const StockTransferReceivePage(transferId: 'T1'),
          _staff,
          _slip(items: 300)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sản phẩm ').evaluate().length, lessThan(40));
      expect(tester.takeException(), isNull);
    });

    testWidgets('receive "Nhận tất cả" on 300 items works and stays fast',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(
          const StockTransferReceivePage(transferId: 'T1'),
          _staff,
          _slip(items: 300)));
      await tester.pumpAndSettle();
      final sw = Stopwatch()..start();
      await tester.tap(find.text('Nhận tất cả'));
      await tester.pumpAndSettle();
      sw.stop();
      expect(find.text('Đã nhận đủ 300'), findsOneWidget);
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });

    testWidgets('keyboard open on tiny screen does not overflow create page',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets =
          const FakeViewPadding(bottom: 260); // soft keyboard
      addTearDown(tester.view.reset);
      await tester
          .pumpWidget(_host(const StockTransferCreatePage(), _admin, _slip()));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(find.text('Thêm hàng vào phiếu'),
          find.byType(ListView).first, const Offset(0, -80));
      await tester.tap(find.text('Thêm hàng vào phiếu'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });
  });
}
