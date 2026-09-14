import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/purchase.dart';
import 'package:stores/domain/entities/transaction_type.dart';

/// Test fixtures and mock generators for Overview / Reports tests
class MockReportData {
  // Factory helpers for domain entities

  static Product createProduct({
    String id = 'prod_001',
    String name = 'Áo thun nam Basic',
    String code = 'AT01',
    String? barcode,
    String? brand = 'StoreBrand',
    String? model,
    double price = 150000.0,
    double costPrice = 90000.0,
    Map<String, int> branchStocks = const {'branch_1': 10, 'branch_2': 5},
    String category = 'Thời trang',
    bool isCombo = false,
    List<ComboComponent> comboComponents = const [],
  }) {
    return Product(
      id: id,
      name: name,
      code: code,
      barcode: barcode,
      brand: brand,
      model: model,
      price: price,
      costPrice: costPrice,
      branchStocks: branchStocks,
      category: category,
      isCombo: isCombo,
      comboComponents: comboComponents,
    );
  }

  static OrderItem createOrderItem({
    String productId = 'prod_001',
    String productName = 'Áo thun nam Basic',
    int quantity = 1,
    double price = 150000.0,
    int warrantyMonths = 0,
    DateTime? purchaseDate,
  }) {
    return OrderItem(
      productId: productId,
      productName: productName,
      quantity: quantity,
      price: price,
      warrantyMonths: warrantyMonths,
      purchaseDate: purchaseDate ?? DateTime(2026, 8, 16, 10, 0),
    );
  }

  static Order createOrder({
    String id = 'order_001',
    String customerId = 'cust_001',
    DateTime? createdAt,
    List<OrderItem>? items,
    double? total,
    String status = 'completed',
    double? amountPaid,
    double debtAmount = 0.0,
    String paymentMethod = 'cash',
    String? createdBy,
    String? createdByName,
  }) {
    final orderItems = items ?? [createOrderItem()];
    final calculatedTotal = total ??
        orderItems.fold<double>(
            0.0, (sum, item) => sum + (item.price * item.quantity));

    return Order(
      id: id,
      customerId: customerId,
      createdAt: createdAt ?? DateTime(2026, 8, 16, 10, 30),
      items: orderItems,
      total: calculatedTotal,
      status: status,
      amountPaid: amountPaid ?? (calculatedTotal - debtAmount),
      debtAmount: debtAmount,
      paymentMethod: paymentMethod,
      createdBy: createdBy,
      createdByName: createdByName,
    );
  }

  static Customer createCustomer({
    String id = 'cust_001',
    String name = 'Nguyễn Văn An',
    String phone = '0901234567',
    String email = 'an.nguyen@example.com',
    String address = '123 Lê Lợi, Q.1, TP.HCM',
    List<Purchase> purchases = const [],
    double? currentDebt = 0.0,
    double? totalSales = 0.0,
    double? netSales = 0.0,
    String? branch = 'branch_1',
    String? status = 'active',
  }) {
    return Customer(
      id: id,
      name: name,
      phone: phone,
      email: email,
      address: address,
      purchases: purchases,
      currentDebt: currentDebt,
      totalSales: totalSales,
      netSales: netSales,
      branch: branch,
      status: status,
    );
  }

  static CustomerDebtTransaction createDebtTransaction({
    String id = 'debt_001',
    String code = 'HD001',
    String customerId = 'cust_001',
    DateTime? date,
    double amount = 500000.0,
    double remainingDebt = 500000.0,
    DebtTransactionType type = DebtTransactionType.invoice,
    String? note = 'Bán hàng ghi nợ',
    String? createdBy = 'admin',
  }) {
    return CustomerDebtTransaction(
      id: id,
      code: code,
      customerId: customerId,
      date: date ?? DateTime(2026, 8, 16, 14, 0),
      amount: amount,
      remainingDebt: remainingDebt,
      type: type,
      note: note,
      createdBy: createdBy,
    );
  }

  static InventoryTransaction createInventoryTransaction({
    String id = 'inv_001',
    String productId = 'prod_001',
    TransactionType type = TransactionType.import,
    int quantity = 20,
    DateTime? date,
    double importPrice = 90000.0,
    String note = 'Nhập hàng đợt 1',
    String? createdBy = 'admin',
    String? createdByName = 'Quản trị viên',
  }) {
    return InventoryTransaction(
      id: id,
      productId: productId,
      type: type,
      quantity: quantity,
      date: date ?? DateTime(2026, 8, 1, 9, 0),
      note: note,
      importPrice: importPrice,
      createdBy: createdBy,
      createdByName: createdByName,
    );
  }

  // Predefined standard catalogs for comprehensive testing

  /// Standard multi-category product catalog
  static List<Product> sampleProductCatalog() {
    return [
      // Category: Thời trang
      createProduct(
        id: 'p_fashion_1',
        name: 'Áo thun Polo Nam',
        code: 'AP01',
        price: 250000.0,
        costPrice: 150000.0,
        branchStocks: {'branch_1': 20, 'branch_2': 15},
        category: 'Thời trang',
      ),
      createProduct(
        id: 'p_fashion_2',
        name: 'Quần Jean Slimfit',
        code: 'QJ01',
        price: 450000.0,
        costPrice: 280000.0,
        branchStocks: {'branch_1': 10, 'branch_2': 5},
        category: 'Thời trang',
      ),
      // Category: Điện thoại & Phụ kiện
      createProduct(
        id: 'p_tech_1',
        name: 'Cáp sạc Type-C Fast Charge',
        code: 'CC01',
        price: 120000.0,
        costPrice: 60000.0,
        branchStocks: {'branch_1': 50, 'branch_2': 30},
        category: 'Điện thoại & Phụ kiện',
      ),
      createProduct(
        id: 'p_tech_2',
        name: 'Tai nghe Bluetooth Pro',
        code: 'TN01',
        price: 650000.0,
        costPrice: 400000.0,
        branchStocks: {'branch_1': 4, 'branch_2': 1}, // Low stock (total 5)
        category: 'Điện thoại & Phụ kiện',
      ),
      createProduct(
        id: 'p_tech_3',
        name: 'Củ sạc nhanh 65W GaN',
        code: 'CS65',
        price: 350000.0,
        costPrice: 200000.0,
        branchStocks: {'branch_1': 0, 'branch_2': 0}, // Out of stock (total 0)
        category: 'Điện thoại & Phụ kiện',
      ),
      // Category: Gia dụng
      createProduct(
        id: 'p_home_1',
        name: 'Bình giữ nhiệt 500ml',
        code: 'BGN01',
        price: 180000.0,
        costPrice: 100000.0,
        branchStocks: {'branch_1': 8, 'branch_2': 0},
        category: 'Gia dụng',
      ),
      // Category: Mỹ phẩm
      createProduct(
        id: 'p_beauty_1',
        name: 'Kem chống nắng SPF 50+',
        code: 'KCN01',
        price: 320000.0,
        costPrice: 190000.0,
        branchStocks: {'branch_1': 2, 'branch_2': 1}, // Low stock (total 3)
        category: 'Mỹ phẩm',
      ),
    ];
  }

  /// Standard customers
  static List<Customer> sampleCustomerList() {
    return [
      createCustomer(
        id: 'c_vip_1',
        name: 'Trần Thị Bích',
        phone: '0912345678',
        currentDebt: 0.0,
        totalSales: 15000000.0,
      ),
      createCustomer(
        id: 'c_debt_1',
        name: 'Lê Văn Cường',
        phone: '0987654321',
        currentDebt: 3500000.0,
        totalSales: 8000000.0,
      ),
      createCustomer(
        id: 'c_regular_1',
        name: 'Phạm Minh Đức',
        phone: '0933445566',
        currentDebt: 1200000.0,
        totalSales: 4500000.0,
      ),
      createCustomer(
        id: 'c_new_1',
        name: 'Hoàng Anh Tuấn',
        phone: '0977889900',
        currentDebt: 0.0,
        totalSales: 500000.0,
      ),
    ];
  }
}
