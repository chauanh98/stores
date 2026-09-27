import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/orders/controllers/invoices_filter_controller.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';

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

class _FakeCustomerListNotifier extends AutoDisposeAsyncNotifier<List<Customer>>
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
  TestWidgetsFlutterBinding.ensureInitialized();

  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const customer1 = Customer(
    id: 'cust_001',
    name: 'Khách VIP',
    phone: '0901111111',
    email: '',
    address: '',
    purchases: [],
  );

  final sampleOrders = [
    Order(
      id: 'HD000001',
      customerId: 'cust_001',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      items: [
        OrderItem(
          productId: 'P1',
          productName: 'Áo thun',
          price: 100000,
          quantity: 1,
          warrantyMonths: 0,
          purchaseDate: DateTime.now(),
        ),
      ],
      total: 100000,
      amountPaid: 100000,
      paymentMethod: 'cash',
      status: 'completed',
      createdBy: 'admin',
    ),
    Order(
      id: 'HD000002',
      customerId: 'cust_001',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      items: [
        OrderItem(
          productId: 'P2',
          productName: 'Quần jeans',
          price: 200000,
          quantity: 1,
          warrantyMonths: 0,
          purchaseDate: DateTime.now(),
        ),
      ],
      total: 200000,
      amountPaid: 50000,
      paymentMethod: 'transfer',
      status: 'completed',
      createdBy: 'staff_01',
    ),
  ];

  group('InvoicesFilterState Unit Tests', () {
    test('defaults have 0 activeFilterCount and hasActiveFilters is false', () {
      final state = InvoicesFilterState.defaults();
      expect(state.activeFilterCount, 0);
      expect(state.hasActiveFilters, isFalse);
    });

    test('activeFilterCount increments per active dimension', () {
      final state = InvoicesFilterState(
        timeRangeType: OverviewTimeRange.today,
        customDateRange: OverviewTimeRange.today.getRange(),
        status: 'returned',
        paymentMethod: 'transfer',
        debtStatus: 'debt',
        staff: 'staff_01',
      );
      expect(state.activeFilterCount, 5);
      expect(state.hasActiveFilters, isTrue);
    });

    test('toJson and fromJson preserves all 5 filter dimensions', () {
      final state = InvoicesFilterState(
        timeRangeType: OverviewTimeRange.yesterday,
        customDateRange: DateTimeRange(
          start: DateTime(2026, 9, 1),
          end: DateTime(2026, 9, 15),
        ),
        status: 'returned',
        paymentMethod: 'cash',
        debtStatus: 'paid',
        staff: 'nhanvien_1',
      );

      final json = state.toJson();
      final recovered = InvoicesFilterState.fromJson(json);

      expect(recovered.timeRangeType, OverviewTimeRange.yesterday);
      expect(recovered.status, 'returned');
      expect(recovered.paymentMethod, 'cash');
      expect(recovered.debtStatus, 'paid');
      expect(recovered.staff, 'nhanvien_1');
    });
  });

  group('InvoicesPage Filter Persistence Widget Tests', () {
    setUp(() {
      FilterStorageService.resetSharedPrefs();
    });

    tearDown(() {
      FilterStorageService.resetSharedPrefs();
    });

    testWidgets(
        'Hydrates active filters from SharedPreferences and shows badge',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'filter_prefs_invoices': jsonEncode({
          'version': 1,
          'timeRangeType': 'today',
          'status': 'completed',
          'paymentMethod': 'transfer',
          'debtStatus': 'debt',
          'staff': 'all',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(sampleOrders)),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([customer1])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Badge must display with active count = 3 (timeRangeType, paymentMethod, debtStatus)
      final badgeFinder =
          find.byKey(const Key('invoices_reset_filter_badge_button'));
      expect(badgeFinder, findsOneWidget);
      expect(find.text('Lọc (3)'), findsOneWidget);

      // Only HD000002 matches completed + transfer + debt
      expect(find.text('Mã đơn: HD000002'), findsOneWidget);
      expect(find.text('Mã đơn: HD000001'), findsNothing);
    });

    testWidgets('Tapping reset badge clears filters and removes from storage',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'filter_prefs_invoices': jsonEncode({
          'version': 1,
          'status': 'returned',
          'paymentMethod': 'all',
          'debtStatus': 'all',
          'staff': 'all',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(sampleOrders)),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([customer1])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final badgeFinder =
          find.byKey(const Key('invoices_reset_filter_badge_button'));
      expect(badgeFinder, findsOneWidget);

      // Tap reset badge
      await tester.tap(badgeFinder);
      await tester.pumpAndSettle();

      // Badge is gone
      expect(find.byKey(const Key('invoices_reset_filter_badge_button')),
          findsNothing);

      // Both completed orders are visible now
      expect(find.text('Mã đơn: HD000001'), findsOneWidget);
      expect(find.text('Mã đơn: HD000002'), findsOneWidget);

      // Verify SharedPreferences is cleared
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filter_prefs_invoices'), isFalse);
    });

    testWidgets('Tapping a status chip persists new filter to storage',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        _buildTestApp(
          child: const InvoicesPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            accountsListProvider
                .overrideWith((ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(sampleOrders)),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([customer1])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Đơn trả hàng" chip
      await tester.tap(find.widgetWithText(ChoiceChip, 'Đơn trả hàng'));
      await tester.pumpAndSettle();

      // Badge shows "Lọc (1)"
      expect(find.byKey(const Key('invoices_reset_filter_badge_button')),
          findsOneWidget);
      expect(find.text('Lọc (1)'), findsOneWidget);

      // SharedPreferences contains updated JSON
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_invoices');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['status'], 'returned');
    });
  });
}
