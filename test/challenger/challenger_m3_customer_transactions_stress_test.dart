import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
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

Widget _buildStressTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Material(child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final currencyFormat = NumberFormat('#,###', 'vi_VN');

  const adminUser = UserAccount(
    username: 'admin_test',
    displayName: 'Quản trị viên Hệ thống',
    role: 'admin',
    storeId: 'store_001',
  );

  const defaultCustomer = Customer(
    id: 'CUST_STRESS_001',
    name: 'Khách hàng Thử nghiệm Tải cao',
    phone: '0901234567',
    email: 'stress_test@example.com',
    address: '123 Đường 3/2, Cần Thơ',
    purchases: [],
    totalSales: 0.0,
    currentDebt: 0.0,
  );

  final Map<String, String> fourStoresMap = {
    'store_001': 'Chi nhánh Đông Thắng',
    'store_002': 'Chi nhánh Thới Bình',
    'store_003': 'Chi nhánh Vĩnh Lộc',
    'store_004': 'Chi nhánh Cái Nước',
  };

  group('CHALLENGER STRESS SUITE 1: High Volume (100+ Orders across 4 Stores)',
      () {
    testWidgets(
        '120 orders distributed evenly across 4 stores render smoothly, accurate counts and sums',
        (tester) async {
      final List<Order> stressOrders = [];
      final storeIds = ['store_001', 'store_002', 'store_003', 'store_004'];

      double expectedGrandTotal = 0.0;
      final Map<String, double> expectedStoreTotals = {
        'store_001': 0.0,
        'store_002': 0.0,
        'store_003': 0.0,
        'store_004': 0.0,
      };

      final baseTime = DateTime(2026, 9, 1, 8, 0);

      for (int i = 1; i <= 120; i++) {
        final storeId = storeIds[(i - 1) % 4];
        final amount = 100000.0 * i;
        expectedGrandTotal += amount;
        expectedStoreTotals[storeId] =
            (expectedStoreTotals[storeId] ?? 0.0) + amount;

        stressOrders.add(
          Order(
            id: 'HD${i.toString().padLeft(4, '0')}',
            customerId: defaultCustomer.id,
            createdAt: baseTime.add(Duration(hours: i)),
            items: [
              OrderItem(
                productId: 'SP_$i',
                productName: 'Sản phẩm nội thất mã số #$i',
                quantity: 1,
                price: amount,
                warrantyMonths: 12,
                purchaseDate: baseTime.add(Duration(hours: i)),
              ),
            ],
            total: amount,
            storeId: storeId,
            createdByName: 'Nhân viên $storeId',
            paymentMethod: i % 2 == 0 ? 'cash' : 'transfer',
          ),
        );
      }

      await tester.pumpWidget(
        _buildStressTestApp(
          child: const CustomerTransactionsPage(customer: defaultCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider.overrideWith((ref) async => fourStoresMap),
            customerOrdersProvider(defaultCustomer.id).overrideWith(
              (ref) => Stream.value(stressOrders),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Check for clean render with zero unhandled exceptions
      expect(tester.takeException(), isNull);

      // Verify subheader count
      expect(find.text('120 giao dịch'), findsOneWidget);

      // Verify grand total sum in header
      expect(
          find.text(currencyFormat.format(expectedGrandTotal)), findsOneWidget);

      // Verify ChoiceChip counts
      expect(find.text('Tất cả chi nhánh (120)'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng (30)'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình (30)'), findsOneWidget);
      expect(find.text('Chi nhánh Vĩnh Lộc (30)'), findsOneWidget);
      expect(find.text('Chi nhánh Cái Nước (30)'), findsOneWidget);

      // Filter to store_003 (Vĩnh Lộc)
      final vlChip = find.byKey(const ValueKey('store_filter_store_003'));
      await tester.ensureVisible(vlChip);
      await tester.tap(vlChip);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('30 giao dịch'), findsOneWidget);
      expect(
          find.text(currencyFormat.format(expectedStoreTotals['store_003']!)),
          findsOneWidget);

      // Filter to store_004 (Cái Nước)
      final cnChip = find.byKey(const ValueKey('store_filter_store_004'));
      await tester.ensureVisible(cnChip);
      await tester.tap(cnChip);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('30 giao dịch'), findsOneWidget);
      expect(
          find.text(currencyFormat.format(expectedStoreTotals['store_004']!)),
          findsOneWidget);

      // Reset to All
      final allChip = find.byKey(const ValueKey('store_filter_all'));
      await tester.ensureVisible(allChip);
      await tester.tap(allChip);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('120 giao dịch'), findsOneWidget);
      expect(
          find.text(currencyFormat.format(expectedGrandTotal)), findsOneWidget);
    });
  });

  group('CHALLENGER STRESS SUITE 2: Rapid Switching & Concurrency Stress', () {
    testWidgets(
        'Rapidly alternating ChoiceChips while scrolling does not crash or corrupt UI state',
        (tester) async {
      final List<Order> stressOrders = [];
      final storeIds = ['store_001', 'store_002', 'store_003', 'store_004'];

      for (int i = 1; i <= 80; i++) {
        final storeId = storeIds[i % 4];
        stressOrders.add(
          Order(
            id: 'ORD$i',
            customerId: defaultCustomer.id,
            createdAt:
                DateTime(2026, 9, 1, 10, 0).add(Duration(minutes: i * 30)),
            items: [
              OrderItem(
                productId: 'P$i',
                productName: 'Mặt hàng $i',
                quantity: 1,
                price: 500000.0,
                warrantyMonths: 12,
                purchaseDate: DateTime(2026, 9, 1, 10, 0),
              ),
            ],
            total: 500000.0,
            storeId: storeId,
          ),
        );
      }

      await tester.pumpWidget(
        _buildStressTestApp(
          child: const CustomerTransactionsPage(customer: defaultCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider.overrideWith((ref) async => fourStoresMap),
            customerOrdersProvider(defaultCustomer.id).overrideWith(
              (ref) => Stream.value(stressOrders),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final chipKeys = [
        'store_filter_store_001',
        'store_filter_store_002',
        'store_filter_store_003',
        'store_filter_store_004',
        'store_filter_all',
      ];

      // Perform 25 rapid taps alternating across chips and scrolling the list
      for (int step = 0; step < 25; step++) {
        final targetKey = chipKeys[step % chipKeys.length];
        final chipFinder = find.byKey(ValueKey(targetKey));
        await tester.ensureVisible(chipFinder);
        await tester.tap(chipFinder);

        // Fling scroll the list every few steps to simulate user interaction
        if (step % 3 == 0) {
          final listFinder = find.byType(ListView);
          if (listFinder.evaluate().isNotEmpty) {
            await tester.fling(listFinder, const Offset(0, -200), 1000);
          }
        }
        await tester.pump(const Duration(milliseconds: 20));
      }

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('CHALLENGER STRESS SUITE 3: Extreme Boundary Cases', () {
    testWidgets(
        '0 orders: shows empty state cleanly under All and store filter',
        (tester) async {
      await tester.pumpWidget(
        _buildStressTestApp(
          child: const CustomerTransactionsPage(customer: defaultCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider.overrideWith((ref) async => fourStoresMap),
            customerOrdersProvider(defaultCustomer.id).overrideWith(
              (ref) => Stream.value([]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
      expect(find.text('Chưa có giao dịch nào'), findsOneWidget);
      expect(find.text('0 giao dịch'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      // Verify chips show (0)
      expect(find.text('Tất cả chi nhánh (0)'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng (0)'), findsOneWidget);

      // Tap store_001 chip when 0 orders
      final dtChip = find.byKey(const ValueKey('store_filter_store_001'));
      await tester.ensureVisible(dtChip);
      await tester.tap(dtChip);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('0 giao dịch'), findsOneWidget);
      expect(find.text('Chưa có giao dịch nào'), findsOneWidget);
    });

    testWidgets(
        'Single Store Exclusivity: 100 orders exclusively at store_001, other stores show 0',
        (tester) async {
      final List<Order> store1Orders = List.generate(
        100,
        (i) => Order(
          id: 'ST1_$i',
          customerId: defaultCustomer.id,
          createdAt: DateTime(2026, 9, 1).add(Duration(minutes: i)),
          items: [],
          total: 100000.0,
          storeId: 'store_001',
        ),
      );

      await tester.pumpWidget(
        _buildStressTestApp(
          child: const CustomerTransactionsPage(customer: defaultCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider.overrideWith((ref) async => fourStoresMap),
            customerOrdersProvider(defaultCustomer.id).overrideWith(
              (ref) => Stream.value(store1Orders),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chi nhánh Đông Thắng (100)'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình (0)'), findsOneWidget);
      expect(find.text('Chi nhánh Vĩnh Lộc (0)'), findsOneWidget);

      // Tap store_002 with 0 orders
      final tbChip = find.byKey(const ValueKey('store_filter_store_002'));
      await tester.ensureVisible(tbChip);
      await tester.tap(tbChip);
      await tester.pumpAndSettle();

      expect(find.text('Chưa có giao dịch nào'), findsOneWidget);
      expect(find.text('0 giao dịch'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      // Tap back to store_001
      final dtChip = find.byKey(const ValueKey('store_filter_store_001'));
      await tester.ensureVisible(dtChip);
      await tester.tap(dtChip);
      await tester.pumpAndSettle();

      expect(find.text('100 giao dịch'), findsOneWidget);
      expect(find.text(currencyFormat.format(10000000.0)), findsOneWidget);
    });

    testWidgets(
        'Extreme strings: 50-char customer name and 100-char store name handled cleanly',
        (tester) async {
      const longNameCustomer = Customer(
        id: 'CUST_LONG_NAME',
        name: 'Nguyễn Hoàng Đình Bảo Long Phước Hải Triều Thảo Nhi Lê Anh Quân',
        phone: '0909999999',
        email: 'longname@example.com',
        address: 'Ấp 4, Xã Đông Thắng, Huyện Cờ Đỏ, TP Cần Thơ',
        purchases: [],
        totalSales: 50000000.0,
        currentDebt: 0.0,
      );

      final Map<String, String> extremeStoresMap = {
        'store_001': 'Chi nhánh Đông Thắng',
        'store_extreme':
            'Chi nhánh Siêu thị Nội Thất Tổng Hợp Miền Tây & Trung Tâm Phân Phối Cà Mau Bạc Liêu Kiên Giang 100 Chars',
      };

      final orderExtreme = Order(
        id: 'ORD_EXTREME_01',
        customerId: longNameCustomer.id,
        createdAt: DateTime(2026, 9, 15, 14, 0),
        items: [
          OrderItem(
            productId: 'P_EXT',
            productName:
                'Bộ bàn ghế chạm rồng bát tiên gỗ cẩm lai nguyên khối quý hiếm xuất xứ cao cấp nhập khẩu chính ngạch 12 món đặc biệt',
            quantity: 1,
            price: 50000000.0,
            warrantyMonths: 36,
            purchaseDate: DateTime(2026, 9, 15, 14, 0),
          ),
        ],
        total: 50000000.0,
        storeId: 'store_extreme',
        createdByName:
            'Chuyên viên tư vấn khách hàng VIP Hoàng Thảo Phương Thảo Linh',
        paymentMethod: 'Chuyển khoản ngân hàng Vietcombank',
      );

      await tester.pumpWidget(
        _buildStressTestApp(
          child: const CustomerTransactionsPage(customer: longNameCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider
                .overrideWith((ref) async => extremeStoresMap),
            customerOrdersProvider(longNameCustomer.id).overrideWith(
              (ref) => Stream.value([orderExtreme]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(StoreBadge), findsOneWidget);
      expect(find.text('ORD_EXTREME_01'), findsOneWidget);
    });

    testWidgets('Extreme multi-billion Dong amount in summary header and card',
        (tester) async {
      final bigOrder = Order(
        id: 'HD_BILLION',
        customerId: defaultCustomer.id,
        createdAt: DateTime(2026, 9, 18, 10, 0),
        items: [],
        total: 52750000000.0,
        // 52.75 Billion VND
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        _buildStressTestApp(
          child: const CustomerTransactionsPage(customer: defaultCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider.overrideWith((ref) async => fourStoresMap),
            customerOrdersProvider(defaultCustomer.id).overrideWith(
              (ref) => Stream.value([bigOrder]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(currencyFormat.format(52750000000.0)), findsNWidgets(2));
    });
  });

  group(
      'CHALLENGER STRESS SUITE 4: Ultra-Narrow Viewport (320px) Overflow Stress',
      () {
    testWidgets(
        'Renders on ultra-narrow 320x480 screen without RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final order1 = Order(
        id: 'HD2026-001',
        customerId: defaultCustomer.id,
        createdAt: DateTime(2026, 9, 15, 10, 30),
        items: [
          OrderItem(
            productId: 'P1',
            productName: 'Bàn ghế ăn gỗ căm xe cao cấp 6 ghế',
            quantity: 1,
            price: 8500000.0,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 9, 15, 10, 30),
          ),
        ],
        total: 8500000.0,
        storeId: 'store_001',
        createdByName: 'Nguyễn Văn Nhân Viên Quán',
        paymentMethod: 'Chuyển khoản',
      );

      final order2 = Order(
        id: 'HD2026-002',
        customerId: defaultCustomer.id,
        createdAt: DateTime(2026, 9, 16, 11, 45),
        items: [
          OrderItem(
            productId: 'P2',
            productName: 'Tủ quần áo 3 cánh gỗ sồi nhập khẩu nguyên kiện',
            quantity: 1,
            price: 12500000.0,
            warrantyMonths: 24,
            purchaseDate: DateTime(2026, 9, 16, 11, 45),
          ),
        ],
        total: 12500000.0,
        storeId: 'store_002',
        createdByName: 'Trần Thị Thu Thảo',
        paymentMethod: 'Tiền mặt',
      );

      await tester.pumpWidget(
        _buildStressTestApp(
          child: const CustomerTransactionsPage(customer: defaultCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider.overrideWith((ref) async => fourStoresMap),
            customerOrdersProvider(defaultCustomer.id).overrideWith(
              (ref) => Stream.value([order1, order2]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('HD2026-001'), findsOneWidget);
      expect(find.text('HD2026-002'), findsOneWidget);
      expect(find.text('2 giao dịch'), findsOneWidget);
    });

    testWidgets(
        'Boundary test: 10-char order ID on 320px viewport has 0 overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final order10 = Order(
        id: 'HD20260901',
        // 10 chars
        customerId: defaultCustomer.id,
        createdAt: DateTime(2026, 9, 18, 15, 0),
        items: [],
        total: 1000000.0,
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        _buildStressTestApp(
          child: const CustomerTransactionsPage(customer: defaultCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider.overrideWith((ref) async => fourStoresMap),
            customerOrdersProvider(defaultCustomer.id).overrideWith(
              (ref) => Stream.value([order10]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Boundary test: 14-char order ID on 320px viewport has zero RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final order14 = Order(
        id: 'HD202609180001',
        // 14 chars
        customerId: defaultCustomer.id,
        createdAt: DateTime(2026, 9, 18, 15, 0),
        items: [],
        total: 1000000.0,
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        _buildStressTestApp(
          child: const CustomerTransactionsPage(customer: defaultCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider.overrideWith((ref) async => fourStoresMap),
            customerOrdersProvider(defaultCustomer.id).overrideWith(
              (ref) => Stream.value([order14]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Adversarial Layout: long order ID + long store name on 320px viewport has zero RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final orderWithLongId = Order(
        id: 'HD-KV-20260919-000001',
        customerId: defaultCustomer.id,
        createdAt: DateTime(2026, 9, 18, 15, 0),
        items: [
          OrderItem(
            productId: 'P_LONG',
            productName: 'Giường ngủ hiện đại cao cấp kích thước 1m8 x 2m',
            quantity: 1,
            price: 15000000.0,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 9, 18, 15, 0),
          ),
        ],
        total: 15000000.0,
        storeId: 'store_001',
        createdByName: 'Võ Thị Kiều Diễm',
        paymentMethod: 'transfer',
      );

      await tester.pumpWidget(
        _buildStressTestApp(
          child: const CustomerTransactionsPage(customer: defaultCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider.overrideWith((ref) async => fourStoresMap),
            customerOrdersProvider(defaultCustomer.id).overrideWith(
              (ref) => Stream.value([orderWithLongId]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Adversarial Layout: 22-char order ID on standard 360px width screen has zero RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final order22Chars = Order(
        id: 'HD-KV-20260919-000001',
        customerId: defaultCustomer.id,
        createdAt: DateTime(2026, 9, 18, 15, 0),
        items: [],
        total: 1000000.0,
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        _buildStressTestApp(
          child: const CustomerTransactionsPage(customer: defaultCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider.overrideWith((ref) async => fourStoresMap),
            customerOrdersProvider(defaultCustomer.id).overrideWith(
              (ref) => Stream.value([order22Chars]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
