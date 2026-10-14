import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';
import 'package:stores/presentation/orders/controllers/invoices_filter_controller.dart';
import 'package:stores/presentation/orders/pages/create_order_page.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/orders/pages/pos_payment_page.dart';
import 'package:stores/presentation/orders/widgets/cancel_invoice_dialog.dart';
import 'package:stores/presentation/orders/widgets/debt_collection_dialog.dart';
import 'package:stores/presentation/orders/widgets/draft_orders_bottom_sheet.dart';
import 'package:stores/presentation/orders/widgets/invoice_detail_bottom_sheet.dart';
import 'package:stores/presentation/orders/widgets/return_order_bottom_sheet.dart';
import 'package:stores/presentation/orders/widgets/return_order_detail_bottom_sheet.dart';

class _Auth extends StateNotifier<UserAccount?> implements AuthNotifier {
  _Auth(super.state);
  @override
  Future<String?> login(String u, String p) async => null;
  @override
  Future<void> logout() async => state = null;
}

class _Customers extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _Customers(this._list);
  final List<Customer> _list;
  @override
  Future<List<Customer>> build() async => _list;
  @override
  Future<void> refresh() async => state = AsyncValue.data(_list);
}

const _admin = UserAccount(
    username: 'a', displayName: 'Admin', role: 'admin', storeId: 'store_001');
const _staff = UserAccount(
    username: 's',
    displayName: 'Nhân viên bán hàng có tên rất dài để thử nghiệm',
    role: 'nhanvien',
    storeId: 'store_001');

const _longName =
    'Bộ bàn ăn bên oval mặt nguyên tấm cực kỳ dài - 8 ghế bọc da cao cấp nhập khẩu màu nâu đậm';
const _longCustomer =
    'Nguyễn Thị Thanh Thảo Nguyên Phương Anh - Công ty TNHH Nội thất Thành phố Hồ Chí Minh';
const _huge = 123456789000.0;

const _customer = Customer(
  id: 'c1',
  name: _longCustomer,
  phone: '0901234567',
  email: 'khach.hang.ten.rat.dai@vi-du-ten-mien-dai.example.com',
  address:
      'Số 123/45/6 Đường Nguyễn Văn Linh, Phường Tân Phong, Quận 7, TP HCM',
  purchases: [],
  currentDebt: _huge,
);

const _config = StorePaymentConfig(
  storeId: 'store_001',
  storeName: 'Đông Thắng Store',
  address: '123 ĐT',
  phone: '0900000000',
  bankName: 'MBBank',
  bankId: 'mbbank',
  accountNo: '999988887777',
  accountName: 'TEST STORE',
  footerNote: 'Hẹn gặp lại',
);

Product _product(int i, {bool long = true}) => Product(
      id: 'p$i',
      name: i % 2 == 0 && long ? '$_longName $i' : 'Sản phẩm $i',
      code: 'MA-$i-RAT-DAI-DE-KIEM-TRA',
      price: _huge,
      costPrice: 1000,
      branchStocks: const {'store_001': 999999},
      category: 'Danh mục có tên khá dài',
      allowSale: true,
    );

Order _order(int n,
    {int lines = 3,
    String status = 'completed',
    bool debt = true,
    DateTime? at}) {
  final when = at ?? DateTime.now().subtract(Duration(minutes: n));
  return Order(
    id: 'HD${(100000 + n).toString()}',
    customerId: 'c1',
    customerName: _longCustomer,
    customerPhone: '0901234567',
    createdAt: when,
    items: [
      for (var i = 0; i < lines; i++)
        OrderItem(
          productId: 'p$i',
          productName: i % 2 == 0 ? '$_longName $i' : 'Sản phẩm $i',
          quantity: 1000000,
          price: _huge,
          originalPrice: _huge,
          discount: 5,
          isDiscountPercent: true,
          note: 'Ghi chú sản phẩm khá dài để kiểm tra việc xuống dòng',
          warrantyMonths: 12,
          purchaseDate: when,
        ),
    ],
    total: _huge * 1000,
    amountPaid: debt ? 1000 : _huge * 1000,
    debtAmount: debt ? _huge : 0,
    status: status,
    storeId: 'store_001',
    note: 'Ghi chú đơn hàng rất dài ' * 5,
    createdByName: _staff.displayName,
    cancelReason: status == 'cancelled' ? 'Khách đổi ý ' * 10 : null,
    cancelledAt: status == 'cancelled' ? when : null,
    cancelledByName: status == 'cancelled' ? _staff.displayName : null,
  );
}

enum _Mode { normal, empty, error }

List<Override> _overrides(UserAccount user,
    {_Mode mode = _Mode.normal, List<Order>? orders, List<Order>? drafts}) {
  final products = mode == _Mode.empty
      ? <Product>[]
      : [for (var i = 0; i < 120; i++) _product(i)];
  return [
    authProvider.overrideWith((ref) => _Auth(user)),
    currentStoreIdProvider.overrideWith((ref) => 'store_001'),
    selectedPOSBranchProvider.overrideWith((ref) => 'store_001'),
    storePaymentConfigProvider.overrideWithValue(_config),
    productListProvider.overrideWith((ref) => mode == _Mode.error
        ? Stream<List<Product>>.error('boom')
        : Stream.value(products)),
    categoryListProvider.overrideWith((ref) => Stream.value(const [
          Category(id: 'a', name: 'Danh mục có tên khá dài'),
          Category(id: 'b', name: 'Phòng khách rất rộng lớn và sang trọng'),
        ])),
    accountsListProvider.overrideWith((ref) => Stream.value([_admin, _staff])),
    allBranchesOrdersByDateRangeProvider.overrideWith((ref, range) =>
        mode == _Mode.error
            ? Stream<List<Order>>.error('boom')
            : Stream.value(mode == _Mode.empty ? <Order>[] : (orders ?? []))),
    posDraftOrdersProvider.overrideWith(
        (ref) => Stream.value(mode == _Mode.empty ? [] : (drafts ?? []))),
    customerListNotifierProvider.overrideWith(() => _Customers([_customer])),
  ];
}

Widget _app(Widget home, List<Override> overrides, double scale,
    {ProviderContainer? container}) {
  final app = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('vi'),
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  );
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: app);
  }
  return ProviderScope(key: UniqueKey(), overrides: overrides, child: app);
}

/// Host that shows a sheet/dialog on button tap.
Widget _launcher(void Function(BuildContext) open) => Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            key: const Key('launch'),
            onPressed: () => open(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    );

const _screens = <String, Size>{
  '320x568': Size(320, 568),
  '360x640': Size(360, 640),
  '412x915': Size(412, 915),
  '768x1024': Size(768, 1024),
  '1280x800': Size(1280, 800),
};

typedef _Build = Widget Function(
    UserAccount user, double scale, _Mode mode, ProviderContainer? c);

class _Case {
  _Case(this.name, this.build,
      {this.launch = false,
      this.modes = const [_Mode.normal],
      this.cart = 0,
      this.after});
  final String name;
  final _Build build;
  final bool launch;
  final List<_Mode> modes;
  final int cart;

  /// Extra interaction run after the screen settled (taps, typing...).
  final Future<void> Function(WidgetTester tester)? after;
}

void main() {
  final orders = [
    for (var i = 0; i < 120; i++)
      _order(i,
          lines: i == 0 ? 120 : 3,
          debt: i % 2 == 0,
          status: i % 7 == 3
              ? 'cancelled'
              : (i % 11 == 5 ? 'returned' : 'completed'))
  ];
  final bigOrder = _order(1, lines: 120);
  final debtOrder = _order(2, lines: 3);
  final ret = ReturnOrder(
    id: 'R1',
    orderId: bigOrder.id,
    customerId: 'c1',
    customerName: _longCustomer,
    storeId: 'store_001',
    createdAt: DateTime.now(),
    items: [
      for (var i = 0; i < 100; i++)
        ReturnOrderItem(
            productId: 'p$i',
            productName: '$_longName $i',
            price: _huge,
            quantity: 1000000)
    ],
    totalReturnAmount: _huge * 1000,
    debtDeducted: _huge,
    cashRefunded: _huge,
    reason: 'Lý do trả hàng rất dài ' * 8,
    createdByName: _staff.displayName,
  );

  final cases = <_Case>[
    _Case('POSPage', (u, s, m, c) => const POSPage(),
        modes: _Mode.values, cart: 100),
    _Case(
        'POSCheckoutPage',
        (u, s, m, c) => const POSCheckoutPage(
            initialCustomer: _customer, initialNote: 'Ghi chú rất dài'),
        cart: 120),
    _Case(
        'POSCheckoutPage empty cart', (u, s, m, c) => const POSCheckoutPage()),
    _Case(
        'POSPaymentPage',
        (u, s, m, c) => const POSPaymentPage(
            initialCustomer: _customer, initialNote: 'Ghi chú rất dài'),
        cart: 120),
    _Case('POSCheckoutPage edit item sheet',
        (u, s, m, c) => const POSCheckoutPage(initialCustomer: _customer),
        cart: 5, after: (tester) async {
      final item = find.textContaining('Bộ bàn ăn').first;
      await tester.ensureVisible(item);
      await tester.tap(item, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    }),
    _Case(
        'AddCustomerDialog',
        (u, s, m, c) => _launcher((ctx) => showDialog<void>(
            context: ctx, builder: (_) => const AddCustomerDialog())),
        launch: true,
        after: (tester) async => expect(find.byType(Dialog), findsOneWidget)),
    _Case('POSPaymentPage split modal',
        (u, s, m, c) => const POSPaymentPage(initialCustomer: _customer),
        cart: 5, after: (tester) async {
      final more = find.byIcon(Icons.more_horiz);
      expect(more, findsWidgets);
      await tester.ensureVisible(more.first);
      await tester.tap(more.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Thanh toán kết hợp'), findsWidgets);
    }),
    _Case('POSPaymentPage transfer tab',
        (u, s, m, c) => const POSPaymentPage(initialCustomer: _customer),
        cart: 5, after: (tester) async {
      final tab = find.text('Chuyển\nkhoản');
      expect(tab, findsWidgets);
      await tester.ensureVisible(tab.first);
      await tester.tap(tab.first, warnIfMissed: false);
      await tester.pumpAndSettle();
    }),
    _Case('POSPage search', (u, s, m, c) => const POSPage(), cart: 3,
        after: (tester) async {
      await tester.enterText(find.byType(TextField).first, 'khong-co-ket-qua');
      await tester.pumpAndSettle();
    }),
    _Case('InvoicesPage', (u, s, m, c) => const InvoicesPage(),
        modes: _Mode.values, after: (tester) async {
      final toggle = find.byKey(const Key('invoices_toggle_expand_all_button'));
      if (toggle.evaluate().isNotEmpty) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      final field = find.byType(TextField);
      if (field.evaluate().isNotEmpty) {
        await tester.enterText(field.first, 'nguyen');
        await tester.pumpAndSettle();
      }
    }),
    _Case('InvoicesPage detail sheet', (u, s, m, c) => const InvoicesPage(),
        after: (tester) async {
      final tile = find.textContaining('HD100000');
      expect(tile, findsWidgets);
      await tester.tap(tile.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(CustomScrollView), findsWidgets,
          reason: 'detail sheet should be open');
      // scroll the sheet to the bottom: the financial summary is built lazily
      await tester.drag(
          find.byType(CustomScrollView).last, const Offset(0, -300000),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
          find.text('Tổng tiền thanh toán').evaluate().length +
              find.text('Khách cần trả').evaluate().length,
          greaterThan(0),
          reason: 'financial summary reachable by scrolling');
    }),
    _Case('InvoicesPage returned filter', (u, s, m, c) => const InvoicesPage(),
        after: (tester) async {
      final container =
          ProviderScope.containerOf(tester.element(find.byType(InvoicesPage)));
      container.read(invoicesFilterProvider.notifier).setStatus('returned');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('return_kpi_summary_card')), findsOneWidget);
    }),
    _Case('InvoicesPage date sheet', (u, s, m, c) => const InvoicesPage(),
        after: (tester) async {
      await tester.tap(find.byIcon(Icons.arrow_drop_down).first,
          warnIfMissed: false);
      await tester.pumpAndSettle();
    }),
    _Case('InvoicesPage branch sheet', (u, s, m, c) => const InvoicesPage(),
        after: (tester) async {
      await tester.tap(find.byIcon(Icons.arrow_drop_down).at(1),
          warnIfMissed: false);
      await tester.pumpAndSettle();
    }),
    _Case('CreateOrderPage',
        (u, s, m, c) => const CreateOrderPage(selectedCustomerId: 'c1')),
    _Case(
        'InvoiceDetailBottomSheet',
        (u, s, m, c) => _launcher((ctx) => InvoiceDetailBottomSheet.show(
            ctx, bigOrder,
            customerName: _longCustomer)),
        launch: true),
    _Case(
        'InvoiceDetailBottomSheet cancelled',
        (u, s, m, c) => _launcher((ctx) => InvoiceDetailBottomSheet.show(
            ctx, _order(3, status: 'cancelled'),
            customerName: _longCustomer)),
        launch: true),
    _Case(
        'ReturnOrderBottomSheet',
        (u, s, m, c) => _launcher((ctx) => ReturnOrderBottomSheet.show(ctx,
            order: bigOrder, customer: _customer)),
        launch: true),
    _Case(
        'ReturnOrderDetailBottomSheet',
        (u, s, m, c) => _launcher((ctx) => ReturnOrderDetailBottomSheet.show(
            ctx,
            order: bigOrder,
            returnOrder: ret,
            customer: _customer)),
        launch: true),
    _Case(
        'DebtCollectionDialog',
        (u, s, m, c) => _launcher((ctx) => DebtCollectionDialog.show(ctx,
            order: debtOrder, customer: _customer, remainingDebt: _huge)),
        launch: true),
    _Case(
        'CancelInvoiceDialog',
        (u, s, m, c) => _launcher((ctx) => CancelInvoiceDialog.show(ctx,
            order: debtOrder, customer: _customer)),
        launch: true),
    _Case(
        'DraftOrdersBottomSheet',
        (u, s, m, c) => _launcher((ctx) => showModalBottomSheet<void>(
            context: ctx,
            isScrollControlled: true,
            builder: (_) => const DraftOrdersBottomSheet())),
        launch: true,
        modes: [_Mode.normal, _Mode.empty]),
  ];

  for (final c in cases) {
    for (final mode in c.modes) {
      for (final e in _screens.entries) {
        for (final scale in [1.0, 1.8]) {
          for (final user in [_admin, _staff]) {
            testWidgets(
                '${c.name} [${mode.name}] ${e.key} x$scale ${user.role}',
                (tester) async {
              tester.view.physicalSize = e.value;
              tester.view.devicePixelRatio = 1.0;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);

              final errors = <String>[];
              final prevOnError = FlutterError.onError;
              FlutterError.onError = (d) {
                final text = d.toDiagnosticsNode().toStringDeep();
                final loc = RegExp(r'lib/presentation/[^\s:]+:\d+')
                    .allMatches(text)
                    .map((m) => m.group(0))
                    .toSet()
                    .join(', ');
                errors.add('${d.exceptionAsString().split('\n').first} @ $loc');
              };
              addTearDown(() => FlutterError.onError = prevOnError);

              final ov = _overrides(user, mode: mode, orders: orders, drafts: [
                for (var i = 0; i < 30; i++) _order(i, status: 'draft')
              ]);
              ProviderContainer? container;
              if (c.cart > 0) {
                container = ProviderContainer(overrides: ov);
                addTearDown(container.dispose);
                final n = container.read(cartProvider.notifier);
                for (var i = 0; i < c.cart; i++) {
                  n.addToCart(_product(i), quantity: 1000000);
                }
              }
              await tester.pumpWidget(_app(
                  c.build(user, scale, mode, container), ov, scale,
                  container: container));
              await tester.pumpAndSettle();
              if (c.launch) {
                await tester.tap(find.byKey(const Key('launch')));
                await tester.pumpAndSettle();
              }
              tester.takeException();
              FlutterError.onError = prevOnError;
              expect(errors.toSet().toList(), isEmpty);
            });
          }
        }
      }
    }
  }

  group('lazy building (jank guards)', () {
    void bigScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    final order300 = _order(7, lines: 300);

    testWidgets('InvoiceDetailBottomSheet with 300 lines builds lazily',
        (tester) async {
      bigScreen(tester);
      final ov = _overrides(_admin);
      await tester.pumpWidget(_app(
          _launcher((ctx) => InvoiceDetailBottomSheet.show(ctx, order300,
              customerName: _longCustomer)),
          ov,
          1.0));
      await tester.tap(find.byKey(const Key('launch')));
      await tester.pumpAndSettle();
      final built = find.byType(ProductImageThumbnail).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(60), reason: 'built $built of 300 lines');
      // scrolling to the bottom still reaches the financial summary
      await tester.drag(
          find.byType(CustomScrollView).last, const Offset(0, -200000));
      await tester.pumpAndSettle();
      expect(find.text('Khách phải trả:'), findsOneWidget);
    });

    testWidgets('ReturnOrderBottomSheet with 300 lines builds lazily',
        (tester) async {
      bigScreen(tester);
      final ov = _overrides(_admin);
      await tester.pumpWidget(_app(
          _launcher((ctx) => ReturnOrderBottomSheet.show(ctx,
              order: order300, customer: _customer)),
          ov,
          1.0));
      await tester.tap(find.byKey(const Key('launch')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('increment_return_p150')), findsNothing,
          reason: 'far-away lines must not be built');
      expect(find.byKey(const Key('increment_return_p0')), findsOneWidget);
    });

    testWidgets('ReturnOrderDetailBottomSheet with 300 lines builds lazily',
        (tester) async {
      bigScreen(tester);
      final ov = _overrides(_admin);
      final big = ReturnOrder(
        id: 'R9',
        orderId: order300.id,
        customerId: 'c1',
        storeId: 'store_001',
        createdAt: DateTime.now(),
        items: [
          for (var i = 0; i < 300; i++)
            ReturnOrderItem(
                productId: 'p$i',
                productName: 'Sản phẩm trả số $i',
                price: 1000,
                quantity: 1)
        ],
        totalReturnAmount: 300000,
      );
      await tester.pumpWidget(_app(
          _launcher((ctx) => ReturnOrderDetailBottomSheet.show(ctx,
              order: order300, returnOrder: big, customer: _customer)),
          ov,
          1.0));
      await tester.tap(find.byKey(const Key('launch')));
      await tester.pumpAndSettle();
      expect(find.text('Sản phẩm trả số 0'), findsOneWidget);
      expect(find.text('Sản phẩm trả số 250'), findsNothing);
    });

    testWidgets('InvoicesPage detail sheet with 300 lines builds lazily',
        (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(_app(const InvoicesPage(),
          _overrides(_admin, orders: [_order(0, lines: 300)]), 1.0));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('HD100000').first);
      await tester.pumpAndSettle();
      expect(find.text('Sản phẩm 299'), findsNothing,
          reason: 'far-away lines must not be built');
      expect(find.textContaining('Bộ bàn ăn'), findsWidgets);
      await tester.drag(
          find.byType(CustomScrollView).last, const Offset(0, -300000));
      await tester.pumpAndSettle();
      expect(
          find.text('Tổng tiền thanh toán').evaluate().length +
              find.text('Khách cần trả').evaluate().length,
          greaterThan(0),
          reason: 'financial summary reachable by scrolling');
    });

    testWidgets('InvoicesPage renders cards and builds 300 invoices lazily',
        (tester) async {
      bigScreen(tester);
      final many = [for (var i = 0; i < 300; i++) _order(i, lines: 2)];
      await tester.pumpWidget(
          _app(const InvoicesPage(), _overrides(_admin, orders: many), 1.0));
      await tester.pumpAndSettle();
      final first = find.textContaining('HD100000');
      expect(first, findsWidgets);
      expect(find.textContaining('HD100299'), findsNothing,
          reason: 'last invoice must not be built before scrolling');
      final built = find.byType(Card).evaluate().length;
      expect(built, lessThan(60), reason: 'built $built cards of 300');
    });
  });
}
