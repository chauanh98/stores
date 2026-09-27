import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/usecases/cancel_invoice_usecase.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';

class _AdversarialOrderRepo implements OrderRepository, OrderRepositoryReturnHandler {
  final Map<String, Order> orders = {};
  final Map<String, ReturnOrder> returnOrders = {};

  @override
  Future<void> create(Order order) async => orders[order.id] = order;

  @override
  Future<void> update(Order order) async => orders[order.id] = order;

  @override
  Future<void> delete(String orderId) async => orders.remove(orderId);

  @override
  Future<Order?> fetchById(String orderId) async => orders[orderId];

  @override
  Stream<List<Order>> watchAll() => Stream.value(orders.values.toList());

  @override
  Stream<List<Order>> watchByCustomer(String customerId) =>
      Stream.value(orders.values.where((o) => o.customerId == customerId).toList());

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value(orders.values.toList());

  @override
  Future<void> createReturn(ReturnOrder returnOrder) async {
    returnOrders[returnOrder.id] = returnOrder;
  }

  @override
  Future<ReturnOrder?> fetchReturnById(String returnId) async => returnOrders[returnId];

  @override
  Stream<List<ReturnOrder>> watchReturnsByDateRange(DateTime start, DateTime end) =>
      Stream.value(returnOrders.values.toList());

  @override
  Stream<List<ReturnOrder>> watchReturnsByOrderId(String orderId) =>
      Stream.value(returnOrders.values.where((r) => r.orderId == orderId).toList());
}

class _AdversarialProductRepo implements ProductRepository {
  final Map<String, Product> products = {};

  @override
  Future<void> delete(String id) async => products.remove(id);

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<void> updateStock(String id, int newStock) async {
    final p = products[id];
    if (p != null) {
      products[id] = p.copyWith(branchStocks: {'store_002': newStock});
    }
  }

  @override
  Future<void> upsert(Product product) async => products[product.id] = product;

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());
}

class _AdversarialInventoryRepo implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async => transactions.add(tx);

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(transactions.where((t) => t.productId == productId).toList());

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime startDate, DateTime endDate) =>
      Stream.value(transactions);
}

class _AdversarialCustomerRepo implements CustomerRepository {
  final Map<String, Customer> customers = {};

  @override
  Future<void> delete(String id) async => customers.remove(id);

  @override
  Future<Customer?> fetchById(String id) async => customers[id];

  @override
  Future<void> upsert(Customer customer) async =>
      customers[customer.id] = customer;

  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers.values.toList());
}

void main() {
  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Khánh Đăng',
    role: 'admin',
    storeId: 'store_002',
  );

  group('Adversarial Reviewer: Comprehensive Edge Case & Invariant Verification', () {
    test('1. OrderModel.fromMap sanitizes debtAmount to 0.0 across all cancellation strings', () {
      final variations = [
        'cancelled',
        'Canceled',
        'Đã hủy',
        'da huy',
        'ĐÃ HUỶ',
        'CANCEL',
      ];

      for (final statusStr in variations) {
        final map = {
          'id': 'HD_TEST_$statusStr',
          'customerId': 'KH_TEST',
          'total': 10000000.0,
          'discount': 1000000.0,
          'amountPaid': 0.0,
          'debtAmount': 9000000.0, // Positive debt in map
          'status': statusStr,
          'items': [
            {'productId': 'P1', 'productName': 'P1', 'quantity': 1, 'price': 10000000.0},
          ],
        };

        final model = OrderModel.fromMap(map);
        expect(model.status, equals('cancelled'),
            reason: 'Status string "$statusStr" must resolve to "cancelled"');
        expect(model.debtAmount, equals(0.0),
            reason: 'Cancelled order in OrderModel must strictly have debtAmount == 0.0');
        expect(model.toMap()['debtAmount'], equals(0.0),
            reason: 'Serialized map must write 0.0 for debtAmount');
      }
    });

    test('2. CancelInvoiceUseCase explicitly resets debtAmount to 0.0 in entity and repo', () async {
      final now = DateTime.now();
      final activeOrder = Order(
        id: 'HD_CANCEL_INVOICE_TEST',
        customerId: 'KH01',
        customerName: 'Nguyễn Văn Test',
        createdAt: now,
        total: 5000000.0,
        discount: 500000.0,
        amountPaid: 1500000.0,
        debtAmount: 3000000.0,
        status: 'completed',
        storeId: 'store_002',
        items: const [],
      );

      final orderRepo = _AdversarialOrderRepo();
      await orderRepo.create(activeOrder);

      final cancelUseCase = CancelInvoiceUseCase(
        orderRepository: orderRepo,
        productRepository: _AdversarialProductRepo(),
        inventoryRepository: _AdversarialInventoryRepo(),
        customerRepository: _AdversarialCustomerRepo(),
      );

      final cancelledOrder = await cancelUseCase.execute(
        order: activeOrder,
        cancelReason: 'Khách hàng đổi ý không mua nữa',
        currentUser: adminUser,
        storeId: 'store_002',
      );

      expect(cancelledOrder.isCancelled, isTrue);
      expect(cancelledOrder.debtAmount, equals(0.0),
          reason: 'CancelInvoiceUseCase must set debtAmount = 0.0');
      expect(cancelledOrder.remainingDebt, equals(0.0));
      expect(cancelledOrder.hasDebt, isFalse);

      final saved = await orderRepo.fetchById('HD_CANCEL_INVOICE_TEST');
      expect(saved?.debtAmount, equals(0.0));
      expect(saved?.remainingDebt, equals(0.0));
    });

    test('3. Untested Edge Case 3: Partial return followed by invoice cancellation prevents negative debt and double credit', () async {
      final orderDate = DateTime(2026, 9, 1, 10, 0);

      const prod1 = Product(
        id: 'P_ITEM_A',
        name: 'Item A',
        code: 'IA',
        price: 3000000.0,
        costPrice: 2000000.0,
        category: 'Hàng hóa',
        branchStocks: {'store_002': 10},
      );
      const prod2 = Product(
        id: 'P_ITEM_B',
        name: 'Item B',
        code: 'IB',
        price: 4000000.0,
        costPrice: 2500000.0,
        category: 'Hàng hóa',
        branchStocks: {'store_002': 5},
      );

      final prodRepo = _AdversarialProductRepo();
      await prodRepo.upsert(prod1);
      await prodRepo.upsert(prod2);

      final invRepo = _AdversarialInventoryRepo();
      final orderRepo = _AdversarialOrderRepo();
      final custRepo = _AdversarialCustomerRepo();

      // Original order: 2 Item A (6M) + 1 Item B (4M) = 10M total.
      // Discount = 1M (10%). netPayable = 9M.
      // Amount paid = 3M, debt = 6M.
      final originalOrder = Order(
        id: 'HD_RETURN_THEN_CANCEL',
        customerId: 'KH_PARTIAL',
        customerName: 'Khách hàng VIP',
        createdAt: orderDate,
        total: 10000000.0,
        discount: 1000000.0,
        amountPaid: 3000000.0,
        debtAmount: 6000000.0,
        status: 'completed',
        storeId: 'store_002',
        items: [
          OrderItem(
            productId: 'P_ITEM_A',
            productName: 'Item A',
            quantity: 2,
            price: 3000000.0,
            warrantyMonths: 0,
            purchaseDate: orderDate,
          ),
          OrderItem(
            productId: 'P_ITEM_B',
            productName: 'Item B',
            quantity: 1,
            price: 4000000.0,
            warrantyMonths: 0,
            purchaseDate: orderDate,
          ),
        ],
      );
      await orderRepo.create(originalOrder);

      const initialCustomer = Customer(
        id: 'KH_PARTIAL',
        name: 'Khách hàng VIP',
        phone: '0901234567',
        email: '',
        address: '',
        purchases: [],
        currentDebt: 6000000.0,
        totalSales: 10000000.0,
        netSales: 9000000.0,
      );
      await custRepo.upsert(initialCustomer);

      // Phase 1: Return 1 unit of Item A (gross 3M, discount 300k, refund 2.7M)
      final returnUseCase = ProcessReturnOrderUseCase(
        orderRepository: orderRepo,
        productRepository: prodRepo,
        inventoryRepository: invRepo,
        customerRepository: custRepo,
      );

      final returnResult = await returnUseCase.execute(
        originalOrder: originalOrder,
        returnItems: const [
          ReturnOrderItem(
            productId: 'P_ITEM_A',
            productName: 'Item A',
            quantity: 1,
            price: 3000000.0,
          ),
        ],
        storeId: 'store_002',
        currentUser: adminUser,
        reason: 'Khách đổi trả 1 sản phẩm',
      );

      expect(returnResult.returnOrder.totalReturnAmount, equals(2700000.0));
      expect(returnResult.returnOrder.totalRefund, equals(2700000.0));
      expect(returnResult.returnOrder.debtDeducted, equals(2700000.0));
      expect(returnResult.returnOrder.cashRefunded, equals(0.0));

      // Customer debt after return: 6.000.000 - 2.700.000 = 3.300.000
      final custAfterReturn = await custRepo.fetchById('KH_PARTIAL');
      expect(custAfterReturn?.currentDebt, equals(3300000.0));
      expect(custAfterReturn?.netSales, equals(6300000.0));

      final orderAfterReturn = await orderRepo.fetchById('HD_RETURN_THEN_CANCEL');
      expect(orderAfterReturn, isNotNull);
      expect(orderAfterReturn!.remainingDebt, equals(3300000.0));
      expect(orderAfterReturn.debtAmount, equals(3300000.0));

      // Phase 2: Now Cancel the remaining order
      final cancelUseCase = CancelInvoiceUseCase(
        orderRepository: orderRepo,
        productRepository: prodRepo,
        inventoryRepository: invRepo,
        customerRepository: custRepo,
      );

      final cancelledOrder = await cancelUseCase.execute(
        order: orderAfterReturn,
        cancelReason: 'Hủy toàn bộ đơn hàng sau khi đã trả bớt',
        currentUser: adminUser,
        storeId: 'store_002',
      );

      expect(cancelledOrder.isCancelled, isTrue);
      expect(cancelledOrder.debtAmount, equals(0.0));
      expect(cancelledOrder.remainingDebt, equals(0.0));
      expect(cancelledOrder.hasDebt, isFalse);

      // Customer debt must be 0.0 (NO negative debt, NO double credit deduction)
      final custAfterCancel = await custRepo.fetchById('KH_PARTIAL');
      expect(custAfterCancel?.currentDebt, equals(0.0));
      expect(custAfterCancel?.displayCurrentDebt, equals(0.0));

      // Check stock restoration:
      // Item A: 1 returned in returnUseCase (+1), 1 remaining restored in cancelUseCase (+1) -> total +2
      final p1 = await prodRepo.fetchById('P_ITEM_A');
      expect(p1?.branchStocks['store_002'], equals(12));

      // Item B: 1 restored in cancelUseCase (+1) -> 5 + 1 = 6
      final p2 = await prodRepo.fetchById('P_ITEM_B');
      expect(p2?.branchStocks['store_002'], equals(6));
    });

    test('4. Untested Edge Case 4: Excel with row discounts, invoice discount, and cancelled orders', () {
      final excel = xl.Excel.createExcel();
      final sheet = excel['Sheet1'];

      // Header row
      sheet.appendRow([
        xl.TextCellValue('Mã hóa đơn'),
        xl.TextCellValue('Thời gian'),
        xl.TextCellValue('Mã khách hàng'),
        xl.TextCellValue('Tên khách hàng'),
        xl.TextCellValue('Mã hàng'),
        xl.TextCellValue('Tên hàng'),
        xl.TextCellValue('Số lượng'),
        xl.TextCellValue('Đơn giá'),
        xl.TextCellValue('Thành tiền'),
        xl.TextCellValue('Tổng tiền hàng'),
        xl.TextCellValue('Giảm giá hóa đơn'),
        xl.TextCellValue('Khách cần trả'),
        xl.TextCellValue('Khách đã trả'),
        xl.TextCellValue('Còn nợ'),
        xl.TextCellValue('Trạng thái'),
        xl.TextCellValue('Chi nhánh'),
      ]);

      // Row 1: Order HD_EX_01 (completed with discount)
      sheet.appendRow([
        xl.TextCellValue('HD_EX_01'),
        xl.TextCellValue('01/09/2026 10:00:00'),
        xl.TextCellValue('KH01'),
        xl.TextCellValue('Khách 1'),
        xl.TextCellValue('P1'),
        xl.TextCellValue('SP 1'),
        const xl.IntCellValue(2),
        const xl.DoubleCellValue(2000000.0),
        const xl.DoubleCellValue(4000000.0),
        const xl.DoubleCellValue(4000000.0), // Tổng tiền hàng
        const xl.DoubleCellValue(500000.0),  // Giảm giá
        const xl.DoubleCellValue(3500000.0), // Khách cần trả
        const xl.DoubleCellValue(1500000.0), // Đã trả
        const xl.DoubleCellValue(2000000.0), // Còn nợ
        xl.TextCellValue('Đã hoàn thành'),
        xl.TextCellValue('Chi nhánh Thới Bình'),
      ]);

      // Row 2: Order HD_EX_02 (cancelled, with positive debt in column)
      sheet.appendRow([
        xl.TextCellValue('HD_EX_02'),
        xl.TextCellValue('01/09/2026 11:00:00'),
        xl.TextCellValue('KH02'),
        xl.TextCellValue('Khách 2'),
        xl.TextCellValue('P2'),
        xl.TextCellValue('SP 2'),
        const xl.IntCellValue(1),
        const xl.DoubleCellValue(5000000.0),
        const xl.DoubleCellValue(5000000.0),
        const xl.DoubleCellValue(5000000.0),
        const xl.DoubleCellValue(200000.0),
        const xl.DoubleCellValue(4800000.0),
        const xl.DoubleCellValue(0.0),
        const xl.DoubleCellValue(4800000.0), // Raw debt in Excel column
        xl.TextCellValue('Đã hủy'),
        xl.TextCellValue('Chi nhánh Thới Bình'),
      ]);

      final bytes = Uint8List.fromList(excel.encode()!);
      final parsed = ExcelHelper.parseInvoices(bytes, defaultStoreId: 'store_002');

      expect(parsed.length, equals(2));

      // Check completed order
      final o1 = parsed.firstWhere((o) => o.id == 'HD_EX_01');
      expect(o1.total, equals(4000000.0));
      expect(o1.discount, equals(500000.0));
      expect(o1.netPayable, equals(3500000.0));
      expect(o1.amountPaid, equals(1500000.0));
      expect(o1.debtAmount, equals(2000000.0));
      expect(o1.remainingDebt, equals(2000000.0));
      expect(o1.hasDebt, isTrue);

      // Check cancelled order
      final o2 = parsed.firstWhere((o) => o.id == 'HD_EX_02');
      expect(o2.isCancelled, isTrue);
      expect(o2.total, equals(5000000.0));
      expect(o2.discount, equals(200000.0));
      expect(o2.netPayable, equals(4800000.0));
      expect(o2.debtAmount, equals(0.0),
          reason: 'Cancelled order parsed from Excel must strictly have debtAmount == 0.0');
      expect(o2.remainingDebt, equals(0.0));
      expect(o2.hasDebt, isFalse);
    });
  });
}
