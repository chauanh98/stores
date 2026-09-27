import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/customers/usecases/import_customers_usecase.dart';
import 'package:stores/application/orders/usecases/import_invoices_usecase.dart';
import 'package:stores/application/products/usecases/import_products_usecase.dart';
import 'package:stores/application/suppliers/usecases/import_suppliers_usecase.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/purchase.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/warranty.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

// ============================================================================
// FAKE REPOSITORIES FOR ADVERSARIAL STRESS TESTING
// ============================================================================

class _FakeCustomerRepository implements CustomerRepository {
  final Map<String, Customer> storage = {};

  _FakeCustomerRepository([List<Customer> initial = const []]) {
    for (final c in initial) {
      storage[c.id] = c;
    }
  }

  @override
  Stream<List<Customer>> watchAll() => Stream.value(storage.values.toList());

  @override
  Future<Customer?> fetchById(String id) async => storage[id];

  @override
  Future<void> upsert(Customer customer) async {
    storage[customer.id] = customer;
  }

  @override
  Future<void> delete(String id) async {
    storage.remove(id);
  }
}

class _FakeSupplierRepository implements SupplierRepository {
  final Map<String, Supplier> storage = {};

  _FakeSupplierRepository([List<Supplier> initial = const []]) {
    for (final s in initial) {
      storage[s.id] = s;
    }
  }

  @override
  Stream<List<Supplier>> watchAll({String? storeId}) =>
      Stream.value(storage.values.toList());

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async => storage[id];

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    storage[supplier.id] = supplier;
  }

  @override
  Future<void> delete(String id, {String? storeId}) async {
    storage.remove(id);
  }

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction transaction,
      {String? storeId}) async {}

  @override
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(String supplierId,
          {String? storeId}) =>
      Stream.value([]);

  @override
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(String supplierId,
          {String? storeId}) async =>
      [];
}

class _FakeOrderRepository implements OrderRepository {
  final Map<String, Order> storage = {};

  _FakeOrderRepository([List<Order> initial = const []]) {
    for (final o in initial) {
      storage[o.id] = o;
    }
  }

  @override
  Future<void> create(Order order) async {
    storage[order.id] = order;
  }

  @override
  Future<void> update(Order order) async {
    storage[order.id] = order;
  }

  @override
  Future<void> delete(String orderId) async {
    storage.remove(orderId);
  }

  @override
  Future<Order?> fetchById(String orderId) async => storage[orderId];

  @override
  Stream<List<Order>> watchAll() => Stream.value(storage.values.toList());

  @override
  Stream<List<Order>> watchByCustomer(String customerId) => Stream.value(
      storage.values.where((o) => o.customerId == customerId).toList());

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value(storage.values.toList());
}

class _FakeProductRepository implements ProductRepository {
  final Map<String, Product> storage = {};

  _FakeProductRepository([List<Product> initial = const []]) {
    for (final p in initial) {
      storage[p.id] = p;
    }
  }

  @override
  Stream<List<Product>> watchAll() => Stream.value(storage.values.toList());

  @override
  Future<List<Product>> fetchAll() async => storage.values.toList();

  @override
  Future<Product?> fetchById(String id) async => storage[id];

  @override
  Future<void> upsert(Product product) async {
    storage[product.id] = product;
  }

  @override
  Future<void> delete(String id) async {
    storage.remove(id);
  }

  @override
  Future<void> updateStock(String id, int newStock) async {
    final p = storage[id];
    if (p != null) {
      storage[id] = p.copyWith(branchStocks: {'store_001': newStock});
    }
  }
}

class _FakeInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async {
    transactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(
          transactions.where((t) => t.productId == productId).toList());

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime start, DateTime end,
          {String? storeId}) =>
      Stream.value(transactions);
}

// ============================================================================
// ADVERSARIAL EXCEL BUILDER HELPERS
// ============================================================================

Uint8List _buildCustomSheet({
  required String sheetName,
  required List<String> headers,
  required List<List<dynamic>> rows,
}) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null) {
    excel.rename(defaultSheet, sheetName);
  }
  final sheet = excel[sheetName];

  for (int c = 0; c < headers.length; c++) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).value =
        TextCellValue(headers[c]);
  }

  for (int r = 0; r < rows.length; r++) {
    final row = rows[r];
    for (int c = 0; c < row.length; c++) {
      final val = row[c];
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
      if (val is double) {
        cell.value = DoubleCellValue(val);
      } else if (val is int) {
        cell.value = IntCellValue(val);
      } else if (val != null) {
        cell.value = TextCellValue(val.toString());
      }
    }
  }

  final bytes = excel.encode()!;
  return Uint8List.fromList(bytes);
}

// ============================================================================
// MAIN ADVERSARIAL CHALLENGE SUITE
// ============================================================================

void main() {
  group('=== CHALLENGER 14: ADVERSARIAL EXCEL & DEDUPLICATION STRESS SUITE ===', () {
    // ========================================================================
    // 1. CORRUPT, TRUNCATED & MALFORMED SPREADSHEETS
    // ========================================================================
    group('1. Corrupt, Truncated & Malformed Spreadsheets', () {
      test('1.1 Completely empty byte array ([]) behavior across parsers and use cases', () async {
        final emptyBytes = <int>[];

        // Suppliers parser gracefully catches and returns empty list
        final suppliers = ExcelHelper.parseSuppliers(emptyBytes);
        expect(suppliers, isEmpty);

        // Invoices parser gracefully catches and returns empty list
        final invoices = ExcelHelper.parseInvoices(emptyBytes);
        expect(invoices, isEmpty);

        // Customers parser throws UnsupportedError because empty bytes lack OpenXML structure
        expect(
          () => ExcelHelper.parseCustomers(emptyBytes),
          throwsA(isA<UnsupportedError>()),
          reason: 'ExcelHelper.parseCustomers lacks outer try-catch for empty byte arrays',
        );

        // Products parser throws UnsupportedError because empty bytes lack OpenXML structure
        expect(
          () => ExcelHelper.parseProducts(emptyBytes),
          throwsA(isA<UnsupportedError>()),
          reason: 'ExcelHelper.parseProducts lacks outer try-catch for empty byte arrays',
        );

        // All UseCases handle empty lists safely with zero added/updated/skipped/errors
        final customerRepo = _FakeCustomerRepository();
        final custResult = await ImportCustomersUseCase(
          customerRepository: customerRepo,
        ).execute(customers: []);
        expect(custResult.total, 0);
        expect(custResult.added, 0);
        expect(custResult.updated, 0);
        expect(custResult.skipped, 0);
        expect(custResult.errors, 0);

        final supplierRepo = _FakeSupplierRepository();
        final suppResult = await ImportSuppliersUseCase(
          supplierRepository: supplierRepo,
        ).execute(suppliers: []);
        expect(suppResult.total, 0);
        expect(suppResult.added, 0);
        expect(suppResult.isSuccess, isTrue);

        final orderRepo = _FakeOrderRepository();
        final prodRepo = _FakeProductRepository();
        final invRepo = _FakeInventoryRepository();
        final invResult = await ImportInvoicesUseCase(
          orderRepository: orderRepo,
          productRepository: prodRepo,
          inventoryRepository: invRepo,
          customerRepository: customerRepo,
        ).execute(orders: [], targetStoreId: 'store_001');
        expect(invResult.total, 0);
        expect(invResult.added, 0);

        final prodResult = await ImportProductsUseCase(
          productRepository: prodRepo,
          inventoryRepository: invRepo,
        ).execute(products: [], targetStoreId: 'store_001');
        expect(prodResult.total, 0);
        expect(prodResult.added, 0);
      });

      test('1.2 Truncated files, non-Excel bytes, and raw binary noise', () {
        final plainTextBytes = utf8.encode('This is not an Excel workbook at all!');
        final truncatedZipHeader = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);
        final randomNoise = Uint8List.fromList(List.generate(128, (i) => (i * 47) % 256));

        for (final noise in [plainTextBytes, truncatedZipHeader, randomNoise]) {
          // parseSuppliers and parseInvoices must never crash on noise
          expect(ExcelHelper.parseSuppliers(noise), isEmpty);
          expect(ExcelHelper.parseInvoices(noise), isEmpty);

          // parseCustomers and parseProducts throw on invalid non-Excel noise
          expect(() => ExcelHelper.parseCustomers(noise), throwsA(anything));
          expect(() => ExcelHelper.parseProducts(noise), throwsA(anything));
        }
      });

      test('1.3 Excel sheets with missing required headers', () {
        // Sheet with completely unrelated headers
        final unrelatedBytes = _buildCustomSheet(
          sheetName: 'Sheet1',
          headers: ['Số thứ tự', 'Ngày ghi sổ', 'Ghi chú nội bộ', 'Màu sắc'],
          rows: [
            [1, '2026-09-01', 'Dòng thử nghiệm', 'Đỏ'],
            [2, '2026-09-02', 'Dòng thứ nghiệm 2', 'Xanh'],
          ],
        );

        // None of the parsers should extract records when identification columns are absent
        expect(ExcelHelper.parseProducts(unrelatedBytes), isEmpty);
        expect(ExcelHelper.parseCustomers(unrelatedBytes), isEmpty);
        expect(ExcelHelper.parseSuppliers(unrelatedBytes), isEmpty);
        expect(ExcelHelper.parseInvoices(unrelatedBytes), isEmpty);
      });

      test('1.4 Excel sheets with misplaced, reversed, and shuffled columns', () {
        // Products sheet where column order is inverted and mixed:
        // Index 0: Tồn kho, 1: Giá vốn, 2: Tên hàng, 3: Mã hàng, 4: Giá bán
        final shuffledProductsBytes = _buildCustomSheet(
          sheetName: 'Danh sách sản phẩm',
          headers: ['Tồn kho', 'Giá vốn', 'Tên hàng', 'Mã hàng', 'Giá bán'],
          rows: [
            [25, 4000000.0, 'Giường ngủ sồi nga', 'SP_SHUFFLE_01', 7500000.0],
            [10, 1200000.0, 'Tủ đầu giường sồi', 'SP_SHUFFLE_02', 2100000.0],
          ],
        );

        final parsedProducts = ExcelHelper.parseProducts(shuffledProductsBytes);
        expect(parsedProducts.length, 2);
        expect(parsedProducts[0].code, 'SP_SHUFFLE_01');
        expect(parsedProducts[0].name, 'Giường ngủ sồi nga');
        expect(parsedProducts[0].price, 7500000.0);
        expect(parsedProducts[0].costPrice, 4000000.0);
        expect(parsedProducts[0].branchStocks['store_001'], 25);

        // Customers sheet with shuffled headers:
        // Index 0: Nợ cần thu hiện tại, 1: Điện thoại, 2: Tên khách hàng, 3: Mã khách hàng
        final shuffledCustomersBytes = _buildCustomSheet(
          sheetName: 'Danh sách khách hàng',
          headers: ['Nợ cần thu hiện tại', 'Điện thoại', 'Tên khách hàng', 'Mã khách hàng'],
          rows: [
            [3500000.0, '0918776655', 'Anh Hoàng Thới Bình', 'KH_SHUFFLE_01'],
          ],
        );

        final parsedCustomers = ExcelHelper.parseCustomers(shuffledCustomersBytes);
        expect(parsedCustomers.length, 1);
        expect(parsedCustomers[0].id, 'KH_SHUFFLE_01');
        expect(parsedCustomers[0].name, 'Anh Hoàng Thới Bình');
        expect(parsedCustomers[0].phone, '0918776655');
        expect(parsedCustomers[0].currentDebt, 3500000.0);

        // Suppliers sheet with shuffled headers:
        // Index 0: Nợ cần trả hiện tại, 1: SĐT, 2: Tên nhà cung cấp, 3: Mã nhà cung cấp
        final shuffledSuppliersBytes = _buildCustomSheet(
          sheetName: 'Danh sách nhà cung cấp',
          headers: ['Nợ cần trả hiện tại', 'SĐT', 'Tên nhà cung cấp', 'Mã nhà cung cấp'],
          rows: [
            [88000000.0, '0988112233', 'Xưởng Sơn PU Mekong', 'NCC_SHUFFLE_01'],
          ],
        );

        final parsedSuppliers = ExcelHelper.parseSuppliers(shuffledSuppliersBytes);
        expect(parsedSuppliers.length, 1);
        expect(parsedSuppliers[0].code, 'NCC_SHUFFLE_01');
        expect(parsedSuppliers[0].name, 'Xưởng Sơn PU Mekong');
        expect(parsedSuppliers[0].phone, '0988112233');
        expect(parsedSuppliers[0].currentDebt, 88000000.0);

        // Invoices sheet with shuffled headers:
        final shuffledInvoicesBytes = _buildCustomSheet(
          sheetName: 'Danh sách hóa đơn',
          headers: ['Trạng thái', 'Khách đã trả', 'Khách cần trả', 'Mã hóa đơn', 'Thời gian', 'Mã KH'],
          rows: [
            ['Hoàn thành', 500000.0, 1500000.0, 'HD_SHUFFLE_01', '2026-09-15 14:30:00', 'KH_SHUFFLE_01'],
          ],
        );

        final parsedInvoices = ExcelHelper.parseInvoices(shuffledInvoicesBytes);
        expect(parsedInvoices.length, 1);
        expect(parsedInvoices[0].id, 'HD_SHUFFLE_01');
        expect(parsedInvoices[0].customerId, 'KH_SHUFFLE_01');
        expect(parsedInvoices[0].total, 1500000.0);
        expect(parsedInvoices[0].amountPaid, 500000.0);
        expect(parsedInvoices[0].debtAmount, 1000000.0);
      });

      test('1.5 Excel sheets with extra unknown columns alongside standard headers', () {
        final extraColsBytes = _buildCustomSheet(
          sheetName: 'Sheet1',
          headers: [
            'Cột hệ thống A',
            'Mã hàng',
            'Cột debug 1',
            'Tên hàng',
            'Cột UUID',
            'Giá bán',
            'Giá vốn',
            'Tồn kho',
            'Custom Ext Info',
          ],
          rows: [
            ['SYS_001', 'SP_EXTRA_01', 'DEBUG_OK', 'Bàn trà mặt kính', 'UUID_123', 2500000.0, 1500000.0, 8, 'EXTRA_DATA'],
          ],
        );

        final products = ExcelHelper.parseProducts(extraColsBytes);
        expect(products.length, 1);
        expect(products[0].code, 'SP_EXTRA_01');
        expect(products[0].name, 'Bàn trà mặt kính');
        expect(products[0].price, 2500000.0);
      });

      test('1.6 Spreadsheet with completely empty/whitespace rows', () {
        final blankRowsBytes = _buildCustomSheet(
          sheetName: 'Sheet1',
          headers: ['Mã hàng', 'Tên hàng', 'Giá bán'],
          rows: [
            ['', '', ''],
            ['   ', '   ', '   '],
            ['SP_REAL_01', 'Ghế đôn gỗ tràm', 350000.0],
            ['', '', ''],
          ],
        );

        final products = ExcelHelper.parseProducts(blankRowsBytes);
        expect(products.length, 1);
        expect(products[0].code, 'SP_REAL_01');
        expect(products[0].name, 'Ghế đôn gỗ tràm');
      });
    });

    // ========================================================================
    // 2. CUSTOMER DEDUPLICATION INVARIANTS & CONFLICT RESOLUTION
    // ========================================================================
    group('2. Customer Deduplication Invariants', () {
      test('2.1 Duplicate customer with same phone number formatted differently matches and PRESERVES debt and purchases', () async {
        final initialPurchase = Purchase(
          productId: 'prod_sofa_wood',
          quantity: 1,
          purchaseDate: DateTime(2026, 8, 1),
          warranty: Warranty(months: 24, expireDate: DateTime(2028, 8, 1)),
        );

        final existingCustomer = Customer(
          id: 'cust_canonical_001',
          name: 'Nguyễn Văn Cũ',
          phone: '0901234567',
          email: 'vancu@cantho.vn',
          address: '123 Đường 30/4, Ninh Kiều, Cần Thơ',
          purchases: [initialPurchase],
          currentDebt: 7500000.0,
          totalSales: 15000000.0,
          netSales: 15000000.0,
          createdAt: '2026-01-01T00:00:00Z',
          createdBy: 'admin_initial',
        );

        final repo = _FakeCustomerRepository([existingCustomer]);
        final useCase = ImportCustomersUseCase(customerRepository: repo);

        // Adversarial imported customer:
        // Different ID ('cust_adversarial_diff_id')
        // Phone formatted with leading +84, spaces, and dashes ('+84 901-234-567')
        // Debt set to 0.0, sales set to 0.0 (attacker attempting debt wipe)
        const adversarialCustomer = Customer(
          id: 'cust_adversarial_diff_id',
          name: 'Nguyễn Văn A (Tên Đã Đổi)',
          phone: '+84 901-234-567',
          email: 'nguyenvana.new@gmail.com',
          address: '456 Đường Nguyễn Văn Cừ, Cần Thơ',
          purchases: [],
          currentDebt: 0.0,
          totalSales: 0.0,
          netSales: 0.0,
        );

        final result = await useCase.execute(customers: [adversarialCustomer]);

        expect(result.total, 1);
        expect(result.added, 0, reason: 'Must match existing customer via normalized phone');
        expect(result.updated, 1, reason: 'Duplicate customer must be updated');
        expect(result.errors, 0);

        // Repository should still have exactly 1 customer
        expect(repo.storage.length, 1);

        final stored = repo.storage['cust_canonical_001'];
        expect(stored, isNotNull);
        expect(stored!.id, 'cust_canonical_001', reason: 'Canonical ID must be preserved');
        expect(stored.currentDebt, 7500000.0, reason: 'Existing debt must NEVER be overwritten by 0.0');
        expect(stored.totalSales, 15000000.0, reason: 'Total sales must be preserved');
        expect(stored.netSales, 15000000.0, reason: 'Net sales must be preserved');
        expect(stored.purchases.length, 1, reason: 'Purchase history must be preserved');
        expect(stored.purchases.first.productId, 'prod_sofa_wood');

        // Contact info is updated
        expect(stored.name, 'Nguyễn Văn A (Tên Đã Đổi)');
        expect(stored.email, 'nguyenvana.new@gmail.com');
        expect(stored.address, '456 Đường Nguyễn Văn Cừ, Cần Thơ');
      });

      test('2.2 Phone normalization variations: spaces, leading 84, +84, dashes', () {
        expect(ImportCustomersUseCase.normalizePhone('0901234567'), '0901234567');
        expect(ImportCustomersUseCase.normalizePhone('+84901234567'), '0901234567');
        expect(ImportCustomersUseCase.normalizePhone('+84 901 234 567'), '0901234567');
        expect(ImportCustomersUseCase.normalizePhone('84901234567'), '0901234567');
        expect(ImportCustomersUseCase.normalizePhone('0901-234-567'), '0901234567');
        expect(ImportCustomersUseCase.normalizePhone('+84-901-234-567'), '0901234567');
        expect(ImportCustomersUseCase.normalizePhone('  0901 234 567  '), '0901234567');
        expect(ImportCustomersUseCase.normalizePhone('901234567'), '0901234567');
        // Boundary case: +84 followed by redundant 0 results in 00 prefix in regex
        expect(ImportCustomersUseCase.normalizePhone('+840901234567'), '00901234567');
      });

      test('2.3 Duplicate customer with missing or empty phone number must NOT falsely match other empty phone records', () async {
        const custEmptyPhone1 = Customer(
          id: 'cust_no_phone_01',
          name: 'Khách Không SĐT 1',
          phone: '',
          email: '',
          address: '',
          purchases: [],
          currentDebt: 2000000.0,
        );

        const custEmptyPhone2 = Customer(
          id: 'cust_no_phone_02',
          name: 'Khách Không SĐT 2',
          phone: '   ',
          email: '',
          address: '',
          purchases: [],
          currentDebt: 4500000.0,
        );

        final repo = _FakeCustomerRepository([custEmptyPhone1, custEmptyPhone2]);
        final useCase = ImportCustomersUseCase(customerRepository: repo);

        // Import two new customers with empty phone
        const newCustEmpty3 = Customer(
          id: 'cust_no_phone_03',
          name: 'Khách Không SĐT 3',
          phone: '',
          email: '',
          address: '',
          purchases: [],
          currentDebt: 0.0,
        );

        const newCustEmpty4 = Customer(
          id: 'cust_no_phone_04',
          name: 'Khách Không SĐT 4',
          phone: '',
          email: '',
          address: '',
          purchases: [],
          currentDebt: 0.0,
        );

        final result = await useCase.execute(customers: [newCustEmpty3, newCustEmpty4]);

        expect(result.total, 2);
        expect(result.added, 2, reason: 'Empty phone records must not collide with each other');
        expect(result.updated, 0);
        expect(result.errors, 0);

        // All 4 distinct customers must exist with their respective debts preserved
        expect(repo.storage.length, 4);
        expect(repo.storage['cust_no_phone_01']!.currentDebt, 2000000.0);
        expect(repo.storage['cust_no_phone_02']!.currentDebt, 4500000.0);
        expect(repo.storage['cust_no_phone_03']!.currentDebt, 0.0);
        expect(repo.storage['cust_no_phone_04']!.currentDebt, 0.0);
      });

      test('2.4 Intra-batch duplicate customers deduplicate cleanly in memory', () async {
        final repo = _FakeCustomerRepository();
        final useCase = ImportCustomersUseCase(customerRepository: repo);

        final batch = <Customer>[
          const Customer(
            id: 'cust_batch_01',
            name: 'Lê Văn Tám',
            phone: '0919223344',
            email: 'tam@example.com',
            address: 'Ấp 1',
            purchases: [],
            currentDebt: 500000.0,
          ),
          const Customer(
            id: 'cust_batch_02_diff_id',
            name: 'Lê Văn Tám (Cập nhật địa chỉ)',
            phone: '+84 919 223 344',
            email: 'tam@example.com',
            address: 'Ấp 3, Xã Đông Thắng',
            purchases: [],
            currentDebt: 0.0,
          ),
        ];

        final result = await useCase.execute(customers: batch);

        expect(result.total, 2);
        expect(result.added, 1);
        expect(result.updated, 1);
        expect(repo.storage.length, 1);

        final saved = repo.storage['cust_batch_01']!;
        expect(saved.name, 'Lê Văn Tám (Cập nhật địa chỉ)');
        expect(saved.address, 'Ấp 3, Xã Đông Thắng');
        expect(saved.currentDebt, 500000.0);
      });
    });

    // ========================================================================
    // 3. SUPPLIER DEDUPLICATION & DEBT RETENTION
    // ========================================================================
    group('3. Supplier Deduplication & Debt Retention', () {
      test('3.1 Duplicate supplier with different name must preserve currentDebt and totalPurchase', () async {
        const existingSupplier = Supplier(
          id: 'NCC_GO_THUAN_PHAT',
          code: 'NCC_GO_THUAN_PHAT',
          name: 'Công ty Gỗ Thuận Phát Cũ',
          phone: '0939887766',
          email: 'thuanphat@wood.vn',
          address: 'Cụm CN An Nghiệp, Sóc Trăng',
          currentDebt: 150000000.0,
          totalPurchase: 650000000.0,
          createdAt: '2026-03-01T00:00:00Z',
          createdBy: 'admin_sys',
        );

        final repo = _FakeSupplierRepository([existingSupplier]);
        final useCase = ImportSuppliersUseCase(supplierRepository: repo);

        // Adversarial duplicate: same code, different temporary ID, modified name, debt wiped to 0.0
        const adversarialSupplier = Supplier(
          id: 'ncc_temp_generated_999',
          code: 'NCC_GO_THUAN_PHAT',
          name: 'Tập Đoàn Chế Biến Gỗ Thuận Phát Quốc Tế (Tên Mới)',
          phone: '0939887766',
          email: 'contact@thuanphatgroup.com',
          address: 'Lô B1, KCN Trà Nóc, Cần Thơ',
          currentDebt: 0.0, // Adversarial attempt to zero debt
          totalPurchase: 0.0,
        );

        final result = await useCase.execute(suppliers: [adversarialSupplier]);

        expect(result.total, 1);
        expect(result.added, 0);
        expect(result.updated, 1);
        expect(result.errors, 0);

        expect(repo.storage.length, 1);
        final stored = repo.storage['NCC_GO_THUAN_PHAT'];
        expect(stored, isNotNull);
        expect(stored!.name, 'Tập Đoàn Chế Biến Gỗ Thuận Phát Quốc Tế (Tên Mới)');
        expect(stored.currentDebt, 150000000.0, reason: 'Supplier currentDebt must be strictly preserved');
        expect(stored.totalPurchase, 650000000.0, reason: 'Supplier totalPurchase must be strictly preserved');
        expect(stored.email, 'contact@thuanphatgroup.com');
        expect(stored.address, 'Lô B1, KCN Trà Nóc, Cần Thơ');
      });

      test('3.2 Duplicate supplier matching by normalized phone with different ID/Code preserves currentDebt', () async {
        const existing = Supplier(
          id: 'NCC_DA_HOACUONG',
          code: 'NCC_DA_HOACUONG',
          name: 'Kho Đá Hoa Cương Miền Nam',
          phone: '0912889900',
          currentDebt: 42000000.0,
          totalPurchase: 180000000.0,
        );

        final repo = _FakeSupplierRepository([existing]);
        final useCase = ImportSuppliersUseCase(supplierRepository: repo);

        const imported = Supplier(
          id: 'ncc_import_888',
          code: 'NCC_NEW_CODE',
          name: 'Đá Hoa Cương Miền Nam (Chi nhánh 2)',
          phone: '+84 912-889-900',
          currentDebt: 0.0,
          totalPurchase: 0.0,
        );

        final result = await useCase.execute(suppliers: [imported]);
        expect(result.updated, 1);
        expect(result.added, 0);

        final stored = repo.storage['NCC_DA_HOACUONG']!;
        expect(stored.currentDebt, 42000000.0);
        expect(stored.totalPurchase, 180000000.0);
      });
    });

    // ========================================================================
    // 4. INVOICE DEDUPLICATION, IDEMPOTENCY & STOCK/DEBT PROTECTION
    // ========================================================================
    group('4. Invoice Deduplication & Idempotency Protection', () {
      test('4.1 Re-importing existing invoice updates invoice fields per R2 without double-deducting inventory or double-adding customer debt', () async {
        final now = DateTime(2026, 9, 15, 10, 0, 0);

        // Seed customer
        const customer = Customer(
          id: 'cust_invoice_target',
          name: 'Đoàn Văn Hậu',
          phone: '0988776655',
          email: 'hau@example.com',
          address: 'Cần Thơ',
          purchases: [],
          currentDebt: 3000000.0,
          totalSales: 8000000.0,
          netSales: 8000000.0,
        );

        // Seed product in target store
        const product = Product(
          id: 'SP_SALON_GO',
          code: 'SP_SALON_GO',
          name: 'Bộ salon gỗ gõ đỏ',
          price: 8000000.0,
          costPrice: 5000000.0,
          category: 'Bàn ghế',
          branchStocks: {'store_001': 10},
        );

        // Existing completed invoice in order repository
        final existingOrder = Order(
          id: 'HD_CANTHO_EXISTING_001',
          customerId: 'cust_invoice_target',
          createdAt: now,
          total: 8000000.0,
          amountPaid: 5000000.0,
          debtAmount: 3000000.0,
          paymentMethod: 'cash',
          status: 'completed',
          storeId: 'store_001',
          items: [
            OrderItem(
              productId: 'SP_SALON_GO',
              productName: 'Bộ salon gỗ gõ đỏ',
              quantity: 1,
              price: 8000000.0,
              warrantyMonths: 12,
              purchaseDate: now,
            ),
          ],
        );

        final orderRepo = _FakeOrderRepository([existingOrder]);
        final productRepo = _FakeProductRepository([product]);
        final inventoryRepo = _FakeInventoryRepository();
        final customerRepo = _FakeCustomerRepository([customer]);

        final useCase = ImportInvoicesUseCase(
          orderRepository: orderRepo,
          productRepository: productRepo,
          inventoryRepository: inventoryRepo,
          customerRepository: customerRepo,
        );

        // Adversarial duplicate invoice:
        // SAME ID 'HD_CANTHO_EXISTING_001'
        // Total inflated to 80,000,000 (10x)
        // Debt inflated to 80,000,000
        // Item quantity inflated to 5 units
        final adversarialDuplicateOrder = Order(
          id: 'HD_CANTHO_EXISTING_001',
          customerId: 'cust_invoice_target',
          createdAt: now.add(const Duration(hours: 2)),
          total: 80000000.0,
          amountPaid: 0.0,
          debtAmount: 80000000.0,
          paymentMethod: 'cash',
          status: 'completed',
          storeId: 'store_001',
          items: [
            OrderItem(
              productId: 'SP_SALON_GO',
              productName: 'Bộ salon gỗ gõ đỏ (Hack)',
              quantity: 5,
              price: 16000000.0,
              warrantyMonths: 12,
              purchaseDate: now,
            ),
          ],
        );

        final result = await useCase.execute(
          orders: [adversarialDuplicateOrder],
          targetStoreId: 'store_001',
        );

        // INVARIANT 1: Upsert count updated per R2
        expect(result.total, 1);
        expect(result.updated, 1, reason: 'Duplicate invoice must be updated per R2');
        expect(result.added, 0);
        expect(result.skipped, 0);
        expect(result.errors, 0);

        // INVARIANT 2: Existing order updated with latest values from import
        final storedOrder = orderRepo.storage['HD_CANTHO_EXISTING_001']!;
        expect(storedOrder.total, 80000000.0, reason: 'Order total is updated from latest Excel import');
        expect(storedOrder.amountPaid, 0.0);
        expect(storedOrder.debtAmount, 80000000.0);
        expect(storedOrder.items.length, 1);
        expect(storedOrder.items.first.quantity, 5);

        // INVARIANT 3: Product stock NOT double-deducted
        final storedProduct = productRepo.storage['SP_SALON_GO']!;
        expect(storedProduct.branchStocks['store_001'], 10,
            reason: 'Stock must remain 10, not deducted by adversarial 5 units');

        // INVARIANT 4: Customer debt NOT double-added
        final storedCustomer = customerRepo.storage['cust_invoice_target']!;
        expect(storedCustomer.currentDebt, 3000000.0,
            reason: 'Customer debt must remain 3,000,000, not increased to 83,000,000');
        expect(storedCustomer.totalSales, 8000000.0);

        // INVARIANT 5: Zero new inventory transactions recorded
        expect(inventoryRepo.transactions, isEmpty);
      });

      test('4.2 Combo product components are protected from double-deduction on duplicate skip', () async {
        final now = DateTime(2026, 9, 15);

        const childComponent = Product(
          id: 'SP_GHE_DON',
          code: 'SP_GHE_DON',
          name: 'Ghế đơn tràm',
          price: 500000.0,
          costPrice: 300000.0,
          category: 'Ghế',
          branchStocks: {'store_001': 20},
        );

        const comboProduct = Product(
          id: 'COMBO_BAN_GHE',
          code: 'COMBO_BAN_GHE',
          name: 'Bộ bàn ăn 4 ghế',
          price: 3000000.0,
          costPrice: 1800000.0,
          category: 'Bàn ăn',
          branchStocks: {'store_001': 5},
          isCombo: true,
          comboComponents: [
            ComboComponent(
              productId: 'SP_GHE_DON',
              productCode: 'SP_GHE_DON',
              productName: 'Ghế đơn tràm',
              quantity: 4,
            ),
          ],
        );

        final existingOrder = Order(
          id: 'HD_COMBO_001',
          customerId: 'khach_le',
          createdAt: now,
          total: 3000000.0,
          amountPaid: 3000000.0,
          debtAmount: 0.0,
          paymentMethod: 'cash',
          status: 'completed',
          storeId: 'store_001',
          items: [
            OrderItem(
              productId: 'COMBO_BAN_GHE',
              productName: 'Bộ bàn ăn 4 ghế',
              quantity: 1,
              price: 3000000.0,
              warrantyMonths: 6,
              purchaseDate: now,
            ),
          ],
        );

        final orderRepo = _FakeOrderRepository([existingOrder]);
        final productRepo = _FakeProductRepository([childComponent, comboProduct]);
        final inventoryRepo = _FakeInventoryRepository();
        final customerRepo = _FakeCustomerRepository();

        final useCase = ImportInvoicesUseCase(
          orderRepository: orderRepo,
          productRepository: productRepo,
          inventoryRepository: inventoryRepo,
          customerRepository: customerRepo,
        );

        // Duplicate combo invoice
        final duplicateOrder = existingOrder.copyWith(
          total: 6000000.0,
          items: [
            OrderItem(
              productId: 'COMBO_BAN_GHE',
              productName: 'Bộ bàn ăn 4 ghế',
              quantity: 2,
              price: 3000000.0,
              warrantyMonths: 6,
              purchaseDate: now,
            ),
          ],
        );

        final result = await useCase.execute(orders: [duplicateOrder], targetStoreId: 'store_001');
        expect(result.updated, 1);
        expect(result.skipped, 0);
        expect(result.added, 0);

        // Component stock must remain intact at 20
        final storedChild = productRepo.storage['SP_GHE_DON']!;
        expect(storedChild.branchStocks['store_001'], 20);
        expect(inventoryRepo.transactions, isEmpty);
      });

      test('4.3 Intra-batch duplicate invoice strictly processes first and updates second', () async {
        final now = DateTime(2026, 9, 15);

        const product = Product(
          id: 'SP_DEN_CHUM',
          code: 'SP_DEN_CHUM',
          name: 'Đèn chùm pha lê',
          price: 5000000.0,
          costPrice: 3000000.0,
          category: 'Đèn',
          branchStocks: {'store_001': 10},
        );

        final productRepo = _FakeProductRepository([product]);
        final orderRepo = _FakeOrderRepository();
        final inventoryRepo = _FakeInventoryRepository();
        final customerRepo = _FakeCustomerRepository();

        final useCase = ImportInvoicesUseCase(
          orderRepository: orderRepo,
          productRepository: productRepo,
          inventoryRepository: inventoryRepo,
          customerRepository: customerRepo,
        );

        final order1 = Order(
          id: 'HD_INTRA_BATCH_001',
          customerId: 'khach_le',
          createdAt: now,
          total: 5000000.0,
          amountPaid: 5000000.0,
          debtAmount: 0.0,
          paymentMethod: 'cash',
          status: 'completed',
          storeId: 'store_001',
          items: [
            OrderItem(
              productId: 'SP_DEN_CHUM',
              productName: 'Đèn chùm pha lê',
              quantity: 2,
              price: 2500000.0,
              warrantyMonths: 12,
              purchaseDate: now,
            ),
          ],
        );

        // Duplicate with same ID in same batch
        final order2 = order1.copyWith(total: 10000000.0);

        final result = await useCase.execute(
          orders: [order1, order2],
          targetStoreId: 'store_001',
        );

        expect(result.total, 2);
        expect(result.added, 1);
        expect(result.updated, 1);
        expect(result.skipped, 0);

        // Stock must be deducted exactly once: 10 - 2 = 8
        final stored = productRepo.storage['SP_DEN_CHUM']!;
        expect(stored.branchStocks['store_001'], 8);
        expect(inventoryRepo.transactions.length, 1);
      });
    });

    // ========================================================================
    // 5. PRODUCT DEDUPLICATION & STOCK / IMAGE PRESERVATION
    // ========================================================================
    group('5. Product Deduplication & Stock / Image Preservation', () {
      test('5.1 Duplicate product with different stock must PRESERVE branchStocks across all branches and preserve imageUrl', () async {
        const existingProduct = Product(
          id: 'SP_SOFA_ITALY',
          code: 'SP_SOFA_ITALY',
          name: 'Sofa Da Bò Ý Nhập Khẩu',
          barcode: '893600999111',
          brand: 'Milano Design',
          price: 28000000.0,
          costPrice: 18000000.0,
          branchStocks: {
            'store_001': 12,
            'store_002': 6,
          },
          category: 'Sofa',
          category3Levels: 'Phòng khách>>Sofa>>Sofa Da',
          imageUrl: 'https://cdn.stores.vn/products/sofa_milano_canonical.jpg',
          images: ['https://cdn.stores.vn/products/sofa_milano_canonical.jpg'],
        );

        final prodRepo = _FakeProductRepository([existingProduct]);
        final invRepo = _FakeInventoryRepository();

        final useCase = ImportProductsUseCase(
          productRepository: prodRepo,
          inventoryRepository: invRepo,
        );

        // Adversarial duplicate product:
        // Same code 'SP_SOFA_ITALY'
        // Stock says 999 or 0
        // ImageUrl points to different URL or is empty
        // Price updated to 29,000,000
        const adversarialProduct = Product(
          id: 'prod_temp_id_999',
          code: 'SP_SOFA_ITALY',
          name: 'Sofa Da Bò Ý Nhập Khẩu (2026 Model)',
          barcode: '893600999111',
          price: 29000000.0,
          costPrice: 19000000.0,
          branchStocks: {
            'store_001': 999,
            'store_002': 0,
          },
          category: 'Sofa',
          category3Levels: 'Phòng khách>>Sofa>>Sofa Da',
          imageUrl: 'https://attacker.com/unwanted_overwrite.jpg',
          images: ['https://attacker.com/unwanted_overwrite.jpg'],
        );

        final result = await useCase.execute(
          products: [adversarialProduct],
          targetStoreId: 'store_001',
        );

        expect(result.total, 1);
        expect(result.added, 0);
        expect(result.updated, 1, reason: 'Duplicate product must be updated');
        expect(result.errors, 0);

        final stored = prodRepo.storage['SP_SOFA_ITALY'];
        expect(stored, isNotNull);

        // INVARIANT 1: branchStocks strictly preserved!
        expect(stored!.branchStocks['store_001'], 12,
            reason: 'store_001 stock must remain 12, not overwritten with 999');
        expect(stored.branchStocks['store_002'], 6,
            reason: 'store_002 stock must remain 6, not overwritten with 0');

        // INVARIANT 2: Canonical imageUrl and images preserved!
        expect(stored.imageUrl, 'https://cdn.stores.vn/products/sofa_milano_canonical.jpg',
            reason: 'Existing imageUrl must NOT be overwritten');
        expect(stored.images, ['https://cdn.stores.vn/products/sofa_milano_canonical.jpg']);

        // INVARIANT 3: Metadata updated
        expect(stored.name, 'Sofa Da Bò Ý Nhập Khẩu (2026 Model)');
        expect(stored.price, 29000000.0);
        expect(stored.costPrice, 19000000.0);

        // INVARIANT 4: Zero initial stock inventory transactions recorded for duplicate
        expect(invRepo.transactions, isEmpty,
            reason: 'No initial stock transaction should be created for duplicate products');
      });

      test('5.2 Imported product populates imageUrl when existing product had no image', () async {
        const existingNoImage = Product(
          id: 'SP_BAN_TRON',
          code: 'SP_BAN_TRON',
          name: 'Bàn tròn gỗ xoan đào',
          price: 3500000.0,
          costPrice: 2000000.0,
          category: 'Bàn',
          branchStocks: {'store_001': 4},
          imageUrl: null,
          images: [],
        );

        final prodRepo = _FakeProductRepository([existingNoImage]);
        final invRepo = _FakeInventoryRepository();

        final useCase = ImportProductsUseCase(
          productRepository: prodRepo,
          inventoryRepository: invRepo,
        );

        const importedWithImage = Product(
          id: 'SP_BAN_TRON',
          code: 'SP_BAN_TRON',
          name: 'Bàn tròn gỗ xoan đào',
          price: 3500000.0,
          costPrice: 2000000.0,
          category: 'Bàn',
          branchStocks: {'store_001': 99},
          imageUrl: 'https://cdn.stores.vn/ban_tron.jpg',
          images: ['https://cdn.stores.vn/ban_tron.jpg'],
        );

        final result = await useCase.execute(
          products: [importedWithImage],
          targetStoreId: 'store_001',
        );

        expect(result.updated, 1);
        final stored = prodRepo.storage['SP_BAN_TRON']!;
        expect(stored.imageUrl, 'https://cdn.stores.vn/ban_tron.jpg');
        expect(stored.images, ['https://cdn.stores.vn/ban_tron.jpg']);
        expect(stored.branchStocks['store_001'], 4); // stock preserved
      });

      test('5.3 Intra-batch duplicate product dedups and preserves first stock', () async {
        final prodRepo = _FakeProductRepository();
        final invRepo = _FakeInventoryRepository();

        final useCase = ImportProductsUseCase(
          productRepository: prodRepo,
          inventoryRepository: invRepo,
        );

        final batch = <Product>[
          const Product(
            id: 'SP_BATCH_01',
            code: 'SP_BATCH_01',
            name: 'Kệ tivi sồi nga 1m8',
            price: 4500000.0,
            costPrice: 2800000.0,
            category: 'Kệ tivi',
            branchStocks: {'store_001': 7},
          ),
          const Product(
            id: 'SP_BATCH_01_ALT',
            code: 'SP_BATCH_01',
            name: 'Kệ tivi sồi nga 1m8 (Mẫu mới)',
            price: 4800000.0,
            costPrice: 3000000.0,
            category: 'Kệ tivi',
            branchStocks: {'store_001': 999},
          ),
        ];

        final result = await useCase.execute(
          products: batch,
          targetStoreId: 'store_001',
        );

        expect(result.total, 2);
        expect(result.added, 1);
        expect(result.updated, 1);

        final stored = prodRepo.storage['SP_BATCH_01']!;
        expect(stored.name, 'Kệ tivi sồi nga 1m8 (Mẫu mới)');
        expect(stored.price, 4800000.0);
        expect(stored.branchStocks['store_001'], 7); // Preserves initial stock from item 1
        expect(invRepo.transactions.length, 1, reason: 'Only 1 initial transaction created');
      });
    });
  });
}
