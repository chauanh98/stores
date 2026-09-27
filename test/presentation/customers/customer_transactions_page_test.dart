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
      home: Material(
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final currencyFormat = NumberFormat('#,###', 'vi_VN');

  const testCustomer = Customer(
    id: 'cust_test_100',
    name: 'Phạm Thị Lan',
    phone: '0912345678',
    email: 'lan@example.com',
    address: 'Cần Thơ',
    totalSales: 10000000.0,
    currentDebt: 0.0,
    purchases: [],
  );

  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffStore1 = UserAccount(
    username: 'staff_dt',
    displayName: 'Nhân viên Đông Thắng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const staffStore2 = UserAccount(
    username: 'staff_tb',
    displayName: 'Nhân viên Thới Bình',
    role: 'nhanvien',
    storeId: 'store_002',
  );

  final baseDate = DateTime(2026, 9, 15, 10, 30);

  final orderStore1 = Order(
    id: 'HD001',
    customerId: 'cust_test_100',
    createdAt: baseDate,
    items: [
      OrderItem(
        productId: 'SP001',
        productName: 'Ghế cao đốt nhang gỗ',
        quantity: 2,
        price: 500000.0,
        warrantyMonths: 12,
        purchaseDate: baseDate,
      ),
    ],
    total: 1000000.0,
    storeId: 'store_001',
    createdByName: 'Nguyễn Văn A',
    paymentMethod: 'cash',
  );

  final orderStore1Second = Order(
    id: 'HD002',
    customerId: 'cust_test_100',
    createdAt: DateTime(2026, 9, 16, 14, 00),
    items: [
      OrderItem(
        productId: 'SP002',
        productName: 'Tủ thờ thao lao',
        quantity: 1,
        price: 3500000.0,
        warrantyMonths: 24,
        purchaseDate: DateTime(2026, 9, 16, 14, 00),
      ),
    ],
    total: 3500000.0,
    storeId: 'store_001',
    createdByName: 'Trần Văn B',
    paymentMethod: 'cash',
  );

  final orderStore2 = Order(
    id: 'HD003',
    customerId: 'cust_test_100',
    createdAt: DateTime(2026, 9, 17, 9, 15),
    items: [
      OrderItem(
        productId: 'SP003',
        productName: 'Bàn ăn cabin',
        quantity: 1,
        price: 4500000.0,
        warrantyMonths: 12,
        purchaseDate: DateTime(2026, 9, 17, 9, 15),
      ),
    ],
    total: 4500000.0,
    storeId: 'store_002',
    createdByName: 'Lê Thị C',
    paymentMethod: 'transfer',
  );

  group('CustomerTransactionsPage - Visual Branch Badges & Local Filter UI', () {
    testWidgets(
        'Admin sees orders from both store_001 and store_002 with respective Store Badges',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([orderStore1, orderStore1Second, orderStore2]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // All 3 orders displayed
      expect(find.text('HD001'), findsOneWidget);
      expect(find.text('HD002'), findsOneWidget);
      expect(find.text('HD003'), findsOneWidget);

      // Store badges displayed for both branches
      expect(find.byType(StoreBadge), findsNWidgets(3));
      expect(find.text('Chi nhánh Đông Thắng'), findsNWidgets(2));
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);

      // Filter chips show counts
      expect(find.text('Tất cả chi nhánh (3)'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng (2)'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình (1)'), findsOneWidget);

      // Header summary displays total of all 3 orders: 1M + 3.5M + 4.5M = 9M
      expect(find.text(currencyFormat.format(9000000.0)), findsOneWidget);
      expect(find.text('3 giao dịch'), findsOneWidget);
    });

    testWidgets(
        'Filtering by "Chi nhánh Đông Thắng" displays only store_001 orders and updates summary total',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([orderStore1, orderStore1Second, orderStore2]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap ChoiceChip for Đông Thắng
      final dtChip = find.byKey(const ValueKey('store_filter_store_001'));
      await tester.ensureVisible(dtChip);
      await tester.tap(dtChip);
      await tester.pumpAndSettle();

      // Only store_001 orders are rendered
      expect(find.text('HD001'), findsOneWidget);
      expect(find.text('HD002'), findsOneWidget);
      expect(find.text('HD003'), findsNothing);

      // Summary total is recalculated: 1M + 3.5M = 4.5M
      expect(find.text(currencyFormat.format(4500000.0)), findsOneWidget);
      expect(find.text('2 giao dịch'), findsOneWidget);
    });

    testWidgets(
        'Filtering by "Chi nhánh Thới Bình" displays only store_002 orders and updates summary total',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([orderStore1, orderStore1Second, orderStore2]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap ChoiceChip for Thới Bình
      final tbChip = find.byKey(const ValueKey('store_filter_store_002'));
      await tester.ensureVisible(tbChip);
      await tester.tap(tbChip);
      await tester.pumpAndSettle();

      // Only store_002 order is rendered
      expect(find.text('HD003'), findsOneWidget);
      expect(find.text('HD001'), findsNothing);
      expect(find.text('HD002'), findsNothing);

      // Summary total is recalculated: 4.5M (header and card amount both present)
      expect(find.text(currencyFormat.format(4500000.0)), findsNWidgets(2));
      expect(find.text('1 giao dịch'), findsOneWidget);
    });

    testWidgets(
        'Tapping "Tất cả chi nhánh" resets filter and restores full orders list and grand total',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([orderStore1, orderStore1Second, orderStore2]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Filter by Thới Bình first
      final tbChip = find.byKey(const ValueKey('store_filter_store_002'));
      await tester.ensureVisible(tbChip);
      await tester.tap(tbChip);
      await tester.pumpAndSettle();
      expect(find.text('HD001'), findsNothing);
      expect(find.text('HD003'), findsOneWidget);

      // Now tap All branches
      final allChip = find.byKey(const ValueKey('store_filter_all'));
      await tester.ensureVisible(allChip);
      await tester.tap(allChip);
      await tester.pumpAndSettle();

      // All 3 orders restored
      expect(find.text('HD001'), findsOneWidget);
      expect(find.text('HD002'), findsOneWidget);
      expect(find.text('HD003'), findsOneWidget);
      expect(find.text(currencyFormat.format(9000000.0)), findsOneWidget);
      expect(find.text('3 giao dịch'), findsOneWidget);
    });

    testWidgets('Staff user only sees orders from their assigned branch',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore1)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([orderStore1, orderStore1Second, orderStore2]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Staff Store 1 only sees Store 1 orders
      expect(find.text('HD001'), findsOneWidget);
      expect(find.text('HD002'), findsOneWidget);
      expect(find.text('HD003'), findsNothing);

      // Staff only has their branch chip and cannot switch
      expect(find.text('Tất cả chi nhánh (3)'), findsNothing);
      expect(find.text('Chi nhánh Đông Thắng (2)'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình (1)'), findsNothing);

      // Summary total reflects only staff's store
      expect(find.text(currencyFormat.format(4500000.0)), findsOneWidget);
    });

    testWidgets('Staff Store 2 only sees orders from store_002',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffStore2)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([orderStore1, orderStore1Second, orderStore2]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HD003'), findsOneWidget);
      expect(find.text('HD001'), findsNothing);
      expect(find.text('HD002'), findsNothing);

      expect(find.text('Chi nhánh Thới Bình (1)'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng (2)'), findsNothing);
      expect(find.text(currencyFormat.format(4500000.0)), findsNWidgets(2));
    });

    testWidgets('Empty state is displayed cleanly if a selected branch has no orders',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            // Only store_001 orders
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([orderStore1, orderStore1Second]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Thới Bình has 0 orders
      expect(find.text('Chi nhánh Thới Bình (0)'), findsOneWidget);

      // Tap Thới Bình
      final tbChip = find.byKey(const ValueKey('store_filter_store_002'));
      await tester.ensureVisible(tbChip);
      await tester.tap(tbChip);
      await tester.pumpAndSettle();

      // Empty state icons and message
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
      expect(find.text('Chưa có giao dịch nào'), findsOneWidget);
      expect(find.text('0 giao dịch'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets(
        'StoreBadge applies distinct styling for store_001, store_002 and fallback',
        (tester) async {
      final orderFallback = Order(
        id: 'HD099',
        customerId: 'cust_test_100',
        createdAt: DateTime(2026, 9, 18, 8, 00),
        items: [
          OrderItem(
            productId: 'SP099',
            productName: 'Bàn trà gỗ sồi',
            quantity: 1,
            price: 2000000.0,
            warrantyMonths: 6,
            purchaseDate: DateTime(2026, 9, 18, 8, 00),
          ),
        ],
        total: 2000000.0,
        storeId: 'store_099',
        createdByName: 'Võ Văn D',
        paymentMethod: 'cash',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([orderStore1, orderStore2, orderFallback]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final badges = tester.widgetList<StoreBadge>(find.byType(StoreBadge)).toList();
      expect(badges.length, 3);

      // Check store_001 badge
      final badgeStore1Finder = find.ancestor(
        of: find.text('Chi nhánh Đông Thắng'),
        matching: find.byType(StoreBadge),
      );
      expect(badgeStore1Finder, findsOneWidget);

      // Verify store_001 container decoration
      final containerStore1 = tester.widget<Container>(
        find.descendant(of: badgeStore1Finder, matching: find.byType(Container)),
      );
      final deco1 = containerStore1.decoration as BoxDecoration;
      expect(deco1.color, const Color(0xFFE0F2FE));

      final textStore1 = tester.widget<Text>(find.text('Chi nhánh Đông Thắng'));
      expect(textStore1.style?.color, const Color(0xFF0067AC));

      // Check store_002 badge
      final badgeStore2Finder = find.ancestor(
        of: find.text('Chi nhánh Thới Bình'),
        matching: find.byType(StoreBadge),
      );
      expect(badgeStore2Finder, findsOneWidget);

      final containerStore2 = tester.widget<Container>(
        find.descendant(of: badgeStore2Finder, matching: find.byType(Container)),
      );
      final deco2 = containerStore2.decoration as BoxDecoration;
      expect(deco2.color, const Color(0xFFDCFCE7));

      final textStore2 = tester.widget<Text>(find.text('Chi nhánh Thới Bình'));
      expect(textStore2.style?.color, const Color(0xFF15803D));

      // Check fallback badge for store_099
      expect(find.text('Chi nhánh store_099'), findsOneWidget);
    });

    testWidgets(
        'Renders cleanly on narrow viewport (360x640) with zero RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([orderStore1, orderStore1Second, orderStore2]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('HD001'), findsOneWidget);
      expect(find.text('HD002'), findsOneWidget);
      expect(find.text('HD003'), findsOneWidget);
    });

    testWidgets(
        'Renders staff name and payment method accurately from Order model',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([orderStore1, orderStore2]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // HD001: Nguyễn Văn A & Tiền mặt
      expect(find.textContaining('Nguyễn Văn A'), findsOneWidget);
      expect(find.text('Tiền mặt'), findsOneWidget);

      // HD003: Lê Thị C & Chuyển khoản
      expect(find.textContaining('Lê Thị C'), findsOneWidget);
      expect(find.text('Chuyển khoản'), findsOneWidget);
    });

    testWidgets(
        'Renders ultra-narrow viewport (320x480) with realistic long order ID (>= 22 chars) without RenderFlex overflow and copy button works',
        (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final longOrder = Order(
        id: 'HD-KV-20260919-000001',
        customerId: testCustomer.id,
        createdAt: DateTime(2026, 9, 19, 10, 0),
        items: [
          OrderItem(
            productId: 'P1',
            productName: 'Sản phẩm nội thất bàn ghế gỗ',
            quantity: 1,
            price: 5000000.0,
            warrantyMonths: 12,
            purchaseDate: DateTime(2026, 9, 19, 10, 0),
          ),
        ],
        total: 5000000.0,
        storeId: 'store_001',
        createdByName: 'Nguyễn Văn A',
        paymentMethod: 'Tiền mặt',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([longOrder]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Zero RenderFlex overflow
      expect(tester.takeException(), isNull);
      expect(find.text('HD-KV-20260919-000001'), findsOneWidget);
      expect(find.byType(StoreBadge), findsOneWidget);

      // Verify copy button functionality
      final copyBtn = find.byIcon(Icons.copy_rounded);
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('HD-KV-20260919-000001'), findsWidgets);
    });

    testWidgets(
        'Renders narrow viewport (360x640) with 22-char long order ID without RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final longOrder = Order(
        id: 'HD-KV-20260919-000001',
        customerId: testCustomer.id,
        createdAt: DateTime(2026, 9, 19, 10, 0),
        items: [],
        total: 2500000.0,
        storeId: 'store_002',
        createdByName: 'Trần Thị B',
        paymentMethod: 'Chuyển khoản',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomerTransactionsPage(customer: testCustomer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerOrdersProvider(testCustomer.id).overrideWith(
              (ref) => Stream.value([longOrder]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('HD-KV-20260919-000001'), findsOneWidget);
      expect(find.byType(StoreBadge), findsOneWidget);
    });
  });
}
