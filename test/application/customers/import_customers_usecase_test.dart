import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/customers/usecases/import_customers_usecase.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/purchase.dart';
import 'package:stores/domain/entities/warranty.dart';
import 'package:stores/domain/repositories/customer_repository.dart';

class _FakeCustomerRepository implements CustomerRepository {
  final Map<String, Customer> storage = {};
  final StreamController<List<Customer>> _controller =
      StreamController<List<Customer>>.broadcast();

  _FakeCustomerRepository([List<Customer> initial = const []]) {
    for (final c in initial) {
      storage[c.id] = c;
    }
  }

  @override
  Stream<List<Customer>> watchAll() =>
      Stream.value(storage.values.toList());

  @override
  Future<Customer?> fetchById(String id) async => storage[id];

  @override
  Future<void> upsert(Customer customer) async {
    storage[customer.id] = customer;
    _controller.add(storage.values.toList());
  }

  @override
  Future<void> delete(String id) async {
    storage.remove(id);
    _controller.add(storage.values.toList());
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  group('ImportCustomersUseCase Tests', () {
    late _FakeCustomerRepository customerRepo;
    late ImportCustomersUseCase useCase;

    setUp(() {
      customerRepo = _FakeCustomerRepository();
      useCase = ImportCustomersUseCase(
        customerRepository: customerRepo,
      );
    });

    tearDown(() {
      customerRepo.dispose();
    });

    test('Empty customers list returns empty ImportResult', () async {
      final result = await useCase.execute(customers: []);
      expect(result.total, 0);
      expect(result.added, 0);
      expect(result.updated, 0);
      expect(result.skipped, 0);
      expect(result.errors, 0);
      expect(result.isSuccess, isTrue);
    });

    test('New customer is added successfully', () async {
      const newCustomer = Customer(
        id: 'cust_001',
        name: 'Nguyễn Văn A',
        phone: '0901234567',
        email: 'vana@example.com',
        address: 'Hà Nội',
        purchases: [],
        currentDebt: 0.0,
      );

      final result = await useCase.execute(customers: [newCustomer]);

      expect(result.total, 1);
      expect(result.added, 1);
      expect(result.updated, 0);
      expect(result.errors, 0);

      final stored = await customerRepo.fetchById('cust_001');
      expect(stored, isNotNull);
      expect(stored!.name, 'Nguyễn Văn A');
      expect(stored.phone, '0901234567');
    });

    test(
        'Duplicate by ID updates contact info but strictly preserves purchases and debt',
        () async {
      final initialPurchase = Purchase(
        productId: 'prod_100',
        quantity: 2,
        purchaseDate: DateTime(2026, 1, 15),
        warranty: Warranty(months: 12, expireDate: DateTime(2027, 1, 15)),
      );

      final existing = Customer(
        id: 'cust_vip_01',
        name: 'Trần Thị B',
        phone: '0912345678',
        email: 'old_email@example.com',
        address: 'Đà Nẵng',
        purchases: [initialPurchase],
        currentDebt: 750000.0,
        totalSales: 3500000.0,
        netSales: 3500000.0,
        group: 'Bạc',
        notes: 'Khách quen',
      );
      await customerRepo.upsert(existing);

      // Imported customer with new contact info but empty purchases & zero debt in Excel
      const imported = Customer(
        id: 'cust_vip_01',
        name: 'Trần Thị B (VIP)',
        phone: '0912345678',
        email: 'new_email@example.com',
        address: 'TP. Hồ Chí Minh',
        purchases: [], // Empty from Excel
        currentDebt: 0.0, // Should NOT overwrite real debt
        totalSales: 0.0,
        netSales: 0.0,
        group: 'Vàng',
        notes: 'Nâng hạng VIP',
      );

      final result = await useCase.execute(customers: [imported]);

      expect(result.total, 1);
      expect(result.updated, 1);
      expect(result.added, 0);

      final stored = await customerRepo.fetchById('cust_vip_01');
      expect(stored, isNotNull);

      // 1. Contact info updated
      expect(stored!.name, 'Trần Thị B (VIP)');
      expect(stored.email, 'new_email@example.com');
      expect(stored.address, 'TP. Hồ Chí Minh');
      expect(stored.group, 'Vàng');
      expect(stored.notes, 'Nâng hạng VIP');

      // 2. CRITICAL PRESERVATION:
      expect(stored.purchases.length, 1);
      expect(stored.purchases.first.productId, 'prod_100');
      expect(stored.currentDebt, 750000.0);
      expect(stored.totalSales, 3500000.0);
      expect(stored.netSales, 3500000.0);
    });

    test(
        'Duplicate by Phone matches normalized phone (+84 and spaces) and preserves debt',
        () async {
      const existing = Customer(
        id: 'CUST_ORIGINAL_ID',
        name: 'Lê Văn C',
        phone: '0987654321',
        email: 'levanc@example.com',
        address: 'Hải Phòng',
        purchases: [],
        currentDebt: 1200000.0,
        totalSales: 5000000.0,
        netSales: 5000000.0,
      );
      await customerRepo.upsert(existing);

      // Imported from Excel has generated ID and international phone format
      const imported = Customer(
        id: 'CUST_EXCEL_NEW_123',
        name: 'Lê Văn C (Cập nhật)',
        phone: '+84 987 654 321', // Formatted differently
        email: 'levanc_new@example.com',
        address: 'Hải Phòng Mới',
        purchases: [],
        currentDebt: 0.0,
      );

      final result = await useCase.execute(customers: [imported]);

      expect(result.updated, 1);
      expect(result.added, 0);

      // Should have updated existing customer by original ID
      final stored = await customerRepo.fetchById('CUST_ORIGINAL_ID');
      expect(stored, isNotNull);
      expect(stored!.name, 'Lê Văn C (Cập nhật)');
      expect(stored.email, 'levanc_new@example.com');
      expect(stored.address, 'Hải Phòng Mới');
      expect(stored.currentDebt, 1200000.0); // Preserved!
      expect(stored.totalSales, 5000000.0); // Preserved!

      // New ID was not created
      final notFound = await customerRepo.fetchById('CUST_EXCEL_NEW_123');
      expect(notFound, isNull);
    });

    test('Empty phone numbers do not match each other as duplicates', () async {
      const c1 = Customer(
        id: 'cust_no_phone_1',
        name: 'Khách lẻ 1',
        phone: '',
        email: '',
        address: '',
        purchases: [],
      );
      const c2 = Customer(
        id: 'cust_no_phone_2',
        name: 'Khách lẻ 2',
        phone: '   ',
        email: '',
        address: '',
        purchases: [],
      );

      final result = await useCase.execute(customers: [c1, c2]);

      expect(result.total, 2);
      expect(result.added, 2);
      expect(result.updated, 0);

      final s1 = await customerRepo.fetchById('cust_no_phone_1');
      final s2 = await customerRepo.fetchById('cust_no_phone_2');
      expect(s1, isNotNull);
      expect(s2, isNotNull);
    });

    test('normalizePhone handles diverse Vietnamese formats correctly', () {
      expect(ImportCustomersUseCase.normalizePhone('0912345678'), '0912345678');
      expect(ImportCustomersUseCase.normalizePhone('+84912345678'), '0912345678');
      expect(ImportCustomersUseCase.normalizePhone('84912345678'), '0912345678');
      expect(ImportCustomersUseCase.normalizePhone('0912 345 678'), '0912345678');
      expect(ImportCustomersUseCase.normalizePhone('0912.345.678'), '0912345678');
      expect(ImportCustomersUseCase.normalizePhone('912345678'), '0912345678');
      expect(ImportCustomersUseCase.normalizePhone(''), '');
      expect(ImportCustomersUseCase.normalizePhone(null), '');
    });

    test('Summary string matches standard format', () async {
      const c1 = Customer(
        id: 'c_sum_1',
        name: 'C1',
        phone: '0900000001',
        email: '',
        address: '',
        purchases: [],
      );
      await customerRepo.upsert(c1);

      const imported1 = Customer(
        id: 'c_sum_1',
        name: 'C1 Updated',
        phone: '0900000001',
        email: '',
        address: '',
        purchases: [],
      );
      const imported2 = Customer(
        id: 'c_sum_2',
        name: 'C2 New',
        phone: '0900000002',
        email: '',
        address: '',
        purchases: [],
      );

      final result = await useCase.execute(customers: [imported1, imported2]);

      expect(result.total, 2);
      expect(result.added, 1);
      expect(result.updated, 1);
      expect(
        result.toSummaryString(),
        'Tổng số dòng: 2 | Thêm mới: 1 | Cập nhật: 1 | Bỏ qua: 0 | Lỗi: 0',
      );
    });
  });
}
