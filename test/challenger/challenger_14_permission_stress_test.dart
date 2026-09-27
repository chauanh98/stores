import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/customers/usecases/import_customers_usecase.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/orders/usecases/import_invoices_usecase.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/products/usecases/import_products_usecase.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/application/suppliers/usecases/import_suppliers_usecase.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/import_result.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/suppliers/pages/suppliers_page.dart';

// ============================================================================
// ADVERSARIAL TEST DOUBLES & SECURITY SPIES
// ============================================================================

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

class _SpyImportProductsUseCase implements ImportProductsUseCase {
  int callCount = 0;

  @override
  Future<ImportResult> execute({
    required List<Product> products,
    required String targetStoreId,
  }) async {
    callCount++;
    throw AssertionError(
      'SECURITY BREACH: ImportProductsUseCase.execute was invoked bypassing Layer 2 guard!',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyImportCustomersUseCase implements ImportCustomersUseCase {
  int callCount = 0;

  @override
  Future<ImportResult> execute({
    required List<Customer> customers,
  }) async {
    callCount++;
    throw AssertionError(
      'SECURITY BREACH: ImportCustomersUseCase.execute was invoked bypassing Layer 2 guard!',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyImportSuppliersUseCase implements ImportSuppliersUseCase {
  int callCount = 0;

  @override
  Future<ImportResult> execute({
    required List<Supplier> suppliers,
    String? targetStoreId,
  }) async {
    callCount++;
    throw AssertionError(
      'SECURITY BREACH: ImportSuppliersUseCase.execute was invoked bypassing Layer 2 guard!',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyImportInvoicesUseCase implements ImportInvoicesUseCase {
  int callCount = 0;

  @override
  Future<ImportResult> execute({
    required List<Order> orders,
    required String targetStoreId,
  }) async {
    callCount++;
    throw AssertionError(
      'SECURITY BREACH: ImportInvoicesUseCase.execute was invoked bypassing Layer 2 guard!',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

// ============================================================================
// TEST SUITE: ADVERSARIAL PERMISSION & WEB ISOLATION CHALLENGER
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Test User Accounts with varying privileges
  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor',
    displayName: 'Chủ chuỗi / Cửa hàng trưởng',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff',
    displayName: 'Nhân viên bán hàng',
    role: 'staff',
    storeId: 'store_001',
  );

  const nhanvienUser = UserAccount(
    username: 'nhanvien',
    displayName: 'Nhân viên thu ngân',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const cuahangtruongUser = UserAccount(
    username: 'cuahangtruong',
    displayName: 'Quản lý cửa hàng (không phân quyền admin)',
    role: 'cuahangtruong',
    storeId: 'store_001',
  );

  const sampleProducts = <Product>[
    Product(
      id: 'p1',
      name: 'Bàn trà gỗ sồi',
      code: 'BT01',
      price: 2500000,
      costPrice: 1500000,
      branchStocks: {'store_001': 5},
      category: 'Nội thất',
    ),
  ];

  const sampleCustomers = <Customer>[
    Customer(
      id: 'c1',
      name: 'Trần Văn Khách',
      phone: '0987654321',
      email: 'khach@test.vn',
      address: 'TP.HCM',
      purchases: [],
    ),
  ];

  const sampleSuppliers = <Supplier>[
    Supplier(
      id: 's1',
      code: 'NCC_WOOD',
      name: 'Xưởng Gỗ Sồi Miền Bắc',
      phone: '0933221100',
      currentDebt: 5000000,
      totalPurchase: 50000000,
    ),
  ];

  group('CHALLENGE 1: Direct Execution Guard Bypass Attempts on Native Mobile (kIsWeb == false)', () {
    testWidgets(
        'Admin attempting direct _importProducts / _exportProducts calls must immediately early-return without I/O or mutations',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final spyProductsUseCase = _SpyImportProductsUseCase();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
            importProductsUseCaseProvider.overrideWithValue(spyProductsUseCase),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<ProductsPageState>(find.byType(ProductsPage));

      // Adversarially simulate direct programmatic call to import
      await state.testImportProducts();
      await tester.pump();

      // Adversarially simulate direct programmatic call to export
      await state.testExportProducts();
      await tester.pump();

      // Invariant checks:
      // 1. Usecase was never reached
      expect(spyProductsUseCase.callCount, 0);
      // 2. No loading indicator dialog pushed
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // 3. No snackbar displayed
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
        'Admin attempting direct _importCustomers / _exportCustomers calls must immediately early-return without I/O or mutations',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final spyCustomersUseCase = _SpyImportCustomersUseCase();

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
            importCustomersUseCaseProvider
                .overrideWithValue(spyCustomersUseCase),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final state =
          tester.state<CustomersPageState>(find.byType(CustomersPage));

      await state.testImportCustomers();
      await tester.pump();

      await state.testExportCustomers();
      await tester.pump();

      expect(spyCustomersUseCase.callCount, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
        'Admin attempting direct _importSuppliers / _exportSuppliers calls must immediately early-return without I/O or mutations',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final spySuppliersUseCase = _SpyImportSuppliersUseCase();

      await tester.pumpWidget(
        _buildTestApp(
          child: const SuppliersPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            supplierListNotifierProvider.overrideWith(
                () => _FakeSupplierListNotifier(sampleSuppliers)),
            filteredSuppliersProvider.overrideWith(
                (ref) => const AsyncData(sampleSuppliers)),
            importSuppliersUseCaseProvider
                .overrideWithValue(spySuppliersUseCase),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final state =
          tester.state<SuppliersPageState>(find.byType(SuppliersPage));

      await state.testImportSuppliers();
      await tester.pump();

      await state.testExportSuppliers();
      await tester.pump();

      expect(spySuppliersUseCase.callCount, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
        'Admin attempting direct _importInvoices / _exportInvoicesToExcel calls must immediately early-return without I/O or mutations',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final spyInvoicesUseCase = _SpyImportInvoicesUseCase();

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
            importInvoicesUseCaseProvider.overrideWithValue(spyInvoicesUseCase),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final state =
          tester.state<InvoicesPageState>(find.byType(InvoicesPage));

      await state.testImportInvoices();
      await tester.pump();

      await state.testExportInvoices(tester.element(find.byType(InvoicesPage)));
      await tester.pump();

      expect(spyInvoicesUseCase.callCount, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('CHALLENGE 2: Direct Execution Guard Bypass Attempts by Non-Admin Roles', () {
    final nonAdminUsers = <String, UserAccount?>{
      'role: staff': staffUser,
      'role: supervisor': supervisorUser,
      'role: cuahangtruong': cuahangtruongUser,
      'role: nhanvien': nhanvienUser,
      'unauthenticated (null)': null,
    };

    for (final entry in nonAdminUsers.entries) {
      final roleDesc = entry.key;
      final user = entry.value;

      testWidgets(
          'Products: $roleDesc bypass attempt immediately early-returns',
          (tester) async {
        final spyProductsUseCase = _SpyImportProductsUseCase();

        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductsPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
              productListProvider
                  .overrideWith((ref) => Stream.value(sampleProducts)),
              importProductsUseCaseProvider
                  .overrideWithValue(spyProductsUseCase),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final state = tester.state<ProductsPageState>(find.byType(ProductsPage));
        await state.testImportProducts();
        await state.testExportProducts();
        await tester.pump();

        expect(spyProductsUseCase.callCount, 0);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets(
          'Customers: $roleDesc bypass attempt immediately early-returns',
          (tester) async {
        final spyCustomersUseCase = _SpyImportCustomersUseCase();

        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomersPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
              customerListNotifierProvider.overrideWith(
                  () => _FakeCustomerListNotifier(sampleCustomers)),
              customerOrdersProvider(sampleCustomers[0].id)
                  .overrideWith((ref) => Stream.value(<Order>[])),
              customerDebtTransactionsProvider(sampleCustomers[0].id)
                  .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
              importCustomersUseCaseProvider
                  .overrideWithValue(spyCustomersUseCase),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final state =
            tester.state<CustomersPageState>(find.byType(CustomersPage));
        await state.testImportCustomers();
        await state.testExportCustomers();
        await tester.pump();

        expect(spyCustomersUseCase.callCount, 0);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets(
          'Suppliers: $roleDesc bypass attempt immediately early-returns',
          (tester) async {
        final spySuppliersUseCase = _SpyImportSuppliersUseCase();

        await tester.pumpWidget(
          _buildTestApp(
            child: const SuppliersPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
              supplierListNotifierProvider.overrideWith(
                  () => _FakeSupplierListNotifier(sampleSuppliers)),
              filteredSuppliersProvider.overrideWith(
                  (ref) => const AsyncData(sampleSuppliers)),
              importSuppliersUseCaseProvider
                  .overrideWithValue(spySuppliersUseCase),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final state =
            tester.state<SuppliersPageState>(find.byType(SuppliersPage));
        await state.testImportSuppliers();
        await state.testExportSuppliers();
        await tester.pump();

        expect(spySuppliersUseCase.callCount, 0);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets(
          'Invoices: $roleDesc bypass attempt immediately early-returns',
          (tester) async {
        final spyInvoicesUseCase = _SpyImportInvoicesUseCase();

        await tester.pumpWidget(
          _buildTestApp(
            child: const InvoicesPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
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
              importInvoicesUseCaseProvider
                  .overrideWithValue(spyInvoicesUseCase),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final state =
            tester.state<InvoicesPageState>(find.byType(InvoicesPage));
        await state.testImportInvoices();
        await state
            .testExportInvoices(tester.element(find.byType(InvoicesPage)));
        await tester.pump();

        expect(spyInvoicesUseCase.callCount, 0);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
      });
    }
  });

  group('CHALLENGE 3: Concurrency & Reentrancy Stress Under Non-Admin / Mobile', () {
    testWidgets(
        'Products: Burst of 10 concurrent calls does not corrupt state or trigger usecases',
        (tester) async {
      final spyProductsUseCase = _SpyImportProductsUseCase();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            productListProvider
                .overrideWith((ref) => Stream.value(sampleProducts)),
            importProductsUseCaseProvider.overrideWithValue(spyProductsUseCase),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final productsState =
          tester.state<ProductsPageState>(find.byType(ProductsPage));
      await Future.wait(List.generate(
        10,
        (_) => Future.wait([
          productsState.testImportProducts(),
          productsState.testExportProducts(),
        ]),
      ));
      await tester.pump();
      expect(spyProductsUseCase.callCount, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
        'Customers: Burst of 10 concurrent calls does not corrupt state or trigger usecases',
        (tester) async {
      final spyCustomersUseCase = _SpyImportCustomersUseCase();

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
            importCustomersUseCaseProvider
                .overrideWithValue(spyCustomersUseCase),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final customersState =
          tester.state<CustomersPageState>(find.byType(CustomersPage));
      await Future.wait(List.generate(
        10,
        (_) => Future.wait([
          customersState.testImportCustomers(),
          customersState.testExportCustomers(),
        ]),
      ));
      await tester.pump();
      expect(spyCustomersUseCase.callCount, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
        'Suppliers: Burst of 10 concurrent calls does not corrupt state or trigger usecases',
        (tester) async {
      final spySuppliersUseCase = _SpyImportSuppliersUseCase();

      await tester.pumpWidget(
        _buildTestApp(
          child: const SuppliersPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            supplierListNotifierProvider.overrideWith(
                () => _FakeSupplierListNotifier(sampleSuppliers)),
            filteredSuppliersProvider.overrideWith(
                (ref) => const AsyncData(sampleSuppliers)),
            importSuppliersUseCaseProvider
                .overrideWithValue(spySuppliersUseCase),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final suppliersState =
          tester.state<SuppliersPageState>(find.byType(SuppliersPage));
      await Future.wait(List.generate(
        10,
        (_) => Future.wait([
          suppliersState.testImportSuppliers(),
          suppliersState.testExportSuppliers(),
        ]),
      ));
      await tester.pump();
      expect(spySuppliersUseCase.callCount, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
        'Invoices: Burst of 10 concurrent calls does not corrupt state or trigger usecases',
        (tester) async {
      final spyInvoicesUseCase = _SpyImportInvoicesUseCase();

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
            importInvoicesUseCaseProvider.overrideWithValue(spyInvoicesUseCase),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final invoicesState =
          tester.state<InvoicesPageState>(find.byType(InvoicesPage));
      final invoiceContext = tester.element(find.byType(InvoicesPage));
      await Future.wait(List.generate(
        10,
        (_) => Future.wait([
          invoicesState.testImportInvoices(),
          invoicesState.testExportInvoices(invoiceContext),
        ]),
      ));
      await tester.pump();
      expect(spyInvoicesUseCase.callCount, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('CHALLENGE 4: UI Tree Inspection & Web Isolation Invariants on Native Mobile (kIsWeb == false)', () {
    testWidgets(
        'CustomersPage: Excel menu key and items are 100% absent in native mobile for Admin & Non-Admin',
        (tester) async {
      for (final user in [adminUser, supervisorUser, staffUser, cuahangtruongUser, null]) {
        await tester.pumpWidget(
          _buildTestApp(
            child: const CustomersPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
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

        // UI Key MUST NOT exist in widget tree
        expect(find.byKey(const Key('customers_excel_actions_menu')), findsNothing,
            reason: 'customers_excel_actions_menu must not exist on mobile for ${user?.role}');
        // Excel items MUST NOT exist
        expect(find.text('Nhập từ Excel'), findsNothing);
        expect(find.text('Xuất ra Excel'), findsNothing);
      }
    });

    testWidgets(
        'SuppliersPage: Excel menu key and items are 100% absent in native mobile for Admin & Non-Admin',
        (tester) async {
      for (final user in [adminUser, supervisorUser, staffUser, cuahangtruongUser, null]) {
        await tester.pumpWidget(
          _buildTestApp(
            child: const SuppliersPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
              supplierListNotifierProvider.overrideWith(
                  () => _FakeSupplierListNotifier(sampleSuppliers)),
              filteredSuppliersProvider.overrideWith(
                  (ref) => const AsyncData(sampleSuppliers)),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('suppliers_excel_actions_menu')), findsNothing,
            reason: 'suppliers_excel_actions_menu must not exist on mobile for ${user?.role}');
        expect(find.text('Nhập từ Excel'), findsNothing);
        expect(find.text('Xuất ra Excel'), findsNothing);
      }
    });

    testWidgets(
        'InvoicesPage: Excel menu key and legacy export button are 100% absent in native mobile',
        (tester) async {
      for (final user in [adminUser, supervisorUser, staffUser, cuahangtruongUser, null]) {
        await tester.pumpWidget(
          _buildTestApp(
            child: const InvoicesPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
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

        expect(find.byKey(const Key('invoices_excel_actions_menu')), findsNothing,
            reason: 'invoices_excel_actions_menu must not exist on mobile for ${user?.role}');
        expect(find.byKey(const Key('export_excel_button')), findsNothing,
            reason: 'Legacy export_excel_button must never exist on mobile');
        expect(find.text('Nhập hóa đơn từ Excel'), findsNothing);
        expect(find.text('Xuất Excel'), findsNothing);
      }
    });

    testWidgets(
        'ProductsPage: Non-manager roles (staff, cuahangtruong, null) have zero action menu keys or Excel items',
        (tester) async {
      for (final user in [staffUser, nhanvienUser, cuahangtruongUser, null]) {
        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductsPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
              productListProvider
                  .overrideWith((ref) => Stream.value(sampleProducts)),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('products_excel_actions_menu')), findsNothing,
            reason: 'products_excel_actions_menu must not exist for non-manager role ${user?.role}');
        expect(find.text('Nhập từ Excel'), findsNothing);
        expect(find.text('Xuất ra Excel'), findsNothing);
      }
    });

    testWidgets(
        'ProductsPage: Admin & Supervisor on native mobile can access inventory/image actions but Excel actions are strictly absent',
        (tester) async {
      for (final user in [adminUser, supervisorUser]) {
        await tester.pumpWidget(
          _buildTestApp(
            child: const ProductsPage(),
            overrides: [
              authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
              productListProvider
                  .overrideWith((ref) => Stream.value(sampleProducts)),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // The products action menu button exists for managers
        final menuFinder = find.byKey(const Key('products_excel_actions_menu'));
        expect(menuFinder, findsOneWidget);

        // Tap to open popup menu
        await tester.tap(menuFinder);
        await tester.pumpAndSettle();

        // Standard non-Excel items MUST be present
        expect(find.text('Nhập kho sản phẩm'), findsOneWidget);
        expect(find.text('Tự động gán ảnh mẫu'), findsOneWidget);

        // Excel actions MUST NOT exist in the popup menu on native mobile
        expect(find.text('Nhập từ Excel'), findsNothing,
            reason: 'Excel import must be excluded on mobile for ${user.role}');
        expect(find.text('Xuất ra Excel'), findsNothing,
            reason: 'Excel export must be excluded on mobile for ${user.role}');
        expect(find.byIcon(Icons.upload_file), findsNothing);
        expect(find.byIcon(Icons.download), findsNothing);

        // Dismiss popup menu
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
    });
  });
}
