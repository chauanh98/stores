import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/core/utils/invoice_print_helper.dart';
import 'package:stores/data/datasources/firebase/auth_remote_data_source.dart';
import 'package:stores/data/datasources/firebase/store_payment_config_remote_data_source.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
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

// ---------------------------------------------------------------------------
// Test Doubles & Mock Implementations
// ---------------------------------------------------------------------------

class _TestAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _TestAuthNotifier(super.state);

  int logoutCallCount = 0;

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    logoutCallCount++;
    state = null;
  }
}

class _TestStorePaymentConfigRemoteDataSource
    implements StorePaymentConfigRemoteDataSource {
  StorePaymentConfig? lastSavedConfig;
  bool shouldThrowOnSave = false;
  String? saveErrorMessage;

  @override
  Stream<StorePaymentConfig> watchConfig(String storeId) {
    return Stream.value(
      lastSavedConfig ?? StorePaymentConfig(storeId: storeId),
    );
  }

  @override
  Future<StorePaymentConfig> fetchConfig(String storeId) async {
    return lastSavedConfig ?? StorePaymentConfig(storeId: storeId);
  }

  @override
  Future<void> saveConfig(StorePaymentConfig config) async {
    if (shouldThrowOnSave) {
      throw Exception(saveErrorMessage ?? 'Database connection timeout');
    }
    lastSavedConfig = config;
  }
}

class _TestAuthRemoteDataSource implements AuthRemoteDataSource {
  bool shouldThrowOnUpdatePassword = false;
  String? passwordErrorMessage;
  String? lastUpdatedUsername;
  String? lastUpdatedOldPassword;
  String? lastUpdatedNewPassword;

  @override
  Future<UserAccount?> login(String username, String password) async => null;

  @override
  Stream<List<Map<String, dynamic>>> watchAllAccounts() => Stream.value([]);

  @override
  Future<void> saveAccount(String username, Map<String, dynamic> map) async {}

  @override
  Future<void> deleteAccount(String username) async {}

  @override
  Future<String?> getAccountPassword(String username) async => 'old123';

  @override
  Future<void> updatePassword(
    String username,
    String oldPassword,
    String newPassword,
  ) async {
    if (shouldThrowOnUpdatePassword) {
      throw Exception(passwordErrorMessage ?? 'Mật khẩu hiện tại không chính xác');
    }
    lastUpdatedUsername = username;
    lastUpdatedOldPassword = oldPassword;
    lastUpdatedNewPassword = newPassword;
  }
}

class _TestCustomerListNotifier extends CustomerListNotifier {
  @override
  Future<List<Customer>> build() async => [];
}

class _TestSupplierListNotifier extends SupplierListNotifier {
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

void _setTestViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ---------------------------------------------------------------------------
// Main Challenger 2 Test Suite
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mockAdminUser = UserAccount(
    username: 'admin_vip',
    displayName: 'Tổng Quản Lý Admin',
    role: 'admin',
    storeId: 'store_001',
  );

  const mockSupervisorUser = UserAccount(
    username: 'supervisor_vip',
    displayName: 'Giám Sát Khu Vực',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const mockStaffUser = UserAccount(
    username: 'staff_pos',
    displayName: 'Nhân Viên Bán Hàng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const testConfig = StorePaymentConfig(
    storeId: 'store_001',
    storeName: 'CỬA HÀNG NỘI THẤT HOÀNG GIA',
    address: '123 Đường 30/4, Ninh Kiều, Cần Thơ',
    phone: '0901.234.567',
    bankName: 'VietinBank (ICB)',
    bankId: 'vietinbank',
    accountNo: '101010101010',
    accountName: 'HOANG GIA STORE',
    footerNote: 'CẢM ƠN QUÝ KHÁCH VÀ HẸN GẶP LẠI',
    paperSize: 'k80',
    showVietQR: true,
  );

  final commonMoreOverrides = [
    currentStoreNameProvider.overrideWith(
      (ref) async => 'Chi nhánh Đông Thắng (ĐT)',
    ),
    availableStoresProvider.overrideWith(
      (ref) async => {
        'store_001': 'Chi nhánh Đông Thắng (ĐT)',
        'store_002': 'Chi nhánh Thới Bình (TB)',
      },
    ),
    allBranchesOrdersByDateRangeProvider.overrideWith(
      (ref, range) => Stream.value(<Order>[]),
    ),
    customerListNotifierProvider.overrideWith(
      () => _TestCustomerListNotifier(),
    ),
    supplierListNotifierProvider.overrideWith(
      () => _TestSupplierListNotifier(),
    ),
    productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
    accountsListProvider.overrideWith(
      (ref) => Stream.value(<UserAccount>[mockAdminUser]),
    ),
  ];

  group('CHALLENGER 2: StorePaymentSettingsPage Adversarial Tests', () {
    testWidgets(
      'Staff is blocked by strict RBAC guard with warning banner',
      (tester) async {
        _setTestViewport(tester);
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockStaffUser),
              ),
              storePaymentConfigProvider.overrideWithValue(testConfig),
            ],
            child: const StorePaymentSettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Chỉ tài khoản Quản trị / Giám sát'),
          findsOneWidget,
        );
        expect(find.text('THÔNG TIN CỬA HÀNG TRÊN HÓA ĐƠN'), findsNothing);
        expect(find.text('Lưu Cấu Hình Hóa Đơn'), findsNothing);
      },
    );

    testWidgets(
      'Supervisor has full access and can view payment settings form',
      (tester) async {
        _setTestViewport(tester);
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockSupervisorUser),
              ),
              storePaymentConfigProvider.overrideWithValue(testConfig),
            ],
            child: const StorePaymentSettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Cấu hình Hóa đơn & VietQR'), findsOneWidget);
        expect(find.text('THÔNG TIN CỬA HÀNG TRÊN HÓA ĐƠN'), findsOneWidget);
        expect(find.text('CẤU HÌNH MẪU IN & KHỔ GIẤY'), findsOneWidget);
        expect(find.text('THÔNG TIN TÀI KHOẢN NGÂN HÀNG (VIETQR)'), findsOneWidget);
        expect(find.text('GHI CHÚ CHÂN HÓA ĐƠN (FOOTER)'), findsOneWidget);
        expect(find.text('XEM TRƯỚC HÓA ĐƠN IN THỰC TẾ (LIVE PREVIEW)'), findsOneWidget);
        expect(find.text('Lưu Cấu Hình Hóa Đơn'), findsOneWidget);
      },
    );

    testWidgets(
      'Live Receipt Preview reacts dynamically to all form field changes and blanks fallback gracefully',
      (tester) async {
        _setTestViewport(tester);
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockAdminUser),
              ),
              storePaymentConfigProvider.overrideWithValue(testConfig),
            ],
            child: const StorePaymentSettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Initial preview assertions
        expect(find.text('CỬA HÀNG NỘI THẤT HOÀNG GIA'), findsWidgets);
        expect(find.text('123 Đường 30/4, Ninh Kiều, Cần Thơ'), findsWidgets);
        expect(find.text('Hotline: 0901.234.567'), findsOneWidget);
        expect(find.text('CẢM ƠN QUÝ KHÁCH VÀ HẸN GẶP LẠI'), findsWidgets);

        // 2. Change store name in text field
        final storeNameField = find.widgetWithText(
          TextFormField,
          'Tên cửa hàng (Header)',
        );
        await tester.enterText(storeNameField, 'SIÊU THỊ ĐIỆN MÁY MEGAMART');
        await tester.pumpAndSettle();
        expect(find.text('SIÊU THỊ ĐIỆN MÁY MEGAMART'), findsWidgets);

        // 3. Clear store name -> Should fallback to 'TÊN CỬA HÀNG'
        await tester.enterText(storeNameField, '');
        await tester.pumpAndSettle();
        expect(find.text('TÊN CỬA HÀNG'), findsOneWidget);

        // 4. Change address
        final addressField = find.widgetWithText(
          TextFormField,
          'Địa chỉ cửa hàng',
        );
        await tester.enterText(addressField, '456 Lê Duẩn, Đà Nẵng');
        await tester.pumpAndSettle();
        expect(find.text('456 Lê Duẩn, Đà Nẵng'), findsWidgets);

        // 5. Clear address -> Fallback 'Địa chỉ cửa hàng'
        await tester.enterText(addressField, '');
        await tester.pumpAndSettle();
        expect(find.text('Địa chỉ cửa hàng'), findsWidgets);

        // 6. Change phone
        final phoneField = find.widgetWithText(
          TextFormField,
          'Số điện thoại hotline',
        );
        await tester.enterText(phoneField, '0988.777.666');
        await tester.pumpAndSettle();
        expect(find.text('Hotline: 0988.777.666'), findsOneWidget);

        // 7. Clear phone -> Fallback 'Hotline: 09xx.xxx.xxx'
        await tester.enterText(phoneField, '');
        await tester.pumpAndSettle();
        expect(find.text('Hotline: 09xx.xxx.xxx'), findsOneWidget);

        // 8. Change footer note
        final footerField = find.widgetWithText(
          TextFormField,
          'Dòng cam kết / Lời cảm ơn',
        );
        await tester.enterText(footerField, 'BẢO HÀNH CHÍNH HÃNG 24 THÁNG');
        await tester.pumpAndSettle();
        expect(find.text('BẢO HÀNH CHÍNH HÃNG 24 THÁNG'), findsWidgets);

        // 9. Clear footer note -> Fallback 'HÀNG ĐẢM BẢO ĐÚNG CHẤT LƯỢNG'
        await tester.enterText(footerField, '');
        await tester.pumpAndSettle();
        expect(find.text('HÀNG ĐẢM BẢO ĐÚNG CHẤT LƯỢNG'), findsOneWidget);
      },
    );

    testWidgets(
      'Switching Paper Sizes (K80 -> K58 -> A4) dynamically updates ticket width and badge tags',
      (tester) async {
        _setTestViewport(tester);
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockAdminUser),
              ),
              storePaymentConfigProvider.overrideWithValue(testConfig),
            ],
            child: const StorePaymentSettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        final k80Chip = find.widgetWithText(ChoiceChip, 'K80 (80mm)');
        final k58Chip = find.widgetWithText(ChoiceChip, 'K58 (58mm)');
        final a4Chip = find.widgetWithText(ChoiceChip, 'A4 (Chuẩn)');

        expect(k80Chip, findsOneWidget);
        expect(k58Chip, findsOneWidget);
        expect(a4Chip, findsOneWidget);

        // Select K58
        await tester.tap(k58Chip);
        await tester.pumpAndSettle();
        expect(find.text('K58 (58mm)'), findsWidgets);

        // Select A4
        await tester.tap(a4Chip);
        await tester.pumpAndSettle();
        expect(find.text('A4 (Chuẩn)'), findsWidgets);

        // Switch back to K80
        await tester.tap(k80Chip);
        await tester.pumpAndSettle();
        expect(find.text('K80 (80mm)'), findsWidgets);
      },
    );

    testWidgets(
      'Toggling VietQR switch shows/hides the QR payment block in preview dynamically',
      (tester) async {
        _setTestViewport(tester);
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockAdminUser),
              ),
              storePaymentConfigProvider.overrideWithValue(testConfig),
            ],
            child: const StorePaymentSettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        // Initially QR is displayed
        expect(find.text('Quét mã VietQR để thanh toán'), findsOneWidget);

        // Tap switch to turn off
        final qrSwitch = find.byType(Switch);
        expect(qrSwitch, findsOneWidget);
        await tester.tap(qrSwitch);
        await tester.pumpAndSettle();

        // QR section should be removed from preview
        expect(find.text('Quét mã VietQR để thanh toán'), findsNothing);

        // Tap switch to turn back on
        await tester.tap(qrSwitch);
        await tester.pumpAndSettle();
        expect(find.text('Quét mã VietQR để thanh toán'), findsOneWidget);
      },
    );

    testWidgets(
      'Form validation triggers on empty store name, empty account number, or empty account name',
      (tester) async {
        _setTestViewport(tester);
        final fakeDs = _TestStorePaymentConfigRemoteDataSource();

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockAdminUser),
              ),
              storePaymentConfigProvider.overrideWithValue(testConfig),
              storePaymentConfigDataSourceProvider.overrideWithValue(fakeDs),
            ],
            child: const StorePaymentSettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        // Clear store name
        final storeNameField = find.widgetWithText(
          TextFormField,
          'Tên cửa hàng (Header)',
        );
        await tester.enterText(storeNameField, '');

        // Scroll to save button and tap
        await tester.scrollUntilVisible(
          find.text('Lưu Cấu Hình Hóa Đơn'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Lưu Cấu Hình Hóa Đơn'));
        await tester.pumpAndSettle();

        // Validation error appears
        expect(find.text('Vui lòng nhập tên cửa hàng'), findsOneWidget);
        expect(fakeDs.lastSavedConfig, isNull);

        // Fix store name, clear account number
        await tester.scrollUntilVisible(
          storeNameField,
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(storeNameField, 'Valid Store Name');
        final accountNoField = find.widgetWithText(
          TextFormField,
          'Số tài khoản ngân hàng',
        );
        await tester.enterText(accountNoField, '');

        await tester.scrollUntilVisible(
          find.text('Lưu Cấu Hình Hóa Đơn'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Lưu Cấu Hình Hóa Đơn'));
        await tester.pumpAndSettle();

        expect(find.text('Vui lòng nhập số tài khoản'), findsOneWidget);
        expect(fakeDs.lastSavedConfig, isNull);

        // Fix account number, clear account name
        await tester.scrollUntilVisible(
          accountNoField,
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(accountNoField, '99887766');
        final accountNameField = find.widgetWithText(
          TextFormField,
          'Tên chủ tài khoản (Viết hoa)',
        );
        await tester.enterText(accountNameField, '');

        await tester.scrollUntilVisible(
          find.text('Lưu Cấu Hình Hóa Đơn'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Lưu Cấu Hình Hóa Đơn'));
        await tester.pumpAndSettle();

        expect(find.text('Vui lòng nhập tên chủ tài khoản'), findsOneWidget);
        expect(fakeDs.lastSavedConfig, isNull);
      },
    );

    testWidgets(
      'Saving valid form persists converted uppercase accountName, chosen paper size, and bank details',
      (tester) async {
        _setTestViewport(tester);
        final fakeDs = _TestStorePaymentConfigRemoteDataSource();

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockAdminUser),
              ),
              storePaymentConfigProvider.overrideWithValue(testConfig),
              storePaymentConfigDataSourceProvider.overrideWithValue(fakeDs),
            ],
            child: const StorePaymentSettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Select A4 paper size
        await tester.tap(find.widgetWithText(ChoiceChip, 'A4 (Chuẩn)'));
        await tester.pumpAndSettle();

        // 2. Select Vietcombank from dropdown
        final bankDropdown = find.byType(DropdownButtonFormField<String>);
        await tester.scrollUntilVisible(
          bankDropdown,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(bankDropdown);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Vietcombank (VCB)').last);
        await tester.pumpAndSettle();

        // 3. Enter lower-case account name (should be saved uppercase)
        final accountNameField = find.widgetWithText(
          TextFormField,
          'Tên chủ tài khoản (Viết hoa)',
        );
        await tester.enterText(accountNameField, 'nguyen van admin');

        // 4. Save
        await tester.scrollUntilVisible(
          find.text('Lưu Cấu Hình Hóa Đơn'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Lưu Cấu Hình Hóa Đơn'));
        await tester.pumpAndSettle();

        expect(fakeDs.lastSavedConfig, isNotNull);
        expect(fakeDs.lastSavedConfig!.paperSize, 'a4');
        expect(fakeDs.lastSavedConfig!.bankId, 'vietcombank');
        expect(fakeDs.lastSavedConfig!.accountName, 'NGUYEN VAN ADMIN');
        expect(fakeDs.lastSavedConfig!.showVietQR, isTrue);
      },
    );

    testWidgets(
      'Error during save displays failure SnackBar gracefully without crashing',
      (tester) async {
        _setTestViewport(tester);
        final fakeDs = _TestStorePaymentConfigRemoteDataSource()
          ..shouldThrowOnSave = true
          ..saveErrorMessage = 'Network disconnect';

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockAdminUser),
              ),
              storePaymentConfigProvider.overrideWithValue(testConfig),
              storePaymentConfigDataSourceProvider.overrideWithValue(fakeDs),
            ],
            child: const StorePaymentSettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Lưu Cấu Hình Hóa Đơn'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Lưu Cấu Hình Hóa Đơn'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Lỗi khi lưu cấu hình: Exception: Network disconnect'),
          findsOneWidget,
        );
      },
    );
  });

  group('CHALLENGER 2: MorePage Modern Dashboard Adversarial Tests', () {
    testWidgets(
      'Admin renders all 5 Card Blocks, Store Switcher, and full admin options',
      (tester) async {
        _setTestViewport(tester);
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              ...commonMoreOverrides,
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockAdminUser),
              ),
            ],
            child: const MorePage(),
          ),
        );
        await tester.pumpAndSettle();

        // Block 1: Profile & Store
        expect(find.text('Chi nhánh Đông Thắng (ĐT)'), findsWidgets);
        expect(find.text('Tài khoản: admin_vip'), findsOneWidget);
        expect(find.text('Quản trị viên'), findsOneWidget);
        expect(find.text('CHUYỂN ĐỔI CỬA HÀNG'), findsOneWidget);

        // Block 2: Quản lý đối tác
        expect(find.text('QUẢN LÝ ĐỐI TÁC'), findsOneWidget);
        expect(find.text('Khách hàng'), findsOneWidget);
        expect(find.text('Nhà cung cấp'), findsOneWidget);

        // Block 3: Nghiệp vụ Kho & Bán hàng
        expect(find.text('NGHIỆP VỤ KHO & BÁN HÀNG'), findsOneWidget);
        expect(find.text('Nhập hàng'), findsOneWidget);
        expect(find.text('Chuyển kho'), findsOneWidget);
        expect(find.text('Hóa đơn & Sổ quỹ'), findsOneWidget);

        // Block 4: Cấu hình & Quản trị
        expect(find.text('CẤU HÌNH & QUẢN TRỊ'), findsOneWidget);
        expect(find.text('Cấu hình VietQR'), findsOneWidget);
        expect(find.text('Quản lý tài khoản'), findsOneWidget);

        // Block 5: Hệ thống
        expect(find.text('HỆ THỐNG'), findsOneWidget);
        expect(find.text('Đổi mật khẩu'), findsOneWidget);
        expect(find.text('Đăng xuất'), findsOneWidget);
      },
    );

    testWidgets(
      'Supervisor renders Store Switcher and VietQR config with supervisor privileges',
      (tester) async {
        _setTestViewport(tester);
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              ...commonMoreOverrides,
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockSupervisorUser),
              ),
            ],
            child: const MorePage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tài khoản: supervisor_vip'), findsOneWidget);
        expect(find.text('CHUYỂN ĐỔI CỬA HÀNG'), findsOneWidget);
        expect(find.text('CẤU HÌNH & QUẢN TRỊ'), findsOneWidget);
        expect(find.text('Cấu hình VietQR'), findsOneWidget);
      },
    );

    testWidgets(
      'Staff role is strictly isolated: Store Switcher and Block 4 are completely hidden',
      (tester) async {
        _setTestViewport(tester);
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              ...commonMoreOverrides,
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockStaffUser),
              ),
            ],
            child: const MorePage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tài khoản: staff_pos'), findsOneWidget);
        expect(find.text('Nhân viên'), findsOneWidget);

        // Store Switcher hidden
        expect(find.text('CHUYỂN ĐỔI CỬA HÀNG'), findsNothing);

        // Block 4 completely hidden
        expect(find.text('CẤU HÌNH & QUẢN TRỊ'), findsNothing);
        expect(find.text('Cấu hình VietQR'), findsNothing);
        expect(find.text('Quản lý tài khoản'), findsNothing);

        // Blocks 2, 3, 5 remain available
        expect(find.text('QUẢN LÝ ĐỐI TÁC'), findsOneWidget);
        expect(find.text('NGHIỆP VỤ KHO & BÁN HÀNG'), findsOneWidget);
        expect(find.text('HỆ THỐNG'), findsOneWidget);
      },
    );

    testWidgets(
      'Quick Store Switcher dropdown changes store and triggers snackbar confirmation',
      (tester) async {
        _setTestViewport(tester);
        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              ...commonMoreOverrides,
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockAdminUser),
              ),
            ],
            child: const MorePage(),
          ),
        );
        await tester.pumpAndSettle();

        final switcherDropdown = find.widgetWithText(
          DropdownButtonFormField<String>,
          'Chi nhánh Đông Thắng (ĐT)',
        );
        expect(switcherDropdown, findsOneWidget);

        await tester.tap(switcherDropdown);
        await tester.pumpAndSettle();

        // Select store_002
        await tester.tap(find.text('Chi nhánh Thới Bình (TB)').last);
        await tester.pumpAndSettle();

        expect(
          find.text('Đã chuyển sang Chi nhánh Thới Bình (TB)'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Navigation to CustomersPage from MorePage', (tester) async {
      _setTestViewport(tester);
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonMoreOverrides,
            authProvider.overrideWith((ref) => _TestAuthNotifier(mockAdminUser)),
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

    testWidgets('Navigation to SuppliersPage from MorePage', (tester) async {
      _setTestViewport(tester);
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonMoreOverrides,
            authProvider.overrideWith((ref) => _TestAuthNotifier(mockAdminUser)),
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

    testWidgets('Navigation to ImportInventoryPage from MorePage', (tester) async {
      _setTestViewport(tester);
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonMoreOverrides,
            authProvider.overrideWith((ref) => _TestAuthNotifier(mockAdminUser)),
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

    testWidgets('Navigation to InterStoreTransferPage from MorePage', (tester) async {
      _setTestViewport(tester);
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonMoreOverrides,
            authProvider.overrideWith((ref) => _TestAuthNotifier(mockAdminUser)),
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

    testWidgets('Navigation to InvoicesPage from MorePage', (tester) async {
      _setTestViewport(tester);
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonMoreOverrides,
            authProvider.overrideWith((ref) => _TestAuthNotifier(mockAdminUser)),
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

    testWidgets('Navigation to StorePaymentSettingsPage from MorePage', (tester) async {
      _setTestViewport(tester);
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonMoreOverrides,
            authProvider.overrideWith((ref) => _TestAuthNotifier(mockAdminUser)),
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

    testWidgets('Navigation to AccountManagementPage from MorePage', (tester) async {
      _setTestViewport(tester);
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonMoreOverrides,
            authProvider.overrideWith((ref) => _TestAuthNotifier(mockAdminUser)),
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

    testWidgets(
      'Change Password modal validates empty, short (<4 chars), and mismatch fields, then saves successfully',
      (tester) async {
        _setTestViewport(tester);
        final testAuthRemoteDs = _TestAuthRemoteDataSource();

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              ...commonMoreOverrides,
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockAdminUser),
              ),
              authRemoteDataSourceProvider.overrideWithValue(testAuthRemoteDs),
            ],
            child: const MorePage(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Đổi mật khẩu'));
        await tester.tap(find.text('Đổi mật khẩu'));
        await tester.pumpAndSettle();

        expect(find.text('Đổi Mật Khẩu'), findsOneWidget);

        // 1. Submit empty -> Trigger validation
        await tester.tap(find.text('Lưu mật khẩu'));
        await tester.pumpAndSettle();
        expect(find.text('Vui lòng nhập mật khẩu hiện tại'), findsOneWidget);

        // 2. Enter old password, short new password
        final oldPassField = find.widgetWithText(
          TextFormField,
          'Mật khẩu hiện tại',
        );
        final newPassField = find.widgetWithText(TextFormField, 'Mật khẩu mới');
        final confirmPassField = find.widgetWithText(
          TextFormField,
          'Xác nhận mật khẩu mới',
        );

        await tester.enterText(oldPassField, 'old123');
        await tester.enterText(newPassField, '12'); // <4
        await tester.enterText(confirmPassField, '12');
        await tester.tap(find.text('Lưu mật khẩu'));
        await tester.pumpAndSettle();

        expect(
          find.text('Mật khẩu mới phải từ 4 ký tự trở lên'),
          findsOneWidget,
        );

        // 3. Password mismatch
        await tester.enterText(newPassField, 'newpass123');
        await tester.enterText(confirmPassField, 'differentpass456');
        await tester.tap(find.text('Lưu mật khẩu'));
        await tester.pumpAndSettle();

        expect(find.text('Xác nhận mật khẩu không khớp'), findsOneWidget);

        // 4. Valid matching passwords -> Submit
        await tester.enterText(confirmPassField, 'newpass123');
        await tester.tap(find.text('Lưu mật khẩu'));
        await tester.pumpAndSettle();

        expect(testAuthRemoteDs.lastUpdatedUsername, 'admin_vip');
        expect(testAuthRemoteDs.lastUpdatedOldPassword, 'old123');
        expect(testAuthRemoteDs.lastUpdatedNewPassword, 'newpass123');
        expect(find.text('Đổi mật khẩu thành công!'), findsOneWidget);
      },
    );

    testWidgets(
      'Change Password modal displays remote data source error on incorrect current password',
      (tester) async {
        _setTestViewport(tester);
        final testAuthRemoteDs = _TestAuthRemoteDataSource()
          ..shouldThrowOnUpdatePassword = true
          ..passwordErrorMessage = 'Mật khẩu cũ không chính xác';

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              ...commonMoreOverrides,
              authProvider.overrideWith(
                (ref) => _TestAuthNotifier(mockAdminUser),
              ),
              authRemoteDataSourceProvider.overrideWithValue(testAuthRemoteDs),
            ],
            child: const MorePage(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Đổi mật khẩu'));
        await tester.tap(find.text('Đổi mật khẩu'));
        await tester.pumpAndSettle();

        final oldPassField = find.widgetWithText(
          TextFormField,
          'Mật khẩu hiện tại',
        );
        final newPassField = find.widgetWithText(TextFormField, 'Mật khẩu mới');
        final confirmPassField = find.widgetWithText(
          TextFormField,
          'Xác nhận mật khẩu mới',
        );

        await tester.enterText(oldPassField, 'wrongpassword');
        await tester.enterText(newPassField, 'validpass123');
        await tester.enterText(confirmPassField, 'validpass123');

        await tester.tap(find.text('Lưu mật khẩu'));
        await tester.pumpAndSettle();

        expect(
          find.text('Lỗi: Mật khẩu cũ không chính xác'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Logout confirmation dialog triggers AuthNotifier.logout() upon confirmation and cancels when dismissed',
      (tester) async {
        _setTestViewport(tester);
        final testAuthNotifier = _TestAuthNotifier(mockAdminUser);

        await tester.pumpWidget(
          _buildTestApp(
            overrides: [
              ...commonMoreOverrides,
              authProvider.overrideWith((ref) => testAuthNotifier),
            ],
            child: const MorePage(),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Open Logout Dialog
        await tester.ensureVisible(find.text('Đăng xuất'));
        await tester.tap(find.text('Đăng xuất'));
        await tester.pumpAndSettle();

        expect(
          find.text('Bạn có chắc chắn muốn đăng xuất khỏi ứng dụng?'),
          findsOneWidget,
        );

        // 2. Dismiss with Cancel
        await tester.tap(find.text('Hủy'));
        await tester.pumpAndSettle();
        expect(testAuthNotifier.logoutCallCount, 0);

        // 3. Re-open and confirm Logout
        await tester.ensureVisible(find.text('Đăng xuất'));
        await tester.tap(find.text('Đăng xuất'));
        await tester.pumpAndSettle();

        // Find the FilledButton inside dialog
        final logoutBtn = find.widgetWithText(FilledButton, 'Đăng xuất');
        await tester.tap(logoutBtn);
        await tester.pumpAndSettle();

        expect(testAuthNotifier.logoutCallCount, 1);
      },
    );
  });

  group('CHALLENGER 2: InvoicePrintHelper Multi-Format Stress Tests', () {
    final testOrder = Order(
      id: 'HD000099',
      customerId: 'KH_VIP_01',
      storeId: 'store_001',
      total: 350000,
      amountPaid: 200000,
      paymentMethod: 'split',
      cashAmount: 100000,
      transferAmount: 100000,
      status: 'completed',
      note: 'Giao hàng tận nơi trước 12h trưa',
      items: [
        OrderItem(
          productId: 'prod_1',
          productName: 'Ban ghe an go soi Nga 6 ghe',
          quantity: 1,
          price: 250000,
          warrantyMonths: 12,
          purchaseDate: DateTime(2026, 8, 19),
        ),
        OrderItem(
          productId: 'prod_2',
          productName: 'Dem lot ghe cao cap',
          quantity: 2,
          price: 50000,
          warrantyMonths: 6,
          purchaseDate: DateTime(2026, 8, 19),
        ),
      ],
      createdAt: DateTime(2026, 8, 19, 10, 30),
    );

    const testCustomer = Customer(
      id: 'KH_VIP_01',
      name: 'Nguyen Van Doanh Nghiep',
      phone: '0912.345.678',
      email: 'khvip@example.com',
      address: 'Khu cong nghiep Tra Noc, Can Tho',
      purchases: [],
    );

    test('buildPdf produces non-empty bytes for K80 format', () async {
      final configK80 = testConfig.copyWith(paperSize: 'k80', showVietQR: true);
      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: testOrder,
        customer: testCustomer,
        config: configK80,
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('buildPdf produces non-empty bytes for K58 format', () async {
      final configK58 = testConfig.copyWith(paperSize: 'k58', showVietQR: true);
      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: testOrder,
        customer: testCustomer,
        config: configK58,
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('buildPdf produces non-empty bytes for A4 format with QR disabled', () async {
      final configA4 = testConfig.copyWith(paperSize: 'a4', showVietQR: false);
      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: testOrder,
        customer: testCustomer,
        config: configA4,
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('buildPdf handles guest customer, zero discount, and single cash payment', () async {
      final simpleOrder = Order(
        id: 'HD000100',
        customerId: 'khach_le',
        storeId: 'store_001',
        total: 100000,
        amountPaid: 100000,
        paymentMethod: 'cash',
        status: 'completed',
        items: [
          OrderItem(
            productId: 'prod_simple',
            productName: 'Ly thuy tinh',
            quantity: 2,
            price: 50000,
            warrantyMonths: 0,
            purchaseDate: DateTime(2026, 8, 19),
          ),
        ],
        createdAt: DateTime(2026, 8, 19, 11, 00),
      );

      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: simpleOrder,
        customer: null,
        config: testConfig.copyWith(paperSize: 'k80'),
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.length, greaterThan(500));
    });
  });
}
