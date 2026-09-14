import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/inter_store_transfer_page.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/settings/pages/account_management_page.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';
import 'package:stores/presentation/settings/pages/store_payment_settings_page.dart';
import 'package:stores/presentation/suppliers/pages/suppliers_page.dart';

class _DynamicAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _DynamicAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _FakeCustomerListNotifier extends CustomerListNotifier {
  @override
  Future<List<Customer>> build() async => [];
}

class _FakeSupplierListNotifier extends SupplierListNotifier {
  @override
  Future<List<Supplier>> build() async => [];
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
      home: Material(child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mockAdminUser = UserAccount(
    username: 'admin_test',
    displayName: 'Quản Trị Viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const mockStaffUser = UserAccount(
    username: 'staff_test',
    displayName: 'Nhân Viên',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  final commonOverrides = [
    currentStoreNameProvider
        .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
    availableStoresProvider.overrideWith((ref) async => {
          'store_001': 'Chi nhánh Đông Thắng',
          'store_002': 'Chi nhánh Thới Bình',
        }),
    allBranchesOrdersByDateRangeProvider
        .overrideWith((ref, range) => Stream.value(<Order>[])),
    customerListNotifierProvider
        .overrideWith(() => _FakeCustomerListNotifier()),
    supplierListNotifierProvider
        .overrideWith(() => _FakeSupplierListNotifier()),
    productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
    accountsListProvider
        .overrideWith((ref) => Stream.value(<UserAccount>[mockAdminUser])),
  ];

  group('MorePage Modern Dashboard 5 Blocks Tests', () {
    testWidgets('Admin views all 5 modern blocks and quick store switcher',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      // Block 1: Profile & Store
      expect(find.text('Chi nhánh Đông Thắng'), findsWidgets);
      expect(find.text('Tài khoản: admin_test'), findsOneWidget);
      expect(find.text('Quản trị viên'), findsOneWidget);
      expect(find.text('CHUYỂN ĐỔI CỬA HÀNG'), findsOneWidget);

      // Block 2: Partner Management
      expect(find.text('QUẢN LÝ ĐỐI TÁC'), findsOneWidget);
      expect(find.text('Khách hàng'), findsOneWidget);
      expect(find.text('Nhà cung cấp'), findsOneWidget);

      // Block 3: Warehouse & Operations
      expect(find.text('NGHIỆP VỤ KHO & BÁN HÀNG'), findsOneWidget);
      expect(find.text('Nhập hàng'), findsOneWidget);
      expect(find.text('Chuyển kho'), findsOneWidget);
      expect(find.text('Hóa đơn & Sổ quỹ'), findsOneWidget);

      // Block 4: Configuration & Admin (Admin only)
      expect(find.text('CẤU HÌNH & QUẢN TRỊ'), findsOneWidget);
      expect(find.text('Cấu hình VietQR'), findsOneWidget);
      expect(find.text('Quản lý tài khoản'), findsOneWidget);

      // Block 5: System & Account
      expect(find.text('HỆ THỐNG'), findsOneWidget);
      expect(find.text('Đổi mật khẩu'), findsOneWidget);
      expect(find.text('Đăng xuất'), findsOneWidget);
    });

    testWidgets('Staff views limited blocks without Admin config or Store switcher',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockStaffUser)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      // Block 1: Profile
      expect(find.text('Tài khoản: staff_test'), findsOneWidget);
      expect(find.text('Nhân viên'), findsOneWidget);
      expect(find.text('CHUYỂN ĐỔI CỬA HÀNG'), findsNothing);

      // Block 2 & 3 visible
      expect(find.text('QUẢN LÝ ĐỐI TÁC'), findsOneWidget);
      expect(find.text('NGHIỆP VỤ KHO & BÁN HÀNG'), findsOneWidget);

      // Block 4 hidden
      expect(find.text('CẤU HÌNH & QUẢN TRỊ'), findsNothing);
      expect(find.text('Cấu hình VietQR'), findsNothing);

      // Block 5 visible
      expect(find.text('HỆ THỐNG'), findsOneWidget);
    });

    testWidgets('Navigation to CustomersPage', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Khách hàng'));
      await tester.tap(find.text('Khách hàng'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomersPage), findsOneWidget);
    });

    testWidgets('Navigation to SuppliersPage', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Nhà cung cấp'));
      await tester.tap(find.text('Nhà cung cấp'));
      await tester.pumpAndSettle();
      expect(find.byType(SuppliersPage), findsOneWidget);
    });

    testWidgets('Navigation to ImportInventoryPage', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Nhập hàng'));
      await tester.tap(find.text('Nhập hàng'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportInventoryPage), findsOneWidget);
    });

    testWidgets('Navigation to InterStoreTransferPage', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Chuyển kho'));
      await tester.tap(find.text('Chuyển kho'));
      await tester.pumpAndSettle();
      expect(find.byType(InterStoreTransferPage), findsOneWidget);
    });

    testWidgets('Navigation to InvoicesPage', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Hóa đơn & Sổ quỹ'));
      await tester.tap(find.text('Hóa đơn & Sổ quỹ'));
      await tester.pumpAndSettle();
      expect(find.byType(InvoicesPage), findsOneWidget);
    });

    testWidgets('Navigation to StorePaymentSettingsPage', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Cấu hình VietQR'));
      await tester.tap(find.text('Cấu hình VietQR'));
      await tester.pumpAndSettle();
      expect(find.byType(StorePaymentSettingsPage), findsOneWidget);
    });

    testWidgets('Navigation to AccountManagementPage', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Quản lý tài khoản'));
      await tester.tap(find.text('Quản lý tài khoản'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountManagementPage), findsOneWidget);
    });

    testWidgets('Opening Change Password and Logout dialogs', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Đổi mật khẩu'));
      await tester.tap(find.text('Đổi mật khẩu'));
      await tester.pumpAndSettle();
      expect(find.text('Đổi Mật Khẩu'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();

      // Tap Đăng xuất
      await tester.ensureVisible(find.text('Đăng xuất'));
      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();
      expect(
          find.text('Bạn có chắc chắn muốn đăng xuất khỏi ứng dụng?'),
          findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
    });
  });
}
