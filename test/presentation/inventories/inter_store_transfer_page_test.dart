import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/inventories/pages/inter_store_transfer_page.dart';

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
  const sampleProduct = Product(
    id: 'prod_001',
    name: 'Sản phẩm Test Chuyển Kho',
    code: 'SPCK01',
    price: 300000,
    costPrice: 200000,
    branchStocks: {'branch_1': 15, 'branch_2': 5},
    category: 'Vật tư',
  );

  const staffUser = UserAccount(
    username: 'staff_user',
    displayName: 'Nhân viên',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_user',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  group('InterStoreTransferPage Tests (R2)', () {
    testWidgets(
        'Staff has source store locked to their assigned storeId',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const InterStoreTransferPage(product: sampleProduct),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                  'store_002': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Exporting store field should be locked to staff store
      expect(
          find.text('Chi nhánh Thới Bình (Cố định)'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      // Product stock info should be visible
      expect(find.text('Sản phẩm Test Chuyển Kho'), findsOneWidget);
    });

    testWidgets(
        'Admin/Supervisor has source store rendered without fixed lock tag',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const InterStoreTransferPage(product: sampleProduct),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                  'store_002': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình (Cố định)'), findsNothing);
      expect(find.byIcon(Icons.storefront), findsOneWidget);
    });
  });
}
