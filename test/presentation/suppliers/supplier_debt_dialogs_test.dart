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
import 'package:stores/domain/repositories/supplier_repository.dart';
import 'package:stores/presentation/suppliers/widgets/supplier_debt_adjustment_dialog.dart';
import 'package:stores/presentation/suppliers/widgets/supplier_debt_payment_dialog.dart';

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
      home: Scaffold(body: child),
    ),
  );
}

class _FakeSupplierRepository implements SupplierRepository {
  final Map<String, Supplier> suppliers = {};
  final List<SupplierDebtTransaction> recordedTransactions = [];

  @override
  Stream<List<Supplier>> watchAll({String? storeId}) =>
      Stream.value(suppliers.values.toList());

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async => suppliers[id];

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    suppliers[supplier.id] = supplier;
  }

  @override
  Future<void> delete(String id, {String? storeId}) async {
    suppliers.remove(id);
  }

  @override
  Future<void> recordDebtTransaction(
    SupplierDebtTransaction transaction, {
    String? storeId,
  }) async {
    recordedTransactions.add(transaction);
  }

  @override
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(
    String supplierId, {
    String? storeId,
  }) =>
      Stream.value(
        recordedTransactions.where((t) => t.supplierId == supplierId).toList(),
      );

  @override
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(
    String supplierId, {
    String? storeId,
  }) async =>
      recordedTransactions.where((t) => t.supplierId == supplierId).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final currencyFormat = NumberFormat('#,###', 'vi_VN');

  const testSupplier = Supplier(
    id: 'NCC000001',
    code: 'NCC000001',
    name: 'Công ty Cổ phần Digiworld',
    totalPurchase: 100000000.0,
    currentDebt: 30000000.0,
  );

  group('Supplier Debt Dialogs Widget Tests', () {
    late _FakeSupplierRepository fakeRepo;

    setUp(() {
      fakeRepo = _FakeSupplierRepository();
      fakeRepo.suppliers['NCC000001'] = testSupplier;
    });

    testWidgets('SupplierDebtPaymentDialog pre-fills debt, handles Trả hết and records payment',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const SupplierDebtPaymentDialog(supplier: testSupplier),
          overrides: [
            supplierRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lập phiếu chi trả nợ NCC'), findsOneWidget);
      expect(find.text('Công ty Cổ phần Digiworld'), findsOneWidget);
      expect(find.text('${currencyFormat.format(30000000.0)} đ'), findsOneWidget);

      // Verify Trả hết button is present
      expect(find.text('Trả hết'), findsOneWidget);

      // Tap Trả hết to set full debt amount
      await tester.tap(find.text('Trả hết'));
      await tester.pumpAndSettle();

      // Submit payment
      await tester.tap(find.text('Xác nhận trả nợ'));
      await tester.pumpAndSettle();

      expect(fakeRepo.recordedTransactions.length, 1);
      final recorded = fakeRepo.recordedTransactions.first;
      expect(recorded.supplierId, 'NCC000001');
      expect(recorded.type, SupplierDebtType.payment);
      expect(recorded.amount, -30000000.0);
      expect(recorded.remainingDebt, 0.0);

      // Supplier current debt is updated to 0
      expect(fakeRepo.suppliers['NCC000001']!.currentDebt, 0.0);
    });

    testWidgets('SupplierDebtAdjustmentDialog adjusts debt and calculates delta correctly',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const SupplierDebtAdjustmentDialog(supplier: testSupplier),
          overrides: [
            supplierRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Điều chỉnh công nợ NCC'), findsWidgets);
      expect(find.text('${currencyFormat.format(30000000.0)} đ'), findsOneWidget);

      // Enter new debt amount: 25,000,000
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dư nợ mới (VNĐ) *'),
        '25.000.000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lý do điều chỉnh'),
        'Chiết khấu cuối năm',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cập nhật nợ'));
      await tester.pumpAndSettle();

      expect(fakeRepo.recordedTransactions.length, 1);
      final recorded = fakeRepo.recordedTransactions.first;
      expect(recorded.supplierId, 'NCC000001');
      expect(recorded.type, SupplierDebtType.adjustment);
      expect(recorded.amount, -5000000.0); // 25,000,000 - 30,000,000
      expect(recorded.remainingDebt, 25000000.0);
      expect(recorded.note, 'Chiết khấu cuối năm');

      expect(fakeRepo.suppliers['NCC000001']!.currentDebt, 25000000.0);
    });
  });
}
