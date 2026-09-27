import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/data/datasources/firebase/order_remote_data_source.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/data/repositories/order_repository_impl.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customer_transactions_page.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _MockOrderRemoteDataSource implements OrderRemoteDataSource {
  final Map<String, Map<String, dynamic>> orders = {};
  Map<String, dynamic>? lastWrittenMap;

  @override
  String get storeId => 'store_002';

  @override
  Future<void> create(String id, Map<String, dynamic> data) async {
    orders[id] = data;
    lastWrittenMap = data;
  }

  @override
  Future<void> update(String id, Map<String, dynamic> data) async {
    orders[id] = data;
    lastWrittenMap = data;
  }

  @override
  Future<void> delete(String id) async => orders.remove(id);

  @override
  Future<Map<String, dynamic>?> fetchById(String id) async => orders[id];

  @override
  Stream<List<Map<String, dynamic>>> watchAll() =>
      Stream.value(orders.values.toList());

  @override
  Stream<List<Map<String, dynamic>>> watchRecentOrders({int limit = 50}) =>
      Stream.value(orders.values.toList());

  @override
  Stream<List<Map<String, dynamic>>> watchByCustomer(String customerId) =>
      Stream.value(orders.values
          .where((m) => m['customerId'] == customerId)
          .toList());

  @override
  Stream<List<Map<String, dynamic>>> watchByDateRange(
          DateTime start, DateTime end) =>
      Stream.value(orders.values.toList());

  @override
  Future<List<Map<String, dynamic>>> fetchByDateRange(
          DateTime start, DateTime end) async =>
      orders.values.toList();

  @override
  Future<void> createReturn(String id, Map<String, dynamic> data) async {}

  @override
  Future<Map<String, dynamic>?> fetchReturnById(String id) async => null;

  @override
  Stream<List<Map<String, dynamic>>> watchReturnsByDateRange(
          DateTime start, DateTime end) =>
      Stream.value([]);

  @override
  Stream<List<Map<String, dynamic>>> watchReturnsByOrderId(String orderId) =>
      Stream.value([]);
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: child,
    ),
  );
}

void main() {
  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Khánh Đăng',
    role: 'admin',
    storeId: 'store_002',
  );

  group('Adversarial Reviewer Round 2: Cross-Module Deep Verification', () {
    test('1. OrderModel.fromMap itemless subtotal fallback prevents double discount deduction', () {
      // Map loaded without items (e.g. shallow order query), but with subtotal, total, and discount
      final itemlessMap = {
        'id': 'HD_ITEMLESS',
        'customerId': 'KH006900',
        'subtotal': 8500000.0,
        'total': 8300000.0, // Legacy net total
        'discount': 200000.0,
        'status': 'cancelled',
        'amountPaid': 0.0,
        'debtAmount': 8300000.0,
        'items': <dynamic>[],
      };

      final om = OrderModel.fromMap(itemlessMap);
      expect(om.total, equals(8500000.0),
          reason: 'Gross total must be 8.500.000đ even when items list is empty');
      expect(om.discount, equals(200000.0),
          reason: 'Discount must be 200.000đ');
      expect(om.debtAmount, equals(0.0),
          reason: 'Cancelled order in OrderModel must have debtAmount == 0.0');

      final serialized = om.toMap();
      expect(serialized['debtAmount'], equals(0.0),
          reason: 'Serialized toMap must strictly write 0.0 for debtAmount on cancelled orders');
    });

    test('2. Order.copyWith(status: "cancelled") automatically zeroes out debtAmount', () {
      final now = DateTime.now();
      final activeOrder = Order(
        id: 'HD_ACTIVE_DEBT',
        customerId: 'KH01',
        createdAt: now,
        items: const [],
        total: 10000000.0,
        discount: 1000000.0,
        amountPaid: 3000000.0,
        debtAmount: 6000000.0, // Active debt
        status: 'completed',
      );

      expect(activeOrder.remainingDebt, equals(6000000.0));
      expect(activeOrder.hasDebt, isTrue);

      // Calling copyWith with status = 'cancelled' without explicitly providing debtAmount: 0.0
      final cancelledOrder = activeOrder.copyWith(status: 'cancelled');
      expect(cancelledOrder.isCancelled, isTrue);
      expect(cancelledOrder.debtAmount, equals(0.0),
          reason: 'copyWith(status: "cancelled") must automatically zero out debtAmount');
      expect(cancelledOrder.remainingDebt, equals(0.0));
      expect(cancelledOrder.hasDebt, isFalse);
    });

    test('3. OrderRepositoryImpl._mapToModel strictly sanitizes debtAmount to 0.0 for cancelled orders', () async {
      final ds = _MockOrderRemoteDataSource();
      final repo = OrderRepositoryImpl(ds);

      final now = DateTime.now();
      // An order entity that somehow carried a non-zero debtAmount with cancelled status
      final orderWithStaleDebt = Order(
        id: 'HD_STALE_DEBT',
        customerId: 'KH01',
        createdAt: now,
        items: const [],
        total: 5000000.0,
        discount: 500000.0,
        amountPaid: 0.0,
        debtAmount: 4500000.0,
        status: 'cancelled',
      );

      await repo.update(orderWithStaleDebt);
      expect(ds.lastWrittenMap, isNotNull);
      expect(ds.lastWrittenMap!['debtAmount'], equals(0.0),
          reason: 'OrderRepositoryImpl must strictly write debtAmount: 0.0 to Firebase for cancelled orders');
    });

    test('4. overview_kpi_providers: paymentBreakdownProvider uses remainingDebt and does not count cancelled order debt', () async {
      final now = DateTime.now();
      final orders = [
        // Completed order with remaining debt 2M
        Order(
          id: 'O1',
          customerId: 'KH1',
          createdAt: now,
          items: const [],
          total: 5000000.0,
          discount: 1000000.0,
          amountPaid: 2000000.0,
          debtAmount: 2000000.0,
          paymentMethod: 'cash',
          status: 'completed',
        ),
        // Cancelled order that originally had 8.3M debt
        Order(
          id: 'O2',
          customerId: 'KH2',
          createdAt: now,
          items: const [],
          total: 8500000.0,
          discount: 200000.0,
          amountPaid: 0.0,
          debtAmount: 8300000.0,
          paymentMethod: 'cash',
          status: 'cancelled',
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          allBranchesOrdersByDateRangeProvider.overrideWith(
              (ref, range) => Stream.value(orders)),
        ],
      );
      addTearDown(container.dispose);

      final range = container.read(overviewCurrentDateRangeProvider);
      await container.read(allBranchesOrdersByDateRangeProvider(range).future);
      final breakdown = container.read(paymentBreakdownProvider).value;
      expect(breakdown, isNotNull);
      expect(breakdown!.debtAmount, equals(2000000.0),
          reason: 'Only active completed order debt (2M) must be included, NOT cancelled order debt (8.3M)');
      expect(breakdown.cashAmount, equals(2000000.0));
      expect(breakdown.totalAmount, equals(4000000.0),
          reason: 'Net total is 4M (5M total - 1M discount = 2M cash + 2M debt)');
    });

    testWidgets('5. CustomerTransactionsPage excludes cancelled HD013123 from total sales and shows Đã hủy badge with strikethrough', (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const customerAnhNghia = Customer(
        id: 'KH006900',
        name: 'Anh Nghĩa',
        phone: '0765029203',
        email: '',
        address: 'Bờ Bao - Kinh 5',
        purchases: [],
        currentDebt: 9300000.0,
        totalSales: 10700000.0,
        netSales: 10300000.0,
      );

      final date = DateTime(2026, 9, 1, 14, 29, 8);
      final customerOrders = [
        // Cancelled invoice HD013123: Gross 8.500.000, discount 200.000
        Order(
          id: 'HD013123',
          customerId: 'KH006900',
          customerName: 'Anh Nghĩa',
          createdAt: date,
          items: [
            OrderItem(
              productId: 'GL22',
              productName: 'Giường tây trụ thao lao (nhà) DÀY - 1m8',
              quantity: 1,
              price: 8500000.0,
              warrantyMonths: 0,
              purchaseDate: date,
            ),
          ],
          total: 8500000.0,
          discount: 200000.0,
          status: 'cancelled',
          amountPaid: 0.0,
          debtAmount: 0.0,
          paymentMethod: 'cash',
          storeId: 'store_002',
        ),
        // Active replacement invoice HD013123_01: Gross 10.700.000, discount 400.000, debt 9.300.000
        Order(
          id: 'HD013123_01',
          customerId: 'KH006900',
          customerName: 'Anh Nghĩa',
          createdAt: date,
          items: [
            OrderItem(
              productId: 'GL21',
              productName: 'Giường tây trụ thao lao (nhà) DÀY - 1m6',
              quantity: 1,
              price: 8100000.0,
              warrantyMonths: 0,
              purchaseDate: date,
            ),
            OrderItem(
              productId: 'VG8',
              productName: 'Giá võng gỗ thao lao - trụ',
              quantity: 1,
              price: 2600000.0,
              warrantyMonths: 0,
              purchaseDate: date,
            ),
          ],
          total: 10700000.0,
          discount: 400000.0,
          status: 'completed',
          amountPaid: 1000000.0,
          debtAmount: 9300000.0,
          paymentMethod: 'cash',
          storeId: 'store_002',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: customerAnhNghia),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider('KH006900').overrideWith(
                (ref) => Stream.value(customerOrders)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Top total sales bar and active order card both display 10.700.000 (active order only), NOT 19.200.000!
      expect(find.text('10.700.000'), findsNWidgets(2),
          reason: 'Total sales must exclude cancelled invoice HD013123 and equal 10.700.000đ (found on header and HD013123_01 card)');
      expect(find.text('19.200.000'), findsNothing,
          reason: 'Total sales must NEVER add cancelled invoice total (19.200.000đ is a phantom sum)');

      // Cancelled badge must be displayed on HD013123
      expect(find.text('Đã hủy'), findsOneWidget);

      // Verify that HD013123 total is struck through
      final cancelledTotalFinder = find.text('8.500.000');
      expect(cancelledTotalFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(cancelledTotalFinder);
      expect(textWidget.style?.decoration, equals(TextDecoration.lineThrough),
          reason: 'Cancelled order total must have lineThrough decoration');
    });
  });
}
