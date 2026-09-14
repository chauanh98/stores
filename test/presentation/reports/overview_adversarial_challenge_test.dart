import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:stores/presentation/customers/widgets/customer_list_tile.dart';
import 'package:stores/presentation/reports/widgets/kpi_metrics_section.dart';
import 'package:stores/presentation/reports/widgets/overview_header.dart';

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

Widget _createAdversarialTestWidget({
  required Widget child,
  List<Override> overrides = const [],
  Size screenSize = const Size(360, 800),
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

  const mockStaff = UserAccount(
    username: 'staff_adversarial',
    displayName: 'Staff Adversary',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const mockAdmin = UserAccount(
    username: 'admin_adversarial',
    displayName: 'Admin User',
    role: 'admin',
    storeId: 'store_001',
  );

  const mockSupervisor = UserAccount(
    username: 'supervisor_adversarial',
    displayName: 'Supervisor Master',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const mockUnknownRole = UserAccount(
    username: 'attacker',
    displayName: null,
    role: 'unknown_role',
    storeId: '',
  );

  group('Adversarial Challenge 1: Staff OverviewHeader Tap & Scope Security', () {
    testWidgets(
        'Staff user cannot trigger store selection modal by tapping anywhere on OverviewHeader',
        (tester) async {
      await tester.pumpWidget(
        _createAdversarialTestWidget(
          child: const OverviewHeader(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockStaff)),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Độc Quyền'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Độc Quyền',
                  'store_002': 'Chi nhánh Bí Mật Khác',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.text('Chi nhánh Độc Quyền'), findsOneWidget);

      // Attempt tapping on store name text
      await tester.tap(find.text('Chi nhánh Độc Quyền'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn cửa hàng hiển thị'), findsNothing);
      expect(find.text('Tất cả chi nhánh gộp'), findsNothing);
      expect(find.text('Chi nhánh Bí Mật Khác'), findsNothing);

      // Attempt tapping anywhere on the header container
      await tester.tap(find.byType(OverviewHeader));
      await tester.pumpAndSettle();
      expect(find.text('Chọn cửa hàng hiển thị'), findsNothing);
    });

    testWidgets(
        'Unknown/unrecognized role defaults to Staff behavior (no role badge)',
        (tester) async {
      await tester.pumpWidget(
        _createAdversarialTestWidget(
          child: const OverviewHeader(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(mockUnknownRole)),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Mặc Định'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Admin'), findsNothing);
      expect(find.text('Giám sát'), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.text('Chi nhánh Mặc Định'), findsOneWidget);
    });

    testWidgets(
        'Admin user without supervisor role renders Admin badge and current store',
        (tester) async {
      await tester.pumpWidget(
        _createAdversarialTestWidget(
          child: const OverviewHeader(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdmin)),
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Admin'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Admin'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.text('Chi nhánh Admin'), findsOneWidget);

      await tester.tap(find.text('Chi nhánh Admin'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn cửa hàng hiển thị'), findsNothing);
    });
  });

  group('Adversarial Challenge 2: Missing Store Names, Long Names & Provider Failures', () {
    testWidgets('Handles store name provider error gracefully for Staff',
        (tester) async {
      await tester.pumpWidget(
        _createAdversarialTestWidget(
          child: const OverviewHeader(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockStaff)),
            currentStoreNameProvider.overrideWith((ref) =>
                Future.error(Exception('Database connection failed!'))),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Fallback text
      expect(find.text('Cửa hàng'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    });

    testWidgets('Handles available stores error gracefully for Supervisor',
        (tester) async {
      await tester.pumpWidget(
        _createAdversarialTestWidget(
          child: const OverviewHeader(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(mockSupervisor)),
            availableStoresProvider.overrideWith((ref) =>
                Future.error(Exception('Firebase network timeout'))),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Giám sát'), findsOneWidget);
      expect(find.text('Cửa hàng'), findsOneWidget);
    });

    testWidgets(
        'Handles ultra-long store names without layout overflow on narrow screen (320px)',
        (tester) async {
      const ultraLongStoreName =
          'Chi nhánh Siêu Thị Điện Máy Công Nghệ Cao Cấp Toàn Quốc Khu Vực 99999 TP.HCM';

      await tester.pumpWidget(
        _createAdversarialTestWidget(
          screenSize: const Size(320, 600),
          child: const OverviewHeader(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockStaff)),
            currentStoreNameProvider
                .overrideWith((ref) async => ultraLongStoreName),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(ultraLongStoreName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Adversarial Challenge 3: Staff Debt Summary Visibility & Security', () {
    testWidgets(
        'Staff user cannot see or tap "Công nợ khách hàng cần thu" in KPIMetricsSection',
        (tester) async {
      const mockKPIs = OverviewKPIs(
        netRevenue: 50000000.0,
        orderCount: 100,
        grossProfit: 20000000.0,
        returnGoodsValue: 0.0,
        aov: 500000.0,
        revenueGrowthPercent: 25.0,
        orderCountGrowthPercent: 10.0,
        profitGrowthPercent: 15.0,
        aovGrowthPercent: 13.6,
        customerDebt: 95000000.0, // High aggregate debt
      );

      await tester.pumpWidget(
        _createAdversarialTestWidget(
          child: const KPIMetricsSection(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockStaff)),
            profitVisibilityProvider.overrideWith((ref) => true),
            overviewKPIsProvider
                .overrideWith((ref) => const AsyncValue.data(mockKPIs)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Debt summary card must be completely missing
      expect(find.text('Công nợ khách hàng cần thu'), findsNothing);
      expect(find.text('${currencyFormat.format(95000000.0)} đ'), findsNothing);
      expect(find.text('Sổ nợ'), findsNothing);
      expect(find.byIcon(Icons.account_balance_wallet_rounded), findsNothing);

      // Attempt to tap visible areas in the metrics widget
      await tester.tap(find.text('Doanh thu thuần'));
      await tester.pumpAndSettle();

      // Ensure no navigation to CustomersPage happened
      expect(find.byType(CustomersPage), findsNothing);
    });

    testWidgets(
        'Admin user CAN see customer debt card and tap to navigate to CustomersPage',
        (tester) async {
      const mockKPIs = OverviewKPIs(
        netRevenue: 50000000.0,
        orderCount: 100,
        grossProfit: 20000000.0,
        returnGoodsValue: 0.0,
        aov: 500000.0,
        revenueGrowthPercent: 25.0,
        orderCountGrowthPercent: 10.0,
        profitGrowthPercent: 15.0,
        aovGrowthPercent: 13.6,
        customerDebt: 12500000.0,
      );

      await tester.pumpWidget(
        _createAdversarialTestWidget(
          child: const KPIMetricsSection(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdmin)),
            profitVisibilityProvider.overrideWith((ref) => true),
            overviewKPIsProvider
                .overrideWith((ref) => const AsyncValue.data(mockKPIs)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Công nợ khách hàng cần thu'), findsOneWidget);
      expect(find.text('${currencyFormat.format(12500000.0)} đ'), findsOneWidget);
      expect(find.text('Sổ nợ'), findsOneWidget);

      // Tap on the debt card
      await tester.tap(find.text('Công nợ khách hàng cần thu'));
      await tester.pumpAndSettle();

      // CustomersPage should be pushed
      expect(find.byType(CustomersPage), findsOneWidget);
    });
  });

  group('Adversarial Challenge 4: Zero, Negative & Extreme Numbers Stress Test', () {
    testWidgets('KPIMetricsSection renders zero debt, zero revenue, zero orders safely',
        (tester) async {
      const zeroKPIs = OverviewKPIs(
        netRevenue: 0.0,
        orderCount: 0,
        grossProfit: 0.0,
        returnGoodsValue: 0.0,
        aov: 0.0,
        revenueGrowthPercent: 0.0,
        orderCountGrowthPercent: 0.0,
        profitGrowthPercent: 0.0,
        aovGrowthPercent: 0.0,
        customerDebt: 0.0,
      );

      await tester.pumpWidget(
        _createAdversarialTestWidget(
          child: const KPIMetricsSection(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockSupervisor)),
            profitVisibilityProvider.overrideWith((ref) => true),
            overviewKPIsProvider
                .overrideWith((ref) => const AsyncValue.data(zeroKPIs)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 đ'), findsNWidgets(4)); // Revenue, Profit, AOV, Debt
      expect(find.text('0'), findsOneWidget); // Order count
      expect(find.text('0.0%'), findsNWidgets(2)); // Revenue & Profit growth badges
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'KPIMetricsSection renders negative revenue, losses, and negative debt without error',
        (tester) async {
      const negativeKPIs = OverviewKPIs(
        netRevenue: -5000000.0,
        orderCount: 2,
        grossProfit: -12000000.0,
        returnGoodsValue: 7000000.0,
        aov: -2500000.0,
        revenueGrowthPercent: -150.5,
        orderCountGrowthPercent: -80.0,
        profitGrowthPercent: -200.0,
        aovGrowthPercent: -130.0,
        customerDebt: -1500000.0, // Customer overpaid (credit balance)
      );

      await tester.pumpWidget(
        _createAdversarialTestWidget(
          child: const KPIMetricsSection(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockSupervisor)),
            profitVisibilityProvider.overrideWith((ref) => true),
            overviewKPIsProvider
                .overrideWith((ref) => const AsyncValue.data(negativeKPIs)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('${currencyFormat.format(-5000000.0)} đ'), findsOneWidget);
      expect(find.text('${currencyFormat.format(-12000000.0)} đ'), findsOneWidget);
      expect(find.text('${currencyFormat.format(7000000.0)} đ'), findsOneWidget);
      expect(find.text('${currencyFormat.format(-1500000.0)} đ'), findsOneWidget);
      expect(find.text('-150.5%'), findsOneWidget);
      expect(find.text('-200.0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'KPIMetricsSection renders massive numbers (100 trillion VND) without crashing',
        (tester) async {
      const massiveKPIs = OverviewKPIs(
        netRevenue: 99999999999999.0,
        orderCount: 8888888,
        grossProfit: 55555555555555.0,
        returnGoodsValue: 1111111111111.0,
        aov: 11250000.0,
        revenueGrowthPercent: 9999.9,
        orderCountGrowthPercent: 500.0,
        profitGrowthPercent: 8888.8,
        aovGrowthPercent: 400.0,
        customerDebt: 77777777777777.0,
      );

      await tester.pumpWidget(
        _createAdversarialTestWidget(
          screenSize: const Size(360, 900),
          child: const KPIMetricsSection(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockAdmin)),
            profitVisibilityProvider.overrideWith((ref) => true),
            overviewKPIsProvider
                .overrideWith((ref) => const AsyncValue.data(massiveKPIs)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
          find.text('${currencyFormat.format(99999999999999.0)} đ'),
          findsOneWidget);
      expect(find.text('8888888'), findsOneWidget);
      expect(
          find.text('${currencyFormat.format(77777777777777.0)} đ'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Adversarial Challenge 5: Cashier Individual Debt Edge Cases', () {
    testWidgets(
        'Cashier viewing customer with negative debt or 0 debt does not see debt tag',
        (tester) async {
      const customerOverpaid = Customer(
        id: 'cust_neg',
        name: 'Khách Hàng Trả Dư',
        phone: '0911223344',
        email: '',
        address: '',
        purchases: [],
        totalSales: 10000000.0,
        currentDebt: -500000.0, // Negative debt
      );

      await tester.pumpWidget(
        _createAdversarialTestWidget(
          child: const CustomerListTile(customer: customerOverpaid),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockStaff)),
            customerOrdersProvider(customerOverpaid.id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(customerOverpaid.id).overrideWith(
                (ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Khách Hàng Trả Dư'), findsOneWidget);
      expect(find.textContaining('Công nợ:'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Cashier viewing customer with extreme debt renders formatted number correctly',
        (tester) async {
      const customerHugeDebt = Customer(
        id: 'cust_huge',
        name: 'Khách Hàng Nợ Lớn',
        phone: '0999888777',
        email: '',
        address: '',
        purchases: [],
        totalSales: 500000000000.0,
        currentDebt: 120000000000.0, // 120 billion VND
      );

      await tester.pumpWidget(
        _createAdversarialTestWidget(
          child: const CustomerListTile(customer: customerHugeDebt),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(mockStaff)),
            customerOrdersProvider(customerHugeDebt.id)
                .overrideWith((ref) => Stream.value(<Order>[])),
            customerDebtTransactionsProvider(customerHugeDebt.id).overrideWith(
                (ref) => Stream.value(<CustomerDebtTransaction>[])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Khách Hàng Nợ Lớn'), findsOneWidget);
      expect(
          find.text('Công nợ: ${currencyFormat.format(120000000000.0)}'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
