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
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';

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

  final List<Customer> sampleCustomers = [
    const Customer(
      id: 'cust_001',
      name: 'Nguyễn Văn Nợ',
      phone: '0901111111',
      email: 'no@example.com',
      address: 'Hà Nội',
      purchases: [],
      currentDebt: 5000000,
    ),
    const Customer(
      id: 'cust_002',
      name: 'Trần Thị Hết Nợ',
      phone: '0902222222',
      email: 'hetno@example.com',
      address: 'Hà Nội',
      purchases: [],
      currentDebt: 0,
    ),
  ];

  List<Override> buildOverrides() => [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        customerListNotifierProvider
            .overrideWith(() => _FakeCustomerListNotifier(sampleCustomers)),
        for (final c in sampleCustomers) ...[
          customerOrdersProvider(c.id)
              .overrideWith((ref) => Stream.value(<Order>[])),
          customerDebtTransactionsProvider(c.id)
              .overrideWith((ref) => Stream.value(<CustomerDebtTransaction>[])),
        ],
      ];

  group('CustomersPage Filter State Retention Tests', () {
    setUp(() {
      FilterStorageService.resetSharedPrefs();
    });

    tearDown(() {
      FilterStorageService.resetSharedPrefs();
    });
    testWidgets('Hydrates inDebt filter from SharedPreferences on initial build',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'filter_prefs_customers': jsonEncode({
          'debtFilter': 'inDebt',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Only inDebt customer should be visible
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsNothing);

      // Reset button with count 1 is visible
      expect(find.byKey(const Key('reset_customer_filters_button')),
          findsOneWidget);
      expect(find.text('Đặt lại (1)'), findsOneWidget);
    });

    testWidgets('Tapping a tab persists new filter to storage', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Both customers visible initially
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsOneWidget);

      // Tap "Hết nợ" tab
      await tester.tap(find.byKey(const Key('debt_filter_tab_cleared')));
      await tester.pumpAndSettle();

      // Only cleared customer visible
      expect(find.text('Trần Thị Hết Nợ'), findsOneWidget);
      expect(find.text('Nguyễn Văn Nợ'), findsNothing);

      // Verify SharedPreferences has updated value
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_customers');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['debtFilter'], 'cleared');
    });

    testWidgets('1-tap Đặt lại resets filters to default and clears cache',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'filter_prefs_customers': jsonEncode({
          'debtFilter': 'inDebt',
        }),
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      final resetBtn = find.byKey(const Key('reset_customer_filters_button'));
      expect(resetBtn, findsOneWidget);

      // Tap reset
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      // Both customers visible now
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsOneWidget);
      expect(find.byKey(const Key('reset_customer_filters_button')), findsNothing);

      // SharedPreferences key removed
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filter_prefs_customers'), isFalse);
    });

    testWidgets('Active navigation override (initialDebtFilter != null) updates cache',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'filter_prefs_customers': jsonEncode({
          'debtFilter': 'cleared',
        }),
      });

      // Navigate with explicit initialDebtFilter: inDebt (like KPI click)
      await tester.pumpWidget(
        _buildTestApp(
          child: const CustomersPage(initialDebtFilter: CustomerDebtFilter.inDebt),
          overrides: buildOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      // inDebt override wins over stored 'cleared'
      expect(find.text('Nguyễn Văn Nợ'), findsOneWidget);
      expect(find.text('Trần Thị Hết Nợ'), findsNothing);

      // SharedPreferences updated to inDebt
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_customers');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['debtFilter'], 'inDebt');
    });
  });
}
