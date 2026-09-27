import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customer_detail_page.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';

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

class _CountingCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _CountingCustomerListNotifier(this._initialCustomers);

  final List<Customer> _initialCustomers;
  int buildCallCount = 0;

  @override
  Future<List<Customer>> build() async {
    buildCallCount++;
    return _initialCustomers;
  }

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialCustomers);
  }
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
  Size screenSize = const Size(400, 900),
  double textScaleFactor = 1.0,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: MediaQuery(
        data: MediaQueryData(
          size: screenSize,
          textScaler: TextScaler.linear(textScaleFactor),
        ),
        child: Material(child: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mockAdminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  group(
      'Adversarial Round 2: InvoicesPage Search Must Not Trigger Customer Catalog',
      () {
    testWidgets(
        'Searching on InvoicesPage when orders have customerName NEVER triggers customerListNotifierProvider',
        (tester) async {
      final notifier = _CountingCustomerListNotifier([]);

      final orders = [
        Order(
          id: 'HD_SEARCH_TEST_01',
          customerId: 'cust_search_1',
          customerName: 'Tập đoàn Hòa Phát',
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: 'SP001',
              productName: 'Bàn ghế sắt sơn tĩnh điện',
              quantity: 2,
              price: 1500000,
              warrantyMonths: 12,
              purchaseDate: DateTime.now(),
            ),
          ],
          total: 3000000,
          amountPaid: 3000000,
          debtAmount: 0,
          status: 'completed',
          paymentMethod: 'cash',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(orders)),
            customerListNotifierProvider.overrideWith(() => notifier),
          ],
          child: const InvoicesPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(notifier.buildCallCount, 0,
          reason: 'Initial load must not trigger customerListNotifierProvider');

      // Now enter search query for order ID
      await tester.enterText(find.byType(TextField).first, 'HD_SEARCH');
      await tester.pumpAndSettle();

      expect(find.text('Tập đoàn Hòa Phát'), findsOneWidget);
      expect(notifier.buildCallCount, 0,
          reason:
              'Searching by order ID must NEVER trigger customerListNotifierProvider');

      // Now enter search query for customer name
      await tester.enterText(find.byType(TextField).first, 'Hòa Phát');
      await tester.pumpAndSettle();

      expect(find.text('Tập đoàn Hòa Phát'), findsOneWidget);
      expect(notifier.buildCallCount, 0,
          reason:
              'Searching by customer name must NEVER trigger customerListNotifierProvider');

      // Now enter search query for product name
      await tester.enterText(find.byType(TextField).first, 'Bàn ghế sắt');
      await tester.pumpAndSettle();

      expect(find.text('Tập đoàn Hòa Phát'), findsOneWidget);
      expect(notifier.buildCallCount, 0,
          reason:
              'Searching by product name must NEVER trigger customerListNotifierProvider');
    });
  });

  group(
      'Adversarial Round 2: Resuming Draft Order Must Preserve Customer Identity',
      () {
    testWidgets(
        'Tapping Tiếp tục xử lý on draft order preserves customer identity in POSCheckoutPage when catalog is not loaded',
        (tester) async {
      final draftOrders = [
        Order(
          id: 'DRAFT_ORDER_001',
          customerId: 'cust_draft_99',
          customerName: 'Nguyễn Văn Bản Nháp',
          createdAt: DateTime.now(),
          items: [
            OrderItem(
              productId: 'SP_DRAFT_1',
              productName: 'Tủ hồ sơ gỗ',
              quantity: 1,
              price: 800000,
              warrantyMonths: 6,
              purchaseDate: DateTime.now(),
            ),
          ],
          total: 800000,
          amountPaid: 0,
          debtAmount: 800000,
          status: 'draft',
          paymentMethod: 'cash',
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(draftOrders)),
            customerListNotifierProvider
                .overrideWith(() => _CountingCustomerListNotifier([])),
            productListProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const InvoicesPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Switch filter to 'Lưu tạm' (since default status is 'completed')
      await tester.tap(find.text('Lưu tạm'));
      await tester.pumpAndSettle();

      // Open draft invoice details sheet
      await tester.tap(find.text('Nguyễn Văn Bản Nháp'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);

      // Find and tap continue payment button
      final resumeButton = find.byType(FilledButton).first;
      expect(resumeButton, findsOneWidget);
      await tester.tap(resumeButton);
      await tester.pumpAndSettle();

      // Assert that POSCheckoutPage was navigated to
      expect(find.byType(POSCheckoutPage), findsOneWidget);

      // Assert customer name is preserved on checkout page
      expect(find.text('Nguyễn Văn Bản Nháp'), findsOneWidget,
          reason:
              'POSCheckoutPage must display customer name from draft order even if catalog was not loaded');
    });
  });

  group('Adversarial Round 2: AsyncError Resilience Across Pages', () {
    testWidgets(
        'InvoicesPage does not throw uncaught exception when orders or accounts are in AsyncError state',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            allBranchesOrdersByDateRangeProvider.overrideWith((ref, range) =>
                Stream.error(Exception('RTDB Connection Timeout'))),
            accountsListProvider.overrideWith(
                (ref) => Stream.error(Exception('Accounts Error'))),
            customerListNotifierProvider
                .overrideWith(() => _CountingCustomerListNotifier([])),
          ],
          child: const InvoicesPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure no crash occurred
      expect(tester.takeException(), isNull,
          reason: 'InvoicesPage must handle AsyncError without throwing');
    });

    testWidgets(
        'CustomerDetailPage does not throw uncaught exception when orders or debt transactions are in AsyncError state',
        (tester) async {
      const testCustomer = Customer(
        id: 'cust_err_test',
        name: 'Trần Lỗi Mạng',
        phone: '0901234567',
        email: '',
        address: '',
        purchases: [],
        totalSales: 100000,
        currentDebt: 50000,
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            customerOrdersProvider('cust_err_test').overrideWith(
                (ref) => Stream.error(Exception('Orders Stream Failed'))),
            customerDebtTransactionsProvider('cust_err_test').overrideWith(
                (ref) => Stream.error(Exception('Debt Stream Failed'))),
          ],
          child: const CustomerDetailPage(customer: testCustomer),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason:
              'CustomerDetailPage must handle AsyncError in orders and debts without throwing');
      expect(find.text('Trần Lỗi Mạng'), findsWidgets);
    });
  });

  group(
      'Adversarial Round 2: Zero RenderFlex Overflow on 320px & 1.25x Text Scaling',
      () {
    testWidgets(
        'CustomersPage renders with 0 overflow at 320px and 1.25x scaling',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const sampleCustomer = Customer(
        id: 'KH_LONG_01',
        name: 'Tập đoàn Công nghiệp - Viễn thông Quân đội Viettel Việt Nam',
        phone: '098877665544',
        email: 'viettel@corporation.vn',
        address: 'Hà Nội',
        purchases: [],
        totalSales: 8888888888.0,
        currentDebt: 7777777777.0,
      );

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(320, 800),
          textScaleFactor: 1.25,
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            customerListNotifierProvider.overrideWith(
                () => _CountingCustomerListNotifier([sampleCustomer])),
          ],
          child: const CustomersPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason:
              'CustomersPage must not overflow on 320px with 1.25x scaling');
    });

    testWidgets(
        'ProductsPage renders with 0 overflow at 320px and 1.25x scaling',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const sampleProduct = Product(
        id: 'SP_LONG_01',
        code: 'SP-EXTREME-CODE-999999999999-VN',
        name:
            'Sản phẩm bàn ăn thông minh kéo dài 10 ghế chất liệu gỗ sồi nhập khẩu nguyên khối',
        price: 999999999.0,
        costPrice: 850000000.0,
        branchStocks: {'store_001': 10000, 'store_002': 20000},
        category: 'Nội thất phòng ăn',
      );

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(320, 800),
          textScaleFactor: 1.25,
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            productListProvider
                .overrideWith((ref) => Stream.value([sampleProduct])),
          ],
          child: const ProductsPage(),
        ),
      );
      FlutterErrorDetails? errorDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errorDetails = details;
      };
      await tester.pumpAndSettle();
      FlutterError.onError = originalOnError;
      if (errorDetails != null) {
        debugPrint('FULL ERROR DETAILS: ${errorDetails!.summary}');
        debugPrint('CONTEXT: ${errorDetails!.context}');
        debugPrint(
            'INFORMATION:\n${errorDetails!.informationCollector?.call().map((e) => e.toString()).join("\n")}');
      }
      final err = errorDetails?.exception;
      expect(err, isNull,
          reason: 'ProductsPage must not overflow on 320px with 1.25x scaling');
    });
  });
}
