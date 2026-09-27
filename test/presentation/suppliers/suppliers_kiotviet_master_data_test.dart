import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';
import 'package:stores/presentation/suppliers/pages/suppliers_page.dart';

class _MockSupplierRepository implements SupplierRepository {
  final List<Supplier> suppliers;

  _MockSupplierRepository(this.suppliers);

  @override
  Stream<List<Supplier>> watchAll({String? storeId}) {
    return Stream.value(suppliers);
  }

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async {
    try {
      return suppliers.firstWhere((s) => s.id == id || s.code == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {}

  @override
  Future<void> delete(String id, {String? storeId}) async {}

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction transaction,
      {String? storeId}) async {}

  @override
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(String supplierId,
      {String? storeId}) {
    return Stream.value([]);
  }

  @override
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(String supplierId,
      {String? storeId}) async {
    return [];
  }
}

class _TestAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _TestAuthNotifier()
      : super(
          const UserAccount(
            username: 'admin',
            displayName: 'Administrator',
            role: 'admin',
            storeId: 'store_001',
          ),
        );

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

void main() {
  testWidgets(
      'SuppliersPage correctly parses and displays 49 KiotViet suppliers with 23B+ VND debt',
      (tester) async {
    // 1. Read real KiotViet Excel file
    final excelFile =
        File('DATA_IMPORT/DanhSachNhaCungCap_KV21092026-213547-088.xlsx');
    expect(excelFile.existsSync(), isTrue,
        reason: 'Excel master file must exist in DATA_IMPORT');

    final realSuppliers =
        ExcelHelper.parseSuppliers(excelFile.readAsBytesSync());
    expect(realSuppliers.length, equals(49));

    final totalDebt =
        realSuppliers.fold<double>(0.0, (sum, s) => sum + s.currentDebt);
    final totalPurchase =
        realSuppliers.fold<double>(0.0, (sum, s) => sum + s.totalPurchase);

    expect(totalDebt, equals(23067331240.0));
    expect(totalPurchase, equals(23473665240.0));

    final mockRepo = _MockSupplierRepository(realSuppliers);
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supplierRepositoryProvider.overrideWithValue(mockRepo),
          authProvider.overrideWith((ref) => _TestAuthNotifier()),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
        ],
        child: const MaterialApp(
          home: SuppliersPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify 49 suppliers count in KPI
    expect(find.text('49'), findsOneWidget);

    // Verify KPI currency values
    final expectedDebtText = '${currencyFormat.format(23067331240)} đ';
    final expectedPurchaseText = '${currencyFormat.format(23473665240)} đ';

    expect(find.text(expectedDebtText), findsOneWidget);
    expect(find.text(expectedPurchaseText), findsOneWidget);

    // Verify presence of top debt supplier (Chú Vinh Hố Nai with 4.4B debt)
    expect(find.text('Chú Vinh Hố Nai'), findsOneWidget);

    // Verify dummy suppliers (Digiworld, Samsung) are NOT present
    expect(find.textContaining('Digiworld'), findsNothing);
    expect(find.textContaining('Synnex FPT'), findsNothing);
    expect(find.textContaining('Samsung'), findsNothing);
  });

  testWidgets('Switching branches (store_001 to store_002) preserves 49 suppliers',
      (tester) async {
    final excelFile =
        File('DATA_IMPORT/DanhSachNhaCungCap_KV21092026-213547-088.xlsx');
    final realSuppliers =
        ExcelHelper.parseSuppliers(excelFile.readAsBytesSync());
    final mockRepo = _MockSupplierRepository(realSuppliers);

    final container = ProviderContainer(
      overrides: [
        supplierRepositoryProvider.overrideWithValue(mockRepo),
        authProvider.overrideWith((ref) => _TestAuthNotifier()),
        currentStoreIdProvider.overrideWith((ref) => 'store_002'), // Thới Bình
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SuppliersPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // At store_002 (Thới Bình), still exactly 49 suppliers
    expect(find.text('49'), findsOneWidget);
    expect(find.text('Chú Vinh Hố Nai'), findsOneWidget);

    // Switch store to store_001
    container.read(selectedStoreIdProvider.notifier).state = 'store_001';
    await tester.pumpAndSettle();

    expect(find.text('49'), findsOneWidget);
    expect(find.text('Chú Vinh Hố Nai'), findsOneWidget);
    expect(find.textContaining('Digiworld'), findsNothing);
  });

  testWidgets('Debt status filter chips correctly filter hasDebt and noDebt',
      (tester) async {
    final excelFile =
        File('DATA_IMPORT/DanhSachNhaCungCap_KV21092026-213547-088.xlsx');
    final realSuppliers =
        ExcelHelper.parseSuppliers(excelFile.readAsBytesSync());
    final mockRepo = _MockSupplierRepository(realSuppliers);

    final withDebtCount = realSuppliers.where((s) => s.currentDebt > 0).length;
    final withoutDebtCount = realSuppliers.where((s) => s.currentDebt <= 0).length;
    expect(withDebtCount, greaterThan(0));
    expect(withoutDebtCount, greaterThan(0));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supplierRepositoryProvider.overrideWithValue(mockRepo),
          authProvider.overrideWith((ref) => _TestAuthNotifier()),
        ],
        child: const MaterialApp(
          home: SuppliersPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap "Còn nợ" chip
    await tester.tap(find.text('Còn nợ'));
    await tester.pumpAndSettle();

    // Chú Dũng Thốt Nốt has 0 debt, so should NOT be visible under "Còn nợ"
    expect(find.text('chú Dũng Thốt Nốt'), findsNothing);
    // Chú Vinh Hố Nai has 4.4B debt, so must be visible
    expect(find.text('Chú Vinh Hố Nai'), findsOneWidget);

    // Tap "Hết nợ" chip
    await tester.tap(find.text('Hết nợ'));
    await tester.pumpAndSettle();

    // Under "Hết nợ", Chú Vinh Hố Nai must NOT be visible
    expect(find.text('Chú Vinh Hố Nai'), findsNothing);
    // Chú Dũng Thốt Nốt has 0 debt, so must be visible
    expect(find.text('chú Dũng Thốt Nốt'), findsOneWidget);
  });
}
