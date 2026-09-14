import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
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
  Future<void> refresh() async {
    state = AsyncData(initialData);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final currencyFormat = NumberFormat('#,###', 'vi_VN');

  const s1 = Supplier(
    id: 'NCC000001',
    code: 'NCC000001',
    name: 'Công ty Cổ phần Digiworld',
    phone: '02839291234',
    address: 'Quận 1, TP.HCM',
    totalPurchase: 100000000.0,
    currentDebt: 30000000.0,
  );

  const s2 = Supplier(
    id: 'NCC000002',
    code: 'NCC000002',
    name: 'Công ty TNHH Synnex FPT',
    phone: '02473006666',
    address: 'Cầu Giấy, Hà Nội',
    totalPurchase: 50000000.0,
    currentDebt: 0.0,
  );

  group('SuppliersPage Widget Tests', () {
    testWidgets('Renders KPI header cards and supplier cards correctly', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const SuppliersPage(),
          overrides: [
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier([s1, s2]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Check AppBar and Title
      expect(find.text('Nhà Cung Cấp'), findsWidgets);

      // Check KPIs
      expect(find.text('Tổng NCC'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Tổng mua'), findsOneWidget);
      expect(find.text('${currencyFormat.format(150000000.0)} đ'), findsOneWidget);
      expect(find.text('Tổng nợ NCC'), findsOneWidget);
      expect(find.text('${currencyFormat.format(30000000.0)} đ'), findsOneWidget);

      // Check list items
      expect(find.text('Công ty Cổ phần Digiworld'), findsOneWidget);
      expect(find.text('Công ty TNHH Synnex FPT'), findsOneWidget);
      expect(find.text('Nợ: ${currencyFormat.format(30000000.0)} đ'), findsOneWidget);
      expect(find.text('Hết nợ'), findsWidgets);

      // Check FAB
      expect(find.text('Thêm NCC'), findsOneWidget);
    });

    testWidgets('Searching and filtering with chips updates visible list', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const SuppliersPage(),
          overrides: [
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier([s1, s2]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Enter search query "Digiworld"
      await tester.enterText(find.byType(TextField), 'Digiworld');
      await tester.pumpAndSettle();

      expect(find.text('Công ty Cổ phần Digiworld'), findsOneWidget);
      expect(find.text('Công ty TNHH Synnex FPT'), findsNothing);

      // Clear search and tap "Hết nợ" chip
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // First instance of 'Hết nợ' is the chip in the filter bar
      await tester.tap(find.text('Hết nợ').first);
      await tester.pumpAndSettle();

      expect(find.text('Công ty Cổ phần Digiworld'), findsNothing);
      expect(find.text('Công ty TNHH Synnex FPT'), findsOneWidget);
    });

    testWidgets('Empty state displays placeholder when no suppliers found', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const SuppliersPage(),
          overrides: [
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier([]),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Không tìm thấy nhà cung cấp nào'), findsOneWidget);
      expect(find.text('Thêm Nhà Cung Cấp'), findsOneWidget);
    });
  });
}
