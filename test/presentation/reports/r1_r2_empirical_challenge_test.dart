import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/core/constants/app_constants.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/reports/widgets/kpi_metrics_section.dart';
import 'package:stores/presentation/reports/widgets/overview_filter_bar.dart';
import 'package:stores/presentation/reports/widgets/overview_header.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';
import 'package:stores/presentation/settings/pages/store_payment_settings_page.dart';

class _DynamicAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _DynamicAuthNotifier(super.state);

  void setUser(UserAccount? user) {
    state = user;
  }

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
  Size screenSize = const Size(400, 850),
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
  final currencyFormat = NumberFormat('#,###', 'vi_VN');

  const mockAdminUser = UserAccount(
    username: 'admin_test',
    displayName: 'Quản Trị Viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const mockSupervisorUser = UserAccount(
    username: 'sup_test',
    displayName: 'Giám Sát Viên',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const mockStaffUser = UserAccount(
    username: 'staff_test',
    displayName: 'Nhân Viên Thu Ngân',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const standardKPIs = OverviewKPIs(
    netRevenue: 45000000.0,
    orderCount: 88,
    grossProfit: 15500000.0,
    returnGoodsValue: 500000.0,
    aov: 511363.6,
    revenueGrowthPercent: 12.5,
    orderCountGrowthPercent: 8.0,
    profitGrowthPercent: 10.2,
    aovGrowthPercent: 4.1,
    customerDebt: 18200000.0,
  );

  group('Requirement R2 - Permission Boundaries & Edge Case Matrix', () {
    test('1. Admin role permissions (role: "admin")', () {
      const admin = UserAccount(
        username: 'admin_matrix',
        role: 'admin',
        storeId: 'store_001',
      );

      // Core requirements for Admin
      expect(admin.isAdmin, isTrue);
      expect(admin.isSupervisor, isFalse);
      expect(admin.isStaff, isFalse);
      expect(admin.canSwitchStore, isTrue,
          reason: 'Admin MUST be able to switch store (R2)');
      expect(admin.canManagePaymentConfig, isTrue,
          reason: 'Admin MUST be able to manage VietQR (R2)');
      expect(admin.canViewDebtSummary, isTrue,
          reason: 'Admin MUST be able to view customer debt summary (R2)');
      expect(admin.canViewCostPrice, isTrue,
          reason: 'Admin CAN view cost price/gross profit (Store Owner)');

      // Other admin permissions
      expect(admin.canManageProducts, isTrue);
      expect(admin.canDeleteInvoice, isTrue);
      expect(admin.canDeleteCustomer, isTrue);
      expect(admin.canEditPriceAndDiscount, isTrue);
    });

    test('2. Supervisor role permissions (role: "supervisor")', () {
      const sup = UserAccount(
        username: 'sup_matrix',
        role: 'supervisor',
        storeId: 'store_001',
      );

      // Core requirements for Supervisor
      expect(sup.isAdmin, isFalse);
      expect(sup.isSupervisor, isTrue);
      expect(sup.isStaff, isFalse);
      expect(sup.canSwitchStore, isTrue);
      expect(sup.canManagePaymentConfig, isFalse);
      expect(sup.canViewDebtSummary, isTrue);
      expect(sup.canViewCostPrice, isTrue);

      // Other supervisor permissions
      expect(sup.canManageProducts, isTrue);
      expect(sup.canDeleteInvoice, isFalse);
      expect(sup.canDeleteCustomer, isFalse);
      expect(sup.canEditPriceAndDiscount, isTrue);
    });

    test('3. Staff role permissions (role: "nhanvien")', () {
      const staff = UserAccount(
        username: 'staff_matrix',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      // Core requirements for Staff: all 4 permissions FALSE
      expect(staff.isAdmin, isFalse);
      expect(staff.isSupervisor, isFalse);
      expect(staff.isStaff, isTrue);
      expect(staff.canSwitchStore, isFalse);
      expect(staff.canManagePaymentConfig, isFalse);
      expect(staff.canViewDebtSummary, isFalse);
      expect(staff.canViewCostPrice, isFalse);

      // Other staff permissions
      expect(staff.canManageProducts, isFalse);
      expect(staff.canDeleteInvoice, isFalse);
      expect(staff.canDeleteCustomer, isFalse);
      expect(staff.canEditPriceAndDiscount, isFalse);
    });

    test('4. Role casing variations & trimming', () {
      final roleCases = [
        ('ADMIN', true, false, true, true, true, true),
        ('Admin', true, false, true, true, true, true),
        ('aDmIn', true, false, true, true, true, true),
        ('  admin \n', true, false, true, true, true, true),
        ('SUPERVISOR', false, true, true, false, true, true),
        ('Supervisor', false, true, true, false, true, true),
        ('  supervisor\t', false, true, true, false, true, true),
        ('NHANVIEN', false, false, false, false, false, false),
        ('NhanVien', false, false, false, false, false, false),
        (' nhanvien ', false, false, false, false, false, false),
      ];

      for (final (
            roleStr,
            expAdmin,
            expSup,
            expSwitch,
            expPay,
            expDebt,
            expCost
          ) in roleCases) {
        final user = UserAccount(
          username: 'user_case',
          role: roleStr,
          storeId: 'store_001',
        );

        expect(user.isAdmin, equals(expAdmin),
            reason: 'isAdmin failed for "$roleStr"');
        expect(user.isSupervisor, equals(expSup),
            reason: 'isSupervisor failed for "$roleStr"');
        expect(user.canSwitchStore, equals(expSwitch),
            reason: 'canSwitchStore failed for "$roleStr"');
        expect(user.canManagePaymentConfig, equals(expPay),
            reason: 'canManagePaymentConfig failed for "$roleStr"');
        expect(user.canViewDebtSummary, equals(expDebt),
            reason: 'canViewDebtSummary failed for "$roleStr"');
        expect(user.canViewCostPrice, equals(expCost),
            reason: 'canViewCostPrice failed for "$roleStr"');
      }
    });

    test('5. Edge-case, unknown and malicious roles fail-safe to Staff', () {
      final edgeRoles = [
        '',
        ' ',
        '   \n\t',
        'manager',
        'guest',
        'root',
        'superuser',
        'ADMINISTRATOR',
        'boss',
        'cashier',
        'staff',
        'admin_test',
        'supervisor_store',
        'admin; DROP TABLE users;--',
        '<script>alert(1)</script>',
      ];

      for (final roleStr in edgeRoles) {
        final user = UserAccount(
          username: 'edge_user',
          role: roleStr,
          storeId: 'store_001',
        );

        expect(user.isAdmin, isFalse,
            reason: 'Edge role "$roleStr" must NOT be admin');
        expect(user.isSupervisor, isFalse,
            reason: 'Edge role "$roleStr" must NOT be supervisor');
        expect(user.isStaff, isTrue,
            reason: 'Edge role "$roleStr" must default to staff');
        expect(user.canSwitchStore, isFalse,
            reason: 'Edge role "$roleStr" must NOT switch stores');
        expect(user.canManagePaymentConfig, isFalse,
            reason: 'Edge role "$roleStr" must NOT manage payment');
        expect(user.canViewDebtSummary, isFalse,
            reason: 'Edge role "$roleStr" must NOT view debt summary');
        expect(user.canViewCostPrice, isFalse,
            reason: 'Edge role "$roleStr" must NOT view cost price');
      }
    });

    test('6. UserAccount.fromMap robust deserialization', () {
      final malformedInputs = [
        <dynamic, dynamic>{},
        <dynamic, dynamic>{'role': null},
        <dynamic, dynamic>{'role': 12345},
        <dynamic, dynamic>{'role': true},
        <dynamic, dynamic>{
          'role': ['admin']
        },
        <dynamic, dynamic>{
          'role': {'admin': true}
        },
      ];

      for (final map in malformedInputs) {
        final user = UserAccount.fromMap('deser_user', map);
        expect(user.isAdmin, isFalse);
        expect(user.isSupervisor, isFalse);
        expect(user.isStaff, isTrue);
        expect(user.canSwitchStore, isFalse);
        expect(user.canManagePaymentConfig, isFalse);
        expect(user.canViewDebtSummary, isFalse);
        expect(user.canViewCostPrice, isFalse);
      }
    });
  });

  group('Requirement R1 - OverviewHeader Streamlining & Zero Refresh Icon', () {
    testWidgets('Header has NO refresh icon or button across all roles',
        (tester) async {
      final authNotifier = _DynamicAuthNotifier(mockAdminUser);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Trung Tâm'),
          ],
          child: const OverviewHeader(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify NO refresh icons
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(find.byIcon(Icons.autorenew), findsNothing);
      expect(find.byIcon(Icons.sync), findsNothing);

      // Verify App name and Sync status badge
      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(find.text('Đã đồng bộ'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);

      // Switch to Supervisor
      authNotifier.setUser(mockSupervisorUser);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(find.text('Giám sát'), findsOneWidget);

      // Switch to Staff
      authNotifier.setUser(mockStaffUser);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(find.text('Admin'), findsNothing);
      expect(find.text('Giám sát'), findsNothing);
    });
  });

  group(
      'Requirement R1 & R2 - OverviewFilterBar Single Row & Branch Interactivity',
      () {
    testWidgets('OverviewFilterBar is single-row: quick chip row is eliminated',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
          ],
          child: const OverviewFilterBar(),
        ),
      );
      await tester.pumpAndSettle();

      // Main bar shows Date Range selector & Branch selector
      expect(find.text('Hôm nay'), findsOneWidget);
      expect(find.text('Tất cả chi nhánh'), findsOneWidget);

      // Redundant quick filter chips are NOT in the main bar row
      expect(find.text('Tháng này'), findsNothing);
      expect(find.text('Hôm qua'), findsNothing);
      expect(find.text('7 ngày qua'), findsNothing);
      expect(find.text('Tháng trước'), findsNothing);
    });

    testWidgets(
        'Admin: Branch selector is interactive and opens branch picker bottom sheet',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
          ],
          child: const OverviewFilterBar(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap branch dropdown
      await tester.tap(find.text('Tất cả chi nhánh'));
      await tester.pumpAndSettle();

      // BottomSheet is displayed
      expect(find.text('Chọn chi nhánh lọc'), findsOneWidget);
      expect(find.text('Chọn tất cả'), findsOneWidget);
      expect(find.text('Xong'), findsOneWidget);

      // Tap 'Xong' to dismiss
      await tester.tap(find.text('Xong'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn chi nhánh lọc'), findsNothing);
    });

    testWidgets(
        'Admin: Branch selector is interactive and opens branch picker bottom sheet',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
          ],
          child: const OverviewFilterBar(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap branch dropdown
      await tester.tap(find.text('Tất cả chi nhánh'));
      await tester.pumpAndSettle();

      expect(find.text('Chọn chi nhánh lọc'), findsOneWidget);
      expect(find.text('Chọn tất cả'), findsOneWidget);
    });

    testWidgets(
        'Staff: Branch selector is LOCKED to single branch (static text/icon) and does NOT open modal on tap',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _DynamicAuthNotifier(mockStaffUser)),
          ],
          child: const OverviewFilterBar(),
        ),
      );
      await tester.pumpAndSettle();

      // Staff is locked to their single branch (Chi nhánh Đông Thắng)
      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.text('Tất cả chi nhánh'), findsNothing);

      // Dropdown chevron arrow on branch selector is NOT present for staff
      // (Only the date range selector has keyboard_arrow_down_rounded)
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

      // Attempt to tap the branch text
      await tester.tap(find.text('Chi nhánh Đông Thắng'));
      await tester.pumpAndSettle();

      // BottomSheet must NOT open
      expect(find.text('Chọn chi nhánh lọc'), findsNothing);
    });
  });

  group(
      'Requirement R2 - KPIMetricsSection Gross Profit & Debt Summary Isolation',
      () {
    testWidgets(
        'Admin: Debt summary IS visible, Gross Profit IS VISIBLE and toggleable',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
            profitVisibilityProvider.overrideWith((ref) => true),
            overviewKPIsProvider
                .overrideWith((ref) => const AsyncValue.data(standardKPIs)),
          ],
          child: const SingleChildScrollView(child: KPIMetricsSection()),
        ),
      );
      await tester.pumpAndSettle();

      // Net revenue visible
      expect(find.text('Doanh thu thuần'), findsOneWidget);
      expect(find.text('${currencyFormat.format(standardKPIs.netRevenue)} đ'),
          findsOneWidget);

      // Gross profit VISIBLE
      expect(find.text('Lợi nhuận gộp'), findsOneWidget);
      expect(find.text('${currencyFormat.format(standardKPIs.grossProfit)} đ'),
          findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      // Customer debt summary IS VISIBLE
      expect(find.text('Công nợ khách hàng cần thu'), findsOneWidget);
      expect(find.text('${currencyFormat.format(standardKPIs.customerDebt)} đ'),
          findsOneWidget);
      expect(find.text('Sổ nợ'), findsOneWidget);
    });

    testWidgets(
        'Supervisor: Debt summary IS visible, Gross Profit IS VISIBLE and toggleable',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith(
                (ref) => _DynamicAuthNotifier(mockSupervisorUser)),
            profitVisibilityProvider.overrideWith((ref) => true),
            overviewKPIsProvider
                .overrideWith((ref) => const AsyncValue.data(standardKPIs)),
          ],
          child: const SingleChildScrollView(child: KPIMetricsSection()),
        ),
      );
      await tester.pumpAndSettle();

      // Both visible
      expect(find.text('Doanh thu thuần'), findsOneWidget);
      expect(find.text('Lợi nhuận gộp'), findsOneWidget);
      expect(find.text('${currencyFormat.format(standardKPIs.grossProfit)} đ'),
          findsOneWidget);
      expect(find.text('Công nợ khách hàng cần thu'), findsOneWidget);

      // Toggle profit visibility
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(find.text('*** ***'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });

    testWidgets('Staff: BOTH Debt summary and Gross Profit are STRICTLY HIDDEN',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _DynamicAuthNotifier(mockStaffUser)),
            profitVisibilityProvider.overrideWith((ref) => true),
            overviewKPIsProvider
                .overrideWith((ref) => const AsyncValue.data(standardKPIs)),
          ],
          child: const SingleChildScrollView(child: KPIMetricsSection()),
        ),
      );
      await tester.pumpAndSettle();

      // Net revenue visible
      expect(find.text('Doanh thu thuần'), findsOneWidget);

      // Gross profit HIDDEN
      expect(find.text('Lợi nhuận gộp'), findsNothing);
      expect(find.text('${currencyFormat.format(standardKPIs.grossProfit)} đ'),
          findsNothing);

      // Debt summary HIDDEN
      expect(find.text('Công nợ khách hàng cần thu'), findsNothing);
      expect(find.text('${currencyFormat.format(standardKPIs.customerDebt)} đ'),
          findsNothing);
    });
  });

  group('Requirement R2 - VietQR Payment Config & MorePage Permissions', () {
    testWidgets('Admin: VietQR config is accessible on MorePage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thời Bình',
                }),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình VietQR'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('CHUYỂN ĐỔI CỬA HÀNG'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('CHUYỂN ĐỔI CỬA HÀNG'), findsOneWidget);
    });

    testWidgets(
        'Supervisor: VietQR config and Store Switching are HIDDEN on MorePage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith(
                (ref) => _DynamicAuthNotifier(mockSupervisorUser)),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thời Bình',
                }),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình VietQR'), findsNothing);
      expect(find.text('CHUYỂN ĐỔI CỬA HÀNG'), findsNothing);
    });

    testWidgets(
        'Staff: VietQR config and Store Switching are HIDDEN on MorePage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _DynamicAuthNotifier(mockStaffUser)),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thời Bình',
                }),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình VietQR'), findsNothing);
      expect(find.text('CHUYỂN ĐỔI CỬA HÀNG'), findsNothing);
    });

    testWidgets('StorePaymentSettingsPage guards against Staff access',
        (tester) async {
      const mockConfig = StorePaymentConfig(
        storeId: 'store_001',
        storeName: 'Test Store',
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _DynamicAuthNotifier(mockStaffUser)),
            storePaymentConfigProvider.overrideWithValue(mockConfig),
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

    testWidgets('StorePaymentSettingsPage allows Admin access and editing',
        (tester) async {
      const mockConfig = StorePaymentConfig(
        storeId: 'store_001',
        storeName: 'Test Store',
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider
                .overrideWith((ref) => _DynamicAuthNotifier(mockAdminUser)),
            storePaymentConfigProvider.overrideWithValue(mockConfig),
          ],
          child: const StorePaymentSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('THÔNG TIN CỬA HÀNG TRÊN HÓA ĐƠN'), findsOneWidget);
      expect(find.text('Lưu Cấu Hình Hóa Đơn'), findsOneWidget);
    });
  });

  group('Adversarial Stress Test: Rapid Live Role Transitions (50+ switches)',
      () {
    testWidgets(
        'Mounted tree handles rapid live switches between Supervisor, Admin, Staff and Unknown roles without error',
        (tester) async {
      final authNotifier = _DynamicAuthNotifier(mockSupervisorUser);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => authNotifier),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
            overviewKPIsProvider
                .overrideWith((ref) => const AsyncValue.data(standardKPIs)),
            profitVisibilityProvider.overrideWith((ref) => true),
          ],
          child: const SingleChildScrollView(
            child: Column(
              children: [
                OverviewHeader(),
                OverviewFilterBar(),
                KPIMetricsSection(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Role cycle
      final roles = [
        mockSupervisorUser,
        mockAdminUser,
        mockStaffUser,
        const UserAccount(
          username: 'edge_guest',
          role: 'guest',
          storeId: 'store_001',
        ),
        const UserAccount(
          username: 'edge_upper',
          role: 'ADMIN',
          storeId: 'store_001',
        ),
        const UserAccount(
          username: 'edge_upper_sup',
          role: 'SUPERVISOR',
          storeId: 'store_001',
        ),
      ];

      for (var i = 0; i < 60; i++) {
        final currentRole = roles[i % roles.length];
        authNotifier.setUser(currentRole);
        await tester.pump();

        if (currentRole.isSupervisor) {
          expect(find.text('Giám sát'), findsOneWidget);
          expect(find.text('Lợi nhuận gộp'), findsOneWidget);
          expect(find.text('Công nợ khách hàng cần thu'), findsOneWidget);
        } else if (currentRole.isAdmin) {
          expect(find.text('Admin'), findsOneWidget);
          expect(find.text('Lợi nhuận gộp'), findsOneWidget);
          expect(find.text('Công nợ khách hàng cần thu'), findsOneWidget);
        } else {
          expect(find.text('Admin'), findsNothing);
          expect(find.text('Giám sát'), findsNothing);
          expect(find.text('Lợi nhuận gộp'), findsNothing);
          expect(find.text('Công nợ khách hàng cần thu'), findsNothing);
        }
      }

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
