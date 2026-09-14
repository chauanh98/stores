import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';
import 'package:stores/presentation/suppliers/pages/add_edit_supplier_page.dart';

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

class _FakeSupplierRepository implements SupplierRepository {
  final List<Supplier> savedSuppliers = [];

  @override
  Stream<List<Supplier>> watchAll({String? storeId}) =>
      Stream.value(savedSuppliers);

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async =>
      savedSuppliers.where((s) => s.id == id).firstOrNull;

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    savedSuppliers.removeWhere((s) => s.id == supplier.id);
    savedSuppliers.add(supplier);
  }

  @override
  Future<void> delete(String id, {String? storeId}) async {
    savedSuppliers.removeWhere((s) => s.id == id);
  }

  @override
  Future<void> recordDebtTransaction(
    SupplierDebtTransaction transaction, {
    String? storeId,
  }) async {}

  @override
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(
    String supplierId, {
    String? storeId,
  }) =>
      Stream.value([]);

  @override
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(
    String supplierId, {
    String? storeId,
  }) async =>
      [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AddEditSupplierPage Widget Tests', () {
    late _FakeSupplierRepository fakeRepo;

    setUp(() {
      fakeRepo = _FakeSupplierRepository();
    });

    testWidgets('Create mode shows auto-generated code and validates required fields',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddEditSupplierPage(),
          overrides: [
            supplierRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thêm Nhà Cung Cấp Mới'), findsOneWidget);
      expect(find.text('TẠO MỚI NHÀ CUNG CẤP'), findsOneWidget);
      expect(find.text('NCC000001'), findsOneWidget);

      // Attempt to submit empty form
      await tester.tap(find.text('TẠO MỚI NHÀ CUNG CẤP'));
      await tester.pumpAndSettle();

      expect(find.text('Vui lòng nhập tên nhà cung cấp'), findsOneWidget);

      // Enter valid data
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên nhà cung cấp *'),
        'Công ty TNHH Thiết bị Số',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số điện thoại'),
        '0912345678',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('TẠO MỚI NHÀ CUNG CẤP'));
      await tester.pumpAndSettle();

      expect(
        fakeRepo.savedSuppliers.any((s) => s.name == 'Công ty TNHH Thiết bị Số'),
        isTrue,
      );
      expect(
        fakeRepo.savedSuppliers.firstWhere((s) => s.name == 'Công ty TNHH Thiết bị Số').phone,
        '0912345678',
      );
    });

    testWidgets('Edit mode populates existing supplier data and allows updating',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const existing = Supplier(
        id: 'NCC000001',
        code: 'NCC000001',
        name: 'Digiworld Corp',
        phone: '02839291234',
        email: 'contact@digiworld.com',
        address: '195 Cô Bắc',
        taxCode: '0302861742',
        totalPurchase: 145000000.0,
        currentDebt: 32500000.0,
      );

      await fakeRepo.upsert(existing);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddEditSupplierPage(supplier: existing),
          overrides: [
            supplierRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chỉnh Sửa Nhà Cung Cấp'), findsOneWidget);
      expect(find.text('CẬP NHẬT NHÀ CUNG CẤP'), findsOneWidget);
      expect(find.text('Digiworld Corp'), findsOneWidget);
      expect(find.text('02839291234'), findsOneWidget);
      expect(find.text('contact@digiworld.com'), findsOneWidget);
      expect(find.text('195 Cô Bắc'), findsOneWidget);
      expect(find.text('0302861742'), findsOneWidget);

      // Edit name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên nhà cung cấp *'),
        'Digiworld Corp Vietnam',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('CẬP NHẬT NHÀ CUNG CẤP'));
      await tester.pumpAndSettle();

      expect(
        fakeRepo.savedSuppliers.any((s) => s.name == 'Digiworld Corp Vietnam'),
        isTrue,
      );
    });
  });
}
