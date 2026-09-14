import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/inventories/pages/import_detail_page.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';

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
  const staffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor_01',
    displayName: 'Giám sát viên',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const sampleProduct = Product(
    id: 'prod_01',
    name: 'Sản phẩm Test A',
    code: 'SPA',
    price: 200000,
    costPrice: 150000,
    branchStocks: {'branch_1': 10, 'branch_2': 5},
    category: 'Mỹ phẩm',
  );

  final sampleTx = InventoryTransaction(
    id: 'tx_import_001',
    productId: 'prod_01',
    type: TransactionType.import,
    quantity: 5,
    date: DateTime(2026, 8, 16),
    note: 'Nhập hàng test',
    importPrice: 150000,
    createdBy: 'staff_01',
    createdByName: 'Nhân viên',
  );

  group('ImportInventoryPage Tests (R1)', () {
    testWidgets(
        'Staff sees locked store badge and masked cost price in ImportInventoryPage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            productListProvider.overrideWith(
                (ref) => Stream.value([sampleProduct])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                  'store_002': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Locked store branch badge
      expect(
          find.text('Chi nhánh nhập: Chi nhánh Thới Bình (Cố định)'),
          findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      // Quantity input should exist
      expect(find.byType(TextFormField), findsWidgets);

      // Cost price input should be HIDDEN for staff
      expect(find.textContaining('Giá nhập'), findsNothing);
      expect(find.textContaining('Tổng giá trị'), findsNothing);
    });

    testWidgets(
        'Supervisor sees full cost price input and total value in ImportInventoryPage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith(
                (ref) => Stream.value([sampleProduct])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                  'store_002': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Branch name (not locked as fixed for supervisor)
      expect(find.text('Chi nhánh nhập: Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.byIcon(Icons.storefront), findsOneWidget);

      // Cost price input and total value summary should be VISIBLE for supervisor
      expect(find.textContaining('Giá nhập'), findsOneWidget);
      expect(find.textContaining('Tổng giá trị'), findsOneWidget);
    });

    testWidgets(
        'Admin with canViewCostPrice == false has masked cost price in ImportInventoryPage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productListProvider.overrideWith(
                (ref) => Stream.value([sampleProduct])),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                  'store_002': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Cost price should be masked for admin as well (only supervisor can view cost price)
      expect(find.textContaining('Giá nhập'), findsNothing);
      expect(find.textContaining('Tổng giá trị'), findsNothing);
    });
  });

  group('ImportDetailPage Cost Price Masking Tests (R1)', () {
    testWidgets('Staff cannot view importPrice on ImportDetailPage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: ImportDetailPage(
            tx: sampleTx,
            product: sampleProduct,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chi tiết nhập hàng'), findsOneWidget);
      expect(find.text('Sản phẩm Test A'), findsOneWidget);
      // importPrice must NOT be displayed
      expect(find.textContaining('Giá nhập'), findsNothing);
      expect(find.text('150000'), findsNothing);
    });

    testWidgets('Supervisor can view importPrice on ImportDetailPage',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: ImportDetailPage(
            tx: sampleTx,
            product: sampleProduct,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chi tiết nhập hàng'), findsOneWidget);
      expect(find.text('Sản phẩm Test A'), findsOneWidget);
      // importPrice must be displayed for supervisor
      expect(find.textContaining('Giá nhập'), findsOneWidget);
      expect(find.text('150000'), findsOneWidget);
    });
  });
}
