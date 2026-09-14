import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/suppliers/pages/supplier_detail_page.dart';

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

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  const staffUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: child,
    ),
  );
}

class _TestSupplierListNotifier extends AutoDisposeAsyncNotifier<List<Supplier>>
    implements SupplierListNotifier {
  final List<Supplier> initialData;
  _TestSupplierListNotifier(this.initialData);

  @override
  Future<List<Supplier>> build() async => initialData;

  @override
  Future<void> refresh() async {}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final currencyFormat = NumberFormat('#,###', 'vi_VN');

  const testSupplier = Supplier(
    id: 'NCC000001',
    code: 'NCC000001',
    name: 'Công ty Cổ phần Digiworld',
    phone: '02839291234',
    email: 'contact@digiworld.com.vn',
    address: '195 Cô Bắc, Quận 1, TP.HCM',
    taxCode: '0302861742',
    totalPurchase: 145000000.0,
    currentDebt: 32500000.0,
    note: 'Nhà phân phối chính hãng',
    status: 'active',
  );

  final testTxs = [
    SupplierDebtTransaction(
      id: 'TX_01',
      supplierId: 'NCC000001',
      date: DateTime(2026, 8, 15, 14, 0),
      type: SupplierDebtType.importBill,
      amount: 32500000.0,
      remainingDebt: 32500000.0,
      referenceCode: 'PN00123',
      note: 'Nhập lô hàng linh kiện đợt 1',
    ),
    SupplierDebtTransaction(
      id: 'TX_02',
      supplierId: 'NCC000001',
      date: DateTime(2026, 8, 18, 9, 30),
      type: SupplierDebtType.payment,
      amount: -10000000.0,
      remainingDebt: 22500000.0,
      referenceCode: 'PC00045',
      note: 'Thanh toán đợt 1',
    ),
  ];

  group('SupplierDetailPage Widget Tests', () {
    testWidgets('Renders supplier profile, KPIs, action buttons, and transaction history',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const SupplierDetailPage(supplier: testSupplier),
          overrides: [
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier([testSupplier]),
            ),
            supplierDebtTransactionsProvider(testSupplier.id).overrideWith(
              (ref) => Stream.value(testTxs),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Check Header
      expect(find.text('Công ty Cổ phần Digiworld'), findsWidgets);
      expect(find.text('NCC000001'), findsOneWidget);
      expect(find.text('MST: 0302861742'), findsOneWidget);
      expect(find.text('02839291234'), findsOneWidget);

      // Check KPI Cards
      expect(find.text('Tổng mua hàng'), findsOneWidget);
      expect(find.text('${currencyFormat.format(145000000.0)} đ'), findsOneWidget);
      expect(find.text('Nợ cần trả NCC'), findsOneWidget);
      expect(find.text('${currencyFormat.format(32500000.0)} đ'), findsOneWidget);

      // Check Action Buttons
      expect(find.text('Trả nợ NCC'), findsOneWidget);
      expect(find.text('Điều chỉnh nợ'), findsOneWidget);

      // Check Transaction List
      expect(find.text('Nhập hàng'), findsOneWidget);
      expect(find.text('+${currencyFormat.format(32500000.0)} đ'), findsOneWidget);
      expect(find.text('Trả tiền NCC'), findsOneWidget);
      expect(find.text('-${currencyFormat.format(10000000.0)} đ'), findsOneWidget);
      expect(find.text('Chứng từ: PN00123'), findsOneWidget);
      expect(find.text('Chứng từ: PC00045'), findsOneWidget);
    });

    testWidgets('Tab switching displays detailed supplier information', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const SupplierDetailPage(supplier: testSupplier),
          overrides: [
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier([testSupplier]),
            ),
            supplierDebtTransactionsProvider(testSupplier.id).overrideWith(
              (ref) => Stream.value(testTxs),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 'THÔNG TIN CHI TIẾT' tab
      await tester.tap(find.text('THÔNG TIN CHI TIẾT'));
      await tester.pumpAndSettle();

      expect(find.text('contact@digiworld.com.vn'), findsOneWidget);
      expect(find.text('195 Cô Bắc, Quận 1, TP.HCM'), findsOneWidget);
      expect(find.text('Nhà phân phối chính hãng'), findsOneWidget);
    });

    testWidgets('Tapping Trả nợ NCC opens debt payment dialog', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const SupplierDetailPage(supplier: testSupplier),
          overrides: [
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier([testSupplier]),
            ),
            supplierDebtTransactionsProvider(testSupplier.id).overrideWith(
              (ref) => Stream.value(testTxs),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trả nợ NCC'));
      await tester.pumpAndSettle();

      expect(find.text('Lập phiếu chi trả nợ NCC'), findsOneWidget);
      expect(find.text('Xác nhận trả nợ'), findsOneWidget);
    });

    testWidgets('Tapping Điều chỉnh nợ opens adjustment dialog', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const SupplierDetailPage(supplier: testSupplier),
          overrides: [
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier([testSupplier]),
            ),
            supplierDebtTransactionsProvider(testSupplier.id).overrideWith(
              (ref) => Stream.value(testTxs),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Điều chỉnh nợ'));
      await tester.pumpAndSettle();

      expect(find.text('Điều chỉnh công nợ NCC'), findsWidgets);
      expect(find.text('Cập nhật nợ'), findsOneWidget);
    });
  });
}
