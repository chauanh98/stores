import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/suppliers/pages/suppliers_page.dart';

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

class _FakeCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _FakeCustomerListNotifier(this._initialCustomers);

  final List<Customer> _initialCustomers;

  @override
  Future<List<Customer>> build() async => _initialCustomers;

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialCustomers);
  }
}

class _FakeSupplierListNotifier
    extends AutoDisposeAsyncNotifier<List<Supplier>>
    implements SupplierListNotifier {
  _FakeSupplierListNotifier(this._initialSuppliers);

  final List<Supplier> _initialSuppliers;

  @override
  Future<List<Supplier>> build() async => _initialSuppliers;

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialSuppliers);
  }

  @override
  Future<void> upsertSupplier(Supplier supplier) async {}

  @override
  Future<void> deleteSupplier(String id) async {}

  @override
  Future<void> recordDebtPayment({
    required String supplierId,
    required double paymentAmount,
    String? referenceCode,
    String? note,
    String createdBy = 'Admin',
  }) async {}

  @override
  Future<void> recordDebtAdjustment({
    required String supplierId,
    required double newDebt,
    String? note,
    String createdBy = 'Admin',
  }) async {}

  @override
  Future<void> recordImportDebt({
    required String supplierId,
    required double totalAmount,
    required double paidAmount,
    String? importCode,
    String? note,
    String createdBy = 'Admin',
  }) async {}
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
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor',
    displayName: 'Chủ chuỗi',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff',
    displayName: 'Nhân viên bán hàng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const sampleProducts = <Product>[
    Product(
      id: 'p1',
      name: 'Áo thun cotton cao cấp',
      code: 'AT01',
      price: 150000,
      costPrice: 80000,
      branchStocks: {'store_001': 10},
      category: 'Thời trang',
    ),
  ];

  const sampleCustomers = <Customer>[
    Customer(
      id: 'c1',
      name: 'Nguyễn Văn Test',
      phone: '0901234567',
      email: 'test@example.com',
      address: 'Hà Nội',
      purchases: [],
    ),
  ];

  const sampleSuppliers = <Supplier>[
    Supplier(
      id: 's1',
      code: 'NCC01',
      name: 'NCC May Mặc',
      phone: '0912345678',
      currentDebt: 0,
      totalPurchase: 0,
    ),
  ];

  group('Milestone 3 — ProductsPage Dual-Layer Permission Guards', () {
    testWidgets(
        'On mobile (kIsWeb == false), Admin cannot see Excel items in PopupMenuButton',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // PopupMenuButton is visible for admin (canManageProducts == true)
      final popupMenuFinder =
          find.byKey(const Key('products_excel_actions_menu'));
      expect(popupMenuFinder, findsOneWidget);

      // Open the popup menu
      await tester.tap(popupMenuFinder);
      await tester.pumpAndSettle();

      // Non-Excel items must be present in the popup menu
      expect(find.text('Nhập kho sản phẩm'), findsOneWidget);
      expect(find.text('Tự động gán ảnh mẫu'), findsOneWidget);

      // Excel items MUST NOT be rendered on mobile
      expect(find.text('Nhập từ Excel'), findsNothing);
      expect(find.text('Xuất ra Excel'), findsNothing);
      expect(find.byIcon(Icons.upload_file), findsNothing);
      expect(find.byIcon(Icons.download), findsNothing);
    });

    testWidgets(
        'On mobile, Supervisor cannot see Excel items in PopupMenuButton',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final popupMenuFinder =
          find.byKey(const Key('products_excel_actions_menu'));
      expect(popupMenuFinder, findsOneWidget);

      await tester.tap(popupMenuFinder);
      await tester.pumpAndSettle();

      expect(find.text('Nhập kho sản phẩm'), findsOneWidget);
      expect(find.text('Tự động gán ảnh mẫu'), findsOneWidget);
      expect(find.text('Nhập từ Excel'), findsNothing);
      expect(find.text('Xuất ra Excel'), findsNothing);
    });

    testWidgets(
        'Staff user cannot see Products actions popup menu at all',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('products_excel_actions_menu')),
          findsNothing);
    });

    testWidgets(
        'ProductsPage execution guards early-return when not on web or non-admin',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<ProductsPageState>(find.byType(ProductsPage));
      // Calling execution-guarded methods returns immediately without error or side-effect
      await state.testImportProducts();
      await state.testExportProducts();
      await tester.pump();

      // No progress dialog shown
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('Milestone 3 — CustomersPage Dual-Layer Permission Guards', () {
    testWidgets(
        'On mobile (kIsWeb == false), Admin cannot see Customers Excel menu',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier(sampleCustomers)),
            customerOrdersProvider(sampleCustomers[0].id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(sampleCustomers[0].id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // On mobile (kIsWeb == false), menu is completely absent
      expect(find.byKey(const Key('customers_excel_actions_menu')),
          findsNothing);
      expect(find.text('Nhập từ Excel'), findsNothing);
      expect(find.text('Xuất ra Excel'), findsNothing);
    });

    testWidgets(
        'Non-admin users (Supervisor and Staff) cannot see Customers Excel menu',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Supervisor
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier(sampleCustomers)),
            customerOrdersProvider(sampleCustomers[0].id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(sampleCustomers[0].id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customers_excel_actions_menu')),
          findsNothing);

      // Staff
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier(sampleCustomers)),
            customerOrdersProvider(sampleCustomers[0].id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(sampleCustomers[0].id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('customers_excel_actions_menu')),
          findsNothing);
    });

    testWidgets(
        'CustomersPage execution guards early-return without side-effects',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier(sampleCustomers)),
            customerOrdersProvider(sampleCustomers[0].id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(sampleCustomers[0].id)
                .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final state =
          tester.state<CustomersPageState>(find.byType(CustomersPage));
      await state.testImportCustomers();
      await state.testExportCustomers();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('Milestone 3 — SuppliersPage Dual-Layer Permission Guards', () {
    testWidgets(
        'On mobile (kIsWeb == false), Admin cannot see Suppliers Excel menu',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const SuppliersPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            supplierListNotifierProvider.overrideWith(
                () => _FakeSupplierListNotifier(sampleSuppliers)),
            filteredSuppliersProvider.overrideWith(
                (ref) => const AsyncData(sampleSuppliers)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // On mobile (kIsWeb == false), Excel menu is completely absent
      expect(find.byKey(const Key('suppliers_excel_actions_menu')),
          findsNothing);
      // Add supplier button is still visible
      expect(find.byTooltip('Thêm nhà cung cấp'), findsOneWidget);
    });

    testWidgets(
        'Non-admin users (Supervisor and Staff) cannot see Suppliers Excel menu',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Supervisor
      await tester.pumpWidget(
        _buildTestApp(
          child: const SuppliersPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            supplierListNotifierProvider.overrideWith(
                () => _FakeSupplierListNotifier(sampleSuppliers)),
            filteredSuppliersProvider.overrideWith(
                (ref) => const AsyncData(sampleSuppliers)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('suppliers_excel_actions_menu')),
          findsNothing);

      // Staff
      await tester.pumpWidget(
        _buildTestApp(
          child: const SuppliersPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            supplierListNotifierProvider.overrideWith(
                () => _FakeSupplierListNotifier(sampleSuppliers)),
            filteredSuppliersProvider.overrideWith(
                (ref) => const AsyncData(sampleSuppliers)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('suppliers_excel_actions_menu')),
          findsNothing);
    });

    testWidgets(
        'SuppliersPage execution guards early-return without side-effects',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const SuppliersPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            supplierListNotifierProvider.overrideWith(
                () => _FakeSupplierListNotifier(sampleSuppliers)),
            filteredSuppliersProvider.overrideWith(
                (ref) => const AsyncData(sampleSuppliers)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final state =
          tester.state<SuppliersPageState>(find.byType(SuppliersPage));
      await state.testImportSuppliers();
      await state.testExportSuppliers();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('Milestone 3 — InvoicesPage Dual-Layer Permission Guards', () {
    testWidgets(
        'On mobile (kIsWeb == false), Admin cannot see Excel menu or standalone export button',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider.overrideWith(
                (ref) => Stream.value([adminUser, staffUser])),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier(sampleCustomers)),
            invoicesActiveDateRangeProvider.overrideWith((ref) =>
                DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 30)),
                    end: DateTime.now())),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value(<Order>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Excel actions menu is completely hidden on mobile
      expect(
          find.byKey(const Key('invoices_excel_actions_menu')), findsNothing);
      // Legacy standalone button is removed
      expect(find.byKey(const Key('export_excel_button')), findsNothing);
    });

    testWidgets(
        'Non-admin users (Supervisor and Staff) cannot see Invoices Excel menu',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Supervisor
      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            accountsListProvider.overrideWith(
                (ref) => Stream.value([supervisorUser, staffUser])),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier(sampleCustomers)),
            invoicesActiveDateRangeProvider.overrideWith((ref) =>
                DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 30)),
                    end: DateTime.now())),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value(<Order>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('invoices_excel_actions_menu')), findsNothing);
      expect(find.byKey(const Key('export_excel_button')), findsNothing);

      // Staff
      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            accountsListProvider.overrideWith(
                (ref) => Stream.value([adminUser, staffUser])),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier(sampleCustomers)),
            invoicesActiveDateRangeProvider.overrideWith((ref) =>
                DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 30)),
                    end: DateTime.now())),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value(<Order>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('invoices_excel_actions_menu')), findsNothing);
      expect(find.byKey(const Key('export_excel_button')), findsNothing);
    });

    testWidgets(
        'InvoicesPage execution guards early-return without side-effects',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            accountsListProvider.overrideWith(
                (ref) => Stream.value([adminUser, staffUser])),
            customerListNotifierProvider.overrideWith(
                () => _FakeCustomerListNotifier(sampleCustomers)),
            invoicesActiveDateRangeProvider.overrideWith((ref) =>
                DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 30)),
                    end: DateTime.now())),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value(<Order>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final state =
          tester.state<InvoicesPageState>(find.byType(InvoicesPage));
      await state.testImportInvoices();
      await state.testExportInvoices(tester.element(find.byType(InvoicesPage)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
