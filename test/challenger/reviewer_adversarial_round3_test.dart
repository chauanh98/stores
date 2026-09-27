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
import 'package:stores/presentation/orders/controllers/invoices_filter_controller.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/widgets/return_order_bottom_sheet.dart';
import 'package:stores/presentation/orders/widgets/return_order_detail_bottom_sheet.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

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

  group('Adversarial Round 3: Bug Hunt', () {
    testWidgets(
        '1. InvoicesPage _buildReturnSummaryCard must not overflow on 320px viewport with 1.25x scaling',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final returnedOrder = Order(
        id: 'HD_RETURN_9999',
        customerId: 'cust_01',
        customerName: 'Nguyễn Văn Hoàn Trả',
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            productId: 'SP001',
            productName: 'Bàn họp oval 12 chỗ chân sắt cao cấp',
            quantity: 5,
            price: 25000000.0,
            warrantyMonths: 12,
            purchaseDate: DateTime.now(),
            returnedQuantity: 5,
          ),
        ],
        total: 125000000.0,
        amountPaid: 100000000.0,
        debtAmount: 25000000.0,
        status: 'returned',
        paymentMethod: 'transfer',
      );

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
          allBranchesOrdersByDateRangeProvider
              .overrideWith((ref, range) => Stream.value([returnedOrder])),
          customerListNotifierProvider
              .overrideWith(() => _CountingCustomerListNotifier([])),
        ],
      );
      addTearDown(container.dispose);

      // Set status filter to 'returned'
      container.read(invoicesFilterProvider.notifier).setStatus('returned');

      FlutterErrorDetails? errorDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errorDetails = details;
      };

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(320, 800),
                textScaler: TextScaler.linear(1.25),
              ),
              child: Material(child: InvoicesPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      FlutterError.onError = originalOnError;

      expect(errorDetails, isNull,
          reason:
              '_buildReturnSummaryCard must not overflow on 320px viewport with 1.25x scale: ${errorDetails?.summary}');
    });

    testWidgets(
        '2. InvoicesPage _showInvoiceDetailsBottomSheet must not overflow on 320px with 1.25x scaling for long customer name',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const longCustName =
          'Tổng Công ty Cổ phần Bưu chính Viettel - Chi nhánh Thành phố Hà Nội';
      final orderWithLongName = Order(
        id: 'HD_LONG_001',
        customerId: 'cust_viettel_long',
        customerName: longCustName,
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            productId: 'SP001',
            productName: 'Ghế xoay',
            quantity: 1,
            price: 500000,
            warrantyMonths: 12,
            purchaseDate: DateTime.now(),
          ),
        ],
        total: 500000,
        amountPaid: 500000,
        debtAmount: 0,
        status: 'completed',
        paymentMethod: 'cash',
      );

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
          allBranchesOrdersByDateRangeProvider
              .overrideWith((ref, range) => Stream.value([orderWithLongName])),
          customerListNotifierProvider
              .overrideWith(() => _CountingCustomerListNotifier([])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(320, 800),
                textScaler: TextScaler.linear(1.25),
              ),
              child: Material(child: InvoicesPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      FlutterErrorDetails? errorDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errorDetails = details;
      };

      // Tap invoice tile to open details bottom sheet
      await tester.tap(find.text(longCustName));
      await tester.pumpAndSettle();

      FlutterError.onError = originalOnError;

      expect(errorDetails, isNull,
          reason:
              '_showInvoiceDetailsBottomSheet must not overflow on 320px with long customer name: ${errorDetails?.summary}');
    });

    testWidgets(
        '3. ProductTile must handle AsyncError in productListProvider for combo product without throwing',
        (tester) async {
      const comboProduct = Product(
        id: 'COMBO_01',
        code: 'CB001',
        name: 'Bộ bàn ghế phòng khách',
        price: 5000000,
        costPrice: 3000000,
        branchStocks: {'store_001': 10},
        category: 'Combo',
        isCombo: true,
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            productListProvider.overrideWith(
                (ref) => Stream.error(Exception('Product stream timeout'))),
          ],
          child: const ProductTile(product: comboProduct),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason:
              'ProductTile must handle AsyncError in productListProvider for combo product without crashing');
    });

    testWidgets(
        '4. ReturnOrderDetailBottomSheet displays order.customerName when customer catalog is not in memory',
        (tester) async {
      final orderWithEmbeddedName = Order(
        id: 'HD_TEST_RETURN_DETAIL',
        customerId: 'cust_remote_99',
        customerName: 'Công ty TNHH Giải pháp Phần mềm Ánh Dương',
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            productId: 'SP001',
            productName: 'Tủ tài liệu',
            quantity: 2,
            price: 1200000,
            warrantyMonths: 12,
            purchaseDate: DateTime.now(),
            returnedQuantity: 1,
          ),
        ],
        total: 2400000,
        amountPaid: 2400000,
        debtAmount: 0,
        status: 'returned',
        paymentMethod: 'cash',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: ReturnOrderDetailBottomSheet(
            order: orderWithEmbeddedName,
            customer: null, // Customer catalog is NOT loaded
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Khách hàng: Công ty TNHH Giải pháp Phần mềm Ánh Dương'),
          findsOneWidget,
          reason:
              'ReturnOrderDetailBottomSheet must display embedded order.customerName instead of falling back to customerId');
    });

    testWidgets(
        '5. ReturnOrderBottomSheet header must not overflow on 320px with 1.25x scaling for long order ID',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final orderWithLongId = Order(
        id: 'HD-LONG-ID-20260919-00123456789-HN',
        customerId: 'cust_01',
        customerName: 'Khách hàng A',
        createdAt: DateTime.now(),
        items: [
          OrderItem(
            productId: 'SP001',
            productName: 'Ghế xoay lưới',
            quantity: 2,
            price: 500000,
            warrantyMonths: 12,
            purchaseDate: DateTime.now(),
          ),
        ],
        total: 1000000,
        amountPaid: 1000000,
        debtAmount: 0,
        status: 'completed',
        paymentMethod: 'cash',
      );

      FlutterErrorDetails? errorDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errorDetails = details;
      };

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(320, 800),
          textScaleFactor: 1.25,
          child: ReturnOrderBottomSheet(
            order: orderWithLongId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      FlutterError.onError = originalOnError;

      expect(errorDetails, isNull,
          reason:
              'ReturnOrderBottomSheet header must not overflow on 320px with 1.25x scale: ${errorDetails?.summary}');
    });

    testWidgets(
        '6. CustomerDetailPage must not overflow on 320px with 1.25x scaling for long customer ID',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const customerWithLongId = Customer(
        id: 'KH-EXTREMELY-LONG-IDENTIFIER-9999999999-VN',
        name: 'Nguyễn Văn Test',
        phone: '0912345678',
        email: '',
        address: '',
        purchases: [],
        totalSales: 1000000,
        currentDebt: 0,
      );

      FlutterErrorDetails? errorDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errorDetails = details;
      };

      await tester.pumpWidget(
        _buildTestApp(
          screenSize: const Size(320, 800),
          textScaleFactor: 1.25,
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(mockAdminUser)),
            customerOrdersProvider(customerWithLongId.id)
                .overrideWith((ref) => Stream.value([])),
            customerDebtTransactionsProvider(customerWithLongId.id)
                .overrideWith((ref) => Stream.value([])),
            customerListNotifierProvider.overrideWith(
                () => _CountingCustomerListNotifier([customerWithLongId])),
          ],
          child: const CustomerDetailPage(customer: customerWithLongId),
        ),
      );
      await tester.pumpAndSettle();
      FlutterError.onError = originalOnError;

      expect(errorDetails, isNull,
          reason:
              'CustomerDetailPage must not overflow on 320px with 1.25x scale: ${errorDetails?.summary}');
    });
  });
}
