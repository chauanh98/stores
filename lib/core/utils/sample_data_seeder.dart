import 'package:firebase_database/firebase_database.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/warranty.dart';

class SampleDataSeeder {
  static final FirebaseDatabase _db = FirebaseDatabase.instance;

  static Future<void> seedCustomers() async {
    final customersRef = _db.ref('customers');

    // Clear existing data first
    await customersRef.remove();

    final sampleCustomers = _getSampleCustomers();

    for (final customer in sampleCustomers) {
      await customersRef.child(customer.id).set({
        'id': customer.id,
        'name': customer.name,
        'phone': customer.phone,
        'email': customer.email,
        'address': customer.address,
        'purchases': customer.purchases.map((purchase) => {
          'productId': purchase.productId,
          'quantity': purchase.quantity,
          'purchaseDate': purchase.purchaseDate.toIso8601String(),
          'warranty': {
            'months': purchase.warranty.months,
            'expireDate': purchase.warranty.expireDate.toIso8601String(),
          },
        }).toList(),
      });
    }

    print('✅ Seeded ${sampleCustomers.length} customers to Firebase');
  }

  static List<Customer> _getSampleCustomers() {
    final now = DateTime.now();

    return [
      Customer(
        id: 'customer_001',
        name: 'Nguyễn Văn An',
        phone: '0901234567',
        email: 'nguyen.van.an@gmail.com',
        address: '123 Đường Lê Lợi, Quận 1, TP.HCM',
        purchases: [
          Purchase(
            productId: 'product_001',
            quantity: 2,
            purchaseDate: now.subtract(const Duration(days: 30000)),
            warranty: Warranty(
              months: 12,
              expireDate: now.subtract(const Duration(days: 335)),
            ),
          ),
          Purchase(
            productId: 'product_002',
            quantity: 1,
            purchaseDate: now.subtract(const Duration(days: 15)),
            warranty: Warranty(
              months: 6,
              expireDate: now.add(const Duration(days: 165)),
            ),
          ),
        ],
      ),
      Customer(
        id: 'customer_002',
        name: 'Trần Thị Bình',
        phone: '0987654321',
        email: 'tran.thi.binh@yahoo.com',
        address: '456 Đường Nguyễn Huệ, Quận 3, TP.HCM',
        purchases: [
          Purchase(
            productId: 'product_003',
            quantity: 3,
            purchaseDate: now.subtract(const Duration(days: 45)),
            warranty: Warranty(
              months: 24,
              expireDate: now.add(const Duration(days: 675)),
            ),
          ),
        ],
      ),
      Customer(
        id: 'customer_003',
        name: 'Lê Minh Cường',
        phone: '0912345678',
        email: 'le.minh.cuong@outlook.com',
        address: '789 Đường Võ Văn Tần, Quận 3, TP.HCM',
        purchases: [
          Purchase(
            productId: 'product_001',
            quantity: 1,
            purchaseDate: now.subtract(const Duration(days: 60)),
            warranty: Warranty(
              months: 12,
              expireDate: now.add(const Duration(days: 305)),
            ),
          ),
          Purchase(
            productId: 'product_004',
            quantity: 2,
            purchaseDate: now.subtract(const Duration(days: 20)),
            warranty: Warranty(
              months: 18,
              expireDate: now.add(const Duration(days: 520)),
            ),
          ),
          Purchase(
            productId: 'product_005',
            quantity: 1,
            purchaseDate: now.subtract(const Duration(days: 5)),
            warranty: Warranty(
              months: 6,
              expireDate: now.add(const Duration(days: 175)),
            ),
          ),
        ],
      ),
      Customer(
        id: 'customer_004',
        name: 'Phạm Thị Dung',
        phone: '0923456789',
        email: 'pham.thi.dung@gmail.com',
        address: '321 Đường Điện Biên Phủ, Quận Bình Thạnh, TP.HCM',
        purchases: [
          Purchase(
            productId: 'product_002',
            quantity: 1,
            purchaseDate: now.subtract(const Duration(days: 10)),
            warranty: Warranty(
              months: 12,
              expireDate: now.add(const Duration(days: 355)),
            ),
          ),
        ],
      ),
      Customer(
        id: 'customer_005',
        name: 'Hoàng Văn Em',
        phone: '0934567890',
        email: 'hoang.van.em@hotmail.com',
        address: '654 Đường Cách Mạng Tháng 8, Quận 10, TP.HCM',
        purchases: [],
      ),
      Customer(
        id: 'customer_006',
        name: 'Võ Thị Phương',
        phone: '0945678901',
        email: 'vo.thi.phuong@gmail.com',
        address: '987 Đường Lý Tự Trọng, Quận 1, TP.HCM',
        purchases: [
          Purchase(
            productId: 'product_003',
            quantity: 2,
            purchaseDate: now.subtract(const Duration(days: 25)),
            warranty: Warranty(
              months: 24,
              expireDate: now.add(const Duration(days: 695)),
            ),
          ),
          Purchase(
            productId: 'product_006',
            quantity: 1,
            purchaseDate: now.subtract(const Duration(days: 8)),
            warranty: Warranty(
              months: 12,
              expireDate: now.add(const Duration(days: 357)),
            ),
          ),
        ],
      ),
      Customer(
        id: 'customer_007',
        name: 'Đặng Minh Giang',
        phone: '0956789012',
        email: 'dang.minh.giang@yahoo.com',
        address: '147 Đường Pasteur, Quận 3, TP.HCM',
        purchases: [
          Purchase(
            productId: 'product_004',
            quantity: 1,
            purchaseDate: now.subtract(const Duration(days: 40)),
            warranty: Warranty(
              months: 18,
              expireDate: now.add(const Duration(days: 500)),
            ),
          ),
        ],
      ),
      Customer(
        id: 'customer_008',
        name: 'Bùi Thị Hoa',
        phone: '0967890123',
        email: 'bui.thi.hoa@gmail.com',
        address: '258 Đường Nguyễn Thị Minh Khai, Quận 1, TP.HCM',
        purchases: [
          Purchase(
            productId: 'product_005',
            quantity: 3,
            purchaseDate: now.subtract(const Duration(days: 12)),
            warranty: Warranty(
              months: 6,
              expireDate: now.add(const Duration(days: 168)),
            ),
          ),
          Purchase(
            productId: 'product_001',
            quantity: 1,
            purchaseDate: now.subtract(const Duration(days: 3)),
            warranty: Warranty(
              months: 12,
              expireDate: now.add(const Duration(days: 362)),
            ),
          ),
        ],
      ),
      Customer(
        id: 'customer_009',
        name: 'Ngô Văn Inh',
        phone: '0978901234',
        email: 'ngo.van.inh@outlook.com',
        address: '369 Đường Hai Bà Trưng, Quận 1, TP.HCM',
        purchases: [],
      ),
      Customer(
        id: 'customer_010',
        name: 'Đinh Thị Kim',
        phone: '0989012345',
        email: 'dinh.thi.kim@hotmail.com',
        address: '741 Đường Đồng Khởi, Quận 1, TP.HCM',
        purchases: [
          Purchase(
            productId: 'product_006',
            quantity: 2,
            purchaseDate: now.subtract(const Duration(days: 18)),
            warranty: Warranty(
              months: 12,
              expireDate: now.add(const Duration(days: 347)),
            ),
          ),
          Purchase(
            productId: 'product_002',
            quantity: 1,
            purchaseDate: now.subtract(const Duration(days: 35)),
            warranty: Warranty(
              months: 6,
              expireDate: now.add(const Duration(days: 145)),
            ),
          ),
          Purchase(
            productId: 'product_003',
            quantity: 1,
            purchaseDate: now.subtract(const Duration(days: 7)),
            warranty: Warranty(
              months: 24,
              expireDate: now.add(const Duration(days: 713)),
            ),
          ),
        ],
      ),
    ];
  }

  static Future<void> seedProducts() async {
    final productsRef = _db.ref('products');

    // Clear existing data first
    await productsRef.remove();

    final sampleProducts = _getSampleProducts();

    for (final product in sampleProducts) {
      await productsRef.child(product.id).set({
        'id': product.id,
        'name': product.name,
        'brand': product.brand,
        'model': product.model,
        'price': product.price,
        'stock': product.stock,
        'category': product.category,
      });
    }

    print('✅ Seeded ${sampleProducts.length} products to Firebase');
  }

  static List<Product> _getSampleProducts() {
    return [
      Product(
        id: 'product_001',
        name: 'iPhone 15 Pro',
        brand: 'Apple',
        model: 'A3108',
        price: 29990000,
        stock: 15,
        category: 'Smartphone',
      ),
      Product(
        id: 'product_002',
        name: 'Samsung Galaxy S24',
        brand: 'Samsung',
        model: 'SM-S921B',
        price: 22990000,
        stock: 12,
        category: 'Smartphone',
      ),
      Product(
        id: 'product_003',
        name: 'MacBook Air M3',
        brand: 'Apple',
        model: 'MLY33',
        price: 32990000,
        stock: 8,
        category: 'Laptop',
      ),
      Product(
        id: 'product_004',
        name: 'Dell XPS 13',
        brand: 'Dell',
        model: 'XPS139320',
        price: 25990000,
        stock: 6,
        category: 'Laptop',
      ),
      Product(
        id: 'product_005',
        name: 'iPad Pro 12.9"',
        brand: 'Apple',
        model: 'MTFQ3',
        price: 24990000,
        stock: 10,
        category: 'Tablet',
      ),
      Product(
        id: 'product_006',
        name: 'Samsung Galaxy Tab S9',
        brand: 'Samsung',
        model: 'SM-X910',
        price: 18990000,
        stock: 7,
        category: 'Tablet',
      ),
    ];
  }

  static Future<void> seedAllData() async {
    print('🌱 Starting to seed sample data...');
    await seedProducts();
    await seedCustomers();
    print('🎉 Sample data seeding completed!');
  }
}