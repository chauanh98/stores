import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/data/datasources/firebase/store_payment_config_remote_data_source.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/settings/pages/store_payment_settings_page.dart';

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

class _FakeStorePaymentConfigRemoteDataSource
    implements StorePaymentConfigRemoteDataSource {
  StorePaymentConfig? lastSavedConfig;

  @override
  Stream<StorePaymentConfig> watchConfig(String storeId) {
    return Stream.value(lastSavedConfig ?? StorePaymentConfig(storeId: storeId));
  }

  @override
  Future<StorePaymentConfig> fetchConfig(String storeId) async {
    return lastSavedConfig ?? StorePaymentConfig(storeId: storeId);
  }

  @override
  Future<void> saveConfig(StorePaymentConfig config) async {
    lastSavedConfig = config;
  }
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
  Size screenSize = const Size(500, 1200),
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: MediaQuery(
        data: MediaQueryData(size: screenSize),
        child: Material(child: child),
      ),
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
    displayName: 'Nhân Viên Thu Ngân',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const testConfig = StorePaymentConfig(
    storeId: 'store_001',
    storeName: 'TRANG TRÍ NỘI THẤT KHÁNH ĐĂNG',
    address: 'Chợ Cờ Đỏ, Xã Cờ Đỏ, Cần Thơ',
    phone: '0917.865 300',
    bankName: 'VIETINBANK',
    bankId: 'vietinbank',
    accountNo: '0917865300',
    accountName: 'Huỳnh Lê Khánh Đăng',
    footerNote: 'HÀNG ĐẢM BẢO ĐÚNG CHẤT LƯỢNG',
    paperSize: 'k80',
    showVietQR: true,
  );

  group('StorePaymentSettingsPage Widget Tests', () {
    testWidgets('Staff access is blocked with permission guard', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockStaffUser)),
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
      expect(find.text('Lưu Cấu Hình Hóa Đơn'), findsNothing);
    });

    testWidgets('Admin can view all form fields, paper size chips, and preview',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
            storePaymentConfigProvider.overrideWithValue(testConfig),
          ],
          child: const StorePaymentSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('THÔNG TIN CỬA HÀNG TRÊN HÓA ĐƠN'), findsOneWidget);
      expect(find.text('CẤU HÌNH MẪU IN & KHỔ GIẤY'), findsOneWidget);
      expect(find.text('K80 (80mm)'), findsWidgets);
      expect(find.text('K58 (58mm)'), findsOneWidget);
      expect(find.text('A4 (Chuẩn)'), findsOneWidget);
      expect(find.text('In mã VietQR trên hóa đơn'), findsOneWidget);
      expect(find.text('XEM TRƯỚC HÓA ĐƠN IN THỰC TẾ (LIVE PREVIEW)'), findsOneWidget);
      expect(find.text('Lưu Cấu Hình Hóa Đơn'), findsOneWidget);
    });

    testWidgets('Selecting K58 paper size chip updates preview tag', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
            storePaymentConfigProvider.overrideWithValue(testConfig),
          ],
          child: const StorePaymentSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on K58 chip
      await tester.tap(find.text('K58 (58mm)'));
      await tester.pumpAndSettle();

      // Preview should now show K58 tag
      expect(find.text('K58 (58mm)'), findsWidgets);
    });

    testWidgets('Toggling VietQR switch updates live receipt QR visibility',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
            storePaymentConfigProvider.overrideWithValue(testConfig),
          ],
          child: const StorePaymentSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Initially VietQR is on
      expect(find.text('Quét mã VietQR để thanh toán'), findsOneWidget);

      // Toggle switch to false
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // VietQR prompt is now hidden in live preview
      expect(find.text('Quét mã VietQR để thanh toán'), findsNothing);
    });

    testWidgets('Editing store name updates live preview text in real-time',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
            storePaymentConfigProvider.overrideWithValue(testConfig),
          ],
          child: const StorePaymentSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      final storeNameField = find.widgetWithText(TextFormField, 'Tên cửa hàng (Header)');
      expect(storeNameField, findsOneWidget);

      await tester.enterText(storeNameField, 'CỬA HÀNG ĐỒ GỖ HOÀNG GIA');
      await tester.pumpAndSettle();

      expect(find.text('CỬA HÀNG ĐỒ GỖ HOÀNG GIA'), findsWidgets);
    });

    testWidgets('Saving updated receipt configuration calls data source with updated config',
        (tester) async {
      final fakeDataSource = _FakeStorePaymentConfigRemoteDataSource();

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
            storePaymentConfigProvider.overrideWithValue(testConfig),
            storePaymentConfigDataSourceProvider.overrideWithValue(fakeDataSource),
          ],
          child: const StorePaymentSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to K58 and toggle QR off
      await tester.tap(find.text('K58 (58mm)'));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Scroll to save button and tap
      await tester.scrollUntilVisible(
        find.text('Lưu Cấu Hình Hóa Đơn'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Lưu Cấu Hình Hóa Đơn'));
      await tester.pumpAndSettle();

      expect(fakeDataSource.lastSavedConfig, isNotNull);
      expect(fakeDataSource.lastSavedConfig!.paperSize, 'k58');
      expect(fakeDataSource.lastSavedConfig!.showVietQR, isFalse);
    });
  });
}
