import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/core/utils/sample_image_helper.dart';
import 'package:stores/core/utils/vietnamese_text_helper.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/data/models/inventory_transaction_model.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/application/orders/cart_providers.dart';

void main() {
  group('M5 Tier 5 Adversarial & Cross-Feature Integration Test Suite', () {
    // =========================================================================
    // AXIS 1: Multi-Branch Lifecycle & Stock Scoping Stress Tests
    // =========================================================================
    group('Axis 1: Multi-Branch Lifecycle & Scoping Integrity', () {
      test('Multi-branch import at Store 1 and direct stock audit at Store 2 preserves branch isolation', () {
        // Product initially has 10 units at store_001 (Đông Thắng) and 5 units at store_002 (Thới Bình)
        const initialProduct = Product(
          id: 'prod_mb_001',
          name: 'Nước tăng lực Compact Cherry',
          code: 'COMPACT01',
          price: 12000,
          costPrice: 8000,
          branchStocks: {'store_001': 10, 'store_002': 5},
          category: 'Đồ uống & Giải khát',
        );

        expect(initialProduct.stockInBranch('store_001'), 10);
        expect(initialProduct.stockInBranch('store_002'), 5);
        expect(initialProduct.stock, 15);

        // Step 1: Simulate Import of 20 units at store_001
        final importTxStore1 = InventoryTransaction(
          id: 'tx_import_store_001',
          productId: initialProduct.id,
          type: TransactionType.import,
          quantity: 20,
          date: DateTime(2026, 8, 1, 10, 0),
          note: 'Nhập hàng từ nhà cung cấp chi nhánh Đông Thắng',
          importPrice: 8200,
          createdBy: 'manager_dt',
          createdByName: 'Quản lý ĐT',
        );

        final productAfterImport = initialProduct.copyWith(
          branchStocks: {
            ...initialProduct.branchStocks,
            'store_001': initialProduct.stockInBranch('store_001') + importTxStore1.quantity,
          },
        );

        expect(productAfterImport.stockInBranch('store_001'), 30);
        expect(productAfterImport.stockInBranch('store_002'), 5); // Store 2 stock remains untouched
        expect(productAfterImport.stock, 35);

        // Step 2: Simulate Direct Stock Adjustment at Store 2 from 5 units to 18 units (diff: +13)
        final oldStore2Stock = productAfterImport.stockInBranch('store_002');
        const newStore2Stock = 18;
        final stockDiff = newStore2Stock - oldStore2Stock; // +13

        final auditTxStore2 = InventoryTransaction(
          id: 'tx_audit_store_002',
          productId: productAfterImport.id,
          type: TransactionType.inventoryAudit,
          quantity: stockDiff.abs(),
          date: DateTime(2026, 8, 2, 14, 0),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: $oldStore2Stock -> Tồn mới: $newStore2Stock, chênh lệch: +$stockDiff)',
          importPrice: productAfterImport.costPrice,
          createdBy: 'supervisor_tb',
          createdByName: 'Giám sát TB',
        );

        final productAfterAudit = productAfterImport.copyWith(
          branchStocks: {
            ...productAfterImport.branchStocks,
            'store_002': newStore2Stock,
          },
        );

        // Assert final stocks
        expect(productAfterAudit.stockInBranch('store_001'), 30);
        expect(productAfterAudit.stockInBranch('store_002'), 18);
        expect(productAfterAudit.stock, 48);

        // Verify transaction models serialization and typing
        final modelImport = InventoryTransactionModel.fromMap({
          'id': importTxStore1.id,
          'productId': importTxStore1.productId,
          'type': 'import',
          'quantity': importTxStore1.quantity,
          'date': importTxStore1.date.toIso8601String(),
          'note': importTxStore1.note,
          'importPrice': importTxStore1.importPrice,
          'createdBy': importTxStore1.createdBy,
          'createdByName': importTxStore1.createdByName,
        });
        expect(modelImport.toTransactionType(), TransactionType.import);

        final modelAudit = InventoryTransactionModel.fromMap({
          'id': auditTxStore2.id,
          'productId': auditTxStore2.productId,
          'type': 'INVENTORY_AUDIT',
          'quantity': auditTxStore2.quantity,
          'date': auditTxStore2.date.toIso8601String(),
          'note': auditTxStore2.note,
          'importPrice': auditTxStore2.importPrice,
          'createdBy': auditTxStore2.createdBy,
          'createdByName': auditTxStore2.createdByName,
        });
        expect(modelAudit.toTransactionType(), TransactionType.inventoryAudit);
      });

      test('Dynamic store alias resolution handles case, accents, and fallback gracefully', () {
        const product = Product(
          id: 'prod_alias_test',
          name: 'Sữa tươi Dalat Milk 450ml',
          code: 'DLM450',
          price: 25000,
          costPrice: 18000,
          branchStocks: {
            'branch_1': 42,
            'branch_2': 17,
            'store_003': 8,
          },
          category: 'Đồ uống & Giải khát',
        );

        // Store 1 aliases
        expect(product.stockInBranch('store_001'), 42);
        expect(product.stockInBranch('branch_1'), 42);
        expect(product.stockInBranch('ĐT'), 42);
        expect(product.stockInBranch('dt'), 42);
        expect(product.stockInBranch('Đông Thắng'), 42);
        expect(product.stockInBranch('dong thang'), 42);

        // Store 2 aliases
        expect(product.stockInBranch('store_002'), 17);
        expect(product.stockInBranch('branch_2'), 17);
        expect(product.stockInBranch('TB'), 17);
        expect(product.stockInBranch('tb'), 17);
        expect(product.stockInBranch('Thới Bình'), 17);
        expect(product.stockInBranch('thoi binh'), 17);
        expect(product.stockInBranch('thời bình'), 17);

        // Dynamic 3rd store
        expect(product.stockInBranch('store_003'), 8);
        expect(product.stockInBranch('STORE_003'), 8);

        // Unknown branches return 0 safely
        expect(product.stockInBranch('unknown_branch'), 0);
        expect(product.stockInBranch(''), 0);
        expect(product.stockInBranch('   '), 0);
      });

      test('Backward compatibility: legacy single stock field migration in ProductModel', () {
        final legacyMap = {
          'id': 'legacy_prod_99',
          'name': 'Gạo ST25 Ông Cua 5kg',
          'code': 'ST25',
          'price': 180000,
          'stock': 77, // Legacy field
          'category': 'Gạo & Ngũ cốc',
        };

        final productModel = ProductModel.fromMap(legacyMap);
        expect(productModel.branchStocks['store_001'], 77);
        expect(productModel.branchStocks['store_002'], 0);
        expect(productModel.allowSale, true); // Default to true
      });
    });

    // =========================================================================
    // AXIS 2: POS Filtering, Active Switch & Cart Protection Stress Tests
    // =========================================================================
    group('Axis 2: POS Filtering, Active Switch & Cart Protection', () {
      test('Active for sale toggle disables POS availability and CartNotifier rejects addition', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        const activeProduct = Product(
          id: 'prod_active',
          name: 'Bánh gạo One One phô mai bắp',
          code: 'ONEONE01',
          price: 32000,
          costPrice: 20000,
          branchStocks: {'branch_1': 100},
          category: 'Bánh kẹo & Đồ ăn vặt',
          allowSale: true,
        );

        const disabledProduct = Product(
          id: 'prod_disabled',
          name: 'Bánh phồng tôm Sa Giang cay đặc biệt',
          code: 'SAGIANG01',
          price: 28000,
          costPrice: 16000,
          branchStocks: {'branch_1': 50},
          category: 'Bánh kẹo & Đồ ăn vặt',
          allowSale: false,
        );

        final cartNotifier = container.read(cartProvider.notifier);

        // 1. Programmatic addition of active product must succeed
        cartNotifier.addToCart(activeProduct);
        expect(container.read(cartProvider).containsKey(activeProduct.id), isTrue);
        expect(container.read(cartProvider)[activeProduct.id]!.quantity, 1);
        expect(container.read(cartTotalItemsProvider), 1);
        expect(container.read(cartTotalAmountProvider), 32000);

        // 2. Programmatic addition of disabled product must be REJECTED immediately
        cartNotifier.addToCart(disabledProduct);
        expect(container.read(cartProvider).containsKey(disabledProduct.id), isFalse);
        expect(container.read(cartTotalItemsProvider), 1); // Remains 1
        expect(container.read(cartTotalAmountProvider), 32000); // Remains 32,000

        // 3. Multi-add attempt on disabled product
        for (int i = 0; i < 5; i++) {
          cartNotifier.addToCart(disabledProduct);
        }
        expect(container.read(cartProvider).containsKey(disabledProduct.id), isFalse);
        expect(container.read(cartTotalItemsProvider), 1);

        // 4. POS Catalog Filter verification: simulate POS listing query
        final allProducts = [activeProduct, disabledProduct];
        final posAvailableProducts = allProducts.where((p) => p.allowSale).toList();
        expect(posAvailableProducts.length, 1);
        expect(posAvailableProducts.first.id, activeProduct.id);

        // 5. If product is re-enabled, POS catalog and CartNotifier allow it
        final reEnabledProduct = disabledProduct.copyWith(allowSale: true);
        final updatedCatalog = [activeProduct, reEnabledProduct].where((p) => p.allowSale).toList();
        expect(updatedCatalog.length, 2);

        cartNotifier.addToCart(reEnabledProduct);
        expect(container.read(cartProvider).containsKey(reEnabledProduct.id), isTrue);
        expect(container.read(cartTotalItemsProvider), 2);
        expect(container.read(cartTotalAmountProvider), 32000 + 28000);
      });

      test('RBAC permission logic for active switch modification', () {
        const adminUser = UserAccount(
          username: 'admin',
          displayName: 'Tổng Quản Lý',
          role: 'admin',
          storeId: 'store_001',
        );

        const supervisorUser = UserAccount(
          username: 'supervisor',
          displayName: 'Giám Sát Vùng',
          role: 'supervisor',
          storeId: 'store_001',
        );

        const staffUser = UserAccount(
          username: 'staff',
          displayName: 'Nhân Viên Thu Ngân',
          role: 'nhanvien',
          storeId: 'store_001',
        );

        expect(adminUser.canManageProducts, isTrue);
        expect(supervisorUser.canManageProducts, isTrue);
        expect(staffUser.canManageProducts, isFalse);
      });

      test('Cart operations (custom price, multi-unit populate, clear) integrity', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        const productA = Product(
          id: 'prod_a',
          name: 'Trà ô long Tea+ Plus 455ml',
          code: 'TEAPLUS',
          price: 11000,
          costPrice: 7500,
          branchStocks: {'branch_1': 200},
          category: 'Đồ uống & Giải khát',
          allowSale: true,
        );

        final cartNotifier = container.read(cartProvider.notifier);
        cartNotifier.addToCart(productA);
        cartNotifier.increaseQuantity(productA.id);
        expect(container.read(cartProvider)[productA.id]!.quantity, 2);
        expect(container.read(cartTotalAmountProvider), 22000);

        // Update custom price
        cartNotifier.updatePrice(productA.id, 10000);
        expect(container.read(cartProvider)[productA.id]!.price, 10000);
        expect(container.read(cartTotalAmountProvider), 20000);

        // Decrease quantity to 1 then to 0 (auto-removal)
        cartNotifier.decreaseQuantity(productA.id);
        expect(container.read(cartProvider)[productA.id]!.quantity, 1);
        cartNotifier.decreaseQuantity(productA.id);
        expect(container.read(cartProvider).containsKey(productA.id), isFalse);
        expect(container.read(cartTotalItemsProvider), 0);
      });
    });

    // =========================================================================
    // AXIS 3: Vietnamese NLP & Multi-Industry Sample Images Stress Tests
    // =========================================================================
    group('Axis 3: Vietnamese NLP & Sample Image Matching Edge Cases', () {
      test('VietnameseTextHelper diacritics stripping under all uppercase, lowercase, and mixed accents', () {
        // Uppercase full diacritic inventory (17 A's, 1 D, 11 E's, 5 I's, 17 O's, 11 U's, 5 Y's)
        const rawUpper = 'ÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬĐÈÉẺẼẸÊỀẾỂỄỆÌÍỈĨỊÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢÙÚỦŨỤƯỪỨỬỮỰỲÝỶỸỴ';
        final expected = '${'a' * 17}d${'e' * 11}${'i' * 5}${'o' * 17}${'u' * 11}${'y' * 5}';
        expect(VietnameseTextHelper.normalizeUnaccented(rawUpper), expected);

        // Word boundary matching
        expect(VietnameseTextHelper.containsWord('BÁNH TRÁNG TRỘN TÂY NINH', 'bánh tráng'), isTrue);
        expect(VietnameseTextHelper.containsPhrase('BÁNH TRÁNG TRỘN TÂY NINH', 'bánh tráng'), isTrue);
        expect(VietnameseTextHelper.containsPhrase('BÁNH TRÁNG TRỘN TÂY NINH', 'BÁNH TRÁNG'), isTrue);
        expect(VietnameseTextHelper.containsPhrase('banh trang tron tay ninh', 'BÁNH TRÁNG', unaccented: true), isTrue);

        // False positive prevention
        expect(VietnameseTextHelper.containsWord('khăn giấy ướt', 'ăn'), isFalse);
        expect(VietnameseTextHelper.containsWord('báo cáo doanh thu', 'áo'), isFalse);
        expect(VietnameseTextHelper.containsWord('cái kéo', 'kẹo'), isFalse);
        expect(VietnameseTextHelper.containsWord('hạt nêm Knorr', 'nêm'), isTrue);
      });

      test('Smart Sample Image Matcher: Accented & Unaccented Retail Items Across 12 Industries', () {
        final testCases = <Map<String, String>>[
          // FMCG & Beverages
          {'name': 'NƯỚC NGỌT COCA COLA CHAI 1.5L', 'expectedCategory': 'Nước ngọt có ga & Nước tăng lực'},
          {'name': 'Nuoc tang luc Redbull lon 250ml', 'expectedCategory': 'Nước ngọt có ga & Nước tăng lực'},
          {'name': 'Bia Heineken Silver lon cao 330ml', 'expectedCategory': 'Bia & Thức uống có cồn'},
          {'name': 'BIA SAIGON SPECIAL LON 330ML', 'expectedCategory': 'Bia & Thức uống có cồn'},
          {'name': 'Sữa tươi tiệt trùng Vinamilk ít đường 1L', 'expectedCategory': 'Sữa tươi & Sữa các loại'},
          {'name': 'Cà phê hòa tan G7 3in1 hộp 18 gói', 'expectedCategory': 'Cà phê & Bột cà phê'},
          {'name': 'Tra xanh Khong Do chai 500ml', 'expectedCategory': 'Trà & Trà sữa'},
          {'name': 'Nước khoáng thiên nhiên Lavie 500ml', 'expectedCategory': 'Nước suối & Nước tinh khiết'},
          {'name': 'Nuoc suoi Aquafina 1.5L', 'expectedCategory': 'Nước suối & Nước tinh khiết'},

          // Confectionery & Snacks
          {'name': 'Bánh quy bơ Danisa hộp thiếc 454g', 'expectedCategory': 'Bánh quy, Bánh ngọt & Snack'},
          {'name': 'Banh Oreo socola kem vani', 'expectedCategory': 'Bánh quy, Bánh ngọt & Snack'},
          {'name': 'Kẹo dẻo Chupa Chups cầu vồng', 'expectedCategory': 'Kẹo & Sô-cô-la'},

          // Grocery & Condiments
          {'name': 'Gạo ST25 đặc sản Sóc Trăng 5kg', 'expectedCategory': 'Gạo, Ngũ cốc & Hạt dinh dưỡng'},
          {'name': 'Mì Hảo Hảo tôm chua cay gói 75g', 'expectedCategory': 'Mì gói, Bún & Phở ăn liền'},
          {'name': 'Mi Omachi xot bo ham', 'expectedCategory': 'Mì gói, Bún & Phở ăn liền'},
          {'name': 'Nước mắm Nam Ngư Đệ Nhị 900ml', 'expectedCategory': 'Dầu ăn, Nước mắm & Gia vị'},
          {'name': 'Dau an Tuong An Cooking Oil 1L', 'expectedCategory': 'Dầu ăn, Nước mắm & Gia vị'},

          // Personal Care & Cosmetics
          {'name': 'Dầu gội Clear Men bạc hà sạch gàu 650g', 'expectedCategory': 'Dầu gội, Sữa tắm & Xà bông'},
          {'name': 'Sữa tắm Lifebuoy bảo vệ vượt trội 850g', 'expectedCategory': 'Dầu gội, Sữa tắm & Xà bông'},
          {'name': 'Kem đánh răng Colgate Total 150g', 'expectedCategory': 'Kem đánh răng & Chăm sóc răng miệng'},
          {'name': 'Son môi MAC Matte Lipstick', 'expectedCategory': 'Son môi & Trang điểm môi'},
          {'name': 'Kem chống nắng Anessa Perfect UV 60ml', 'expectedCategory': 'Skincare & Dưỡng da'},

          // Fashion & Apparel
          {'name': 'Áo thun nam polo cotton co giãn', 'expectedCategory': 'Áo thun, Sơ mi & Áo polo'},
          {'name': 'Quan jean nu ong rong', 'expectedCategory': 'Quần jean, Kaki & Quần tây'},
          {'name': 'Giày thể thao sneaker nam đế êm', 'expectedCategory': 'Giày sneaker & Thể thao'},

          // Tech & Electronics
          {'name': 'Điện thoại iPhone 15 Pro 128GB', 'expectedCategory': 'Apple iPhone'},
          {'name': 'Dien thoai Samsung Galaxy S24 Ultra', 'expectedCategory': 'Android Smartphone'},
          {'name': 'Laptop Dell Inspiron 15 Core i5', 'expectedCategory': 'Laptop & MacBook'},
          {'name': 'Chuột không dây Logitech M331 Silent', 'expectedCategory': 'Bàn phím & Chuột máy tính'},
          {'name': 'Tai nghe Bluetooth không dây Sony', 'expectedCategory': 'Tai nghe & AirPods'},

          // Home & Cleaning
          {'name': 'Nước giặt OMO Matic cửa trước 3.6kg', 'expectedCategory': 'Nước giặt, Bột giặt & Nước xả'},
          {'name': 'Nuoc rua chen Sunlight chanh 750g', 'expectedCategory': 'Nước rửa chén, Lau sàn & Tẩy rửa'},
          {'name': 'Khăn giấy lụa Paseo 3 lớp 200 tờ', 'expectedCategory': 'Khăn giấy & Giấy vệ sinh'},
        ];

        for (final tc in testCases) {
          final prod = Product(
            id: 'test_${tc['name'].hashCode}',
            name: tc['name']!,
            code: 'T01',
            price: 10000,
            costPrice: 5000,
            branchStocks: const {'branch_1': 10},
            category: 'Khác',
          );

          final matches = SampleImageHelper.getSuggestedImages(prod);
          expect(matches.isNotEmpty, isTrue, reason: 'Failed to match for ${tc['name']}');
          expect(matches.first.name, tc['expectedCategory'],
              reason: 'Product "${tc['name']}" expected category "${tc['expectedCategory']}" but got "${matches.first.name}"');
        }
      });

      test('Negative keyword exclusion & collision avoidance stress test', () {
        // 1. Phone Case vs Phone
        const phoneCase = Product(
          id: 'c1',
          name: 'Ốp lưng iPhone 15 Pro Max Silicon chống sốc',
          code: 'CASE01',
          price: 90000,
          costPrice: 30000,
          branchStocks: {'branch_1': 10},
          category: 'Phụ kiện',
        );
        final caseMatches = SampleImageHelper.getSuggestedImages(phoneCase);
        expect(caseMatches.first.name, 'Ốp lưng & Kính cường lực');
        expect(caseMatches.first.name, isNot('Apple iPhone'));

        // 2. Tablet Case vs Tablet
        const tabletCase = Product(
          id: 'c2',
          name: 'Bao da iPad Pro M2 11 inch kèm khe cắm bút',
          code: 'IPADCASE01',
          price: 250000,
          costPrice: 120000,
          branchStocks: {'branch_1': 10},
          category: 'Phụ kiện',
        );
        final tabCaseMatches = SampleImageHelper.getSuggestedImages(tabletCase);
        expect(tabCaseMatches.first.name, 'Ốp lưng & Kính cường lực');

        // 3. Laptop Sleeve / Bag vs Laptop
        const laptopBag = Product(
          id: 'c3',
          name: 'Túi chống sốc MacBook Pro 14 inch chống nước',
          code: 'BAG01',
          price: 350000,
          costPrice: 180000,
          branchStocks: {'branch_1': 10},
          category: 'Phụ kiện',
        );
        final bagMatches = SampleImageHelper.getSuggestedImages(laptopBag);
        expect(bagMatches.first.name, 'Balo & Vali du lịch');
        expect(bagMatches.first.name, isNot('Laptop & MacBook'));

        // 4. Body Wash vs Milk Beverage
        const bodyWash = Product(
          id: 'c4',
          name: 'Sữa tắm trắng da Hazeline lựu đỏ matcha 900g',
          code: 'HAZ01',
          price: 115000,
          costPrice: 85000,
          branchStocks: {'branch_1': 10},
          category: 'Mỹ phẩm',
        );
        final bodyWashMatches = SampleImageHelper.getSuggestedImages(bodyWash);
        expect(bodyWashMatches.first.name, 'Dầu gội, Sữa tắm & Xà bông');
        expect(bodyWashMatches.first.name, isNot('Sữa tươi & Sữa các loại'));

        // 5. Facial Cleanser vs Milk Beverage
        const cleanser = Product(
          id: 'c5',
          name: 'Sữa rửa mặt Simple Kind to Skin Refreshing Facial Wash 150ml',
          code: 'SIMPLE01',
          price: 130000,
          costPrice: 95000,
          branchStocks: {'branch_1': 10},
          category: 'Mỹ phẩm',
        );
        final cleanserMatches = SampleImageHelper.getSuggestedImages(cleanser);
        expect(cleanserMatches.first.name, 'Skincare & Dưỡng da');
        expect(cleanserMatches.first.name, isNot('Sữa tươi & Sữa các loại'));

        // 6. Medicating Oil vs Cooking Oil
        const medicatingOil = Product(
          id: 'c6',
          name: 'Dầu gió xanh Con Ó Eagle Brand 24ml Singapore',
          code: 'CONO01',
          price: 120000,
          costPrice: 90000,
          branchStocks: {'branch_1': 10},
          category: 'Dược phẩm',
        );
        final oilMatches = SampleImageHelper.getSuggestedImages(medicatingOil);
        expect(oilMatches.first.name, 'Thuốc OTC & Cồn y tế');
        expect(oilMatches.first.name, isNot('Dầu ăn, Nước mắm & Gia vị'));
      });

      test('Resilient fallbacks on empty, noise, and gibberish queries', () {
        const emptyProd = Product(
          id: 'f1',
          name: '',
          code: 'E01',
          price: 0,
          costPrice: 0,
          branchStocks: {},
          category: '',
        );
        expect(SampleImageHelper.getSampleImageUrl(emptyProd), SampleImageHelper.universalPlaceholderUrl);

        const noiseProd = Product(
          id: 'f2',
          name: '###@@@\$\$\$ 123456789 !!!???',
          code: 'N01',
          price: 0,
          costPrice: 0,
          branchStocks: {},
          category: '',
        );
        expect(SampleImageHelper.getSampleImageUrl(noiseProd), SampleImageHelper.universalPlaceholderUrl);

        expect(SampleImageHelper.getSampleImageUrlForText('   '), SampleImageHelper.universalPlaceholderUrl);
      });
    });

    // =========================================================================
    // AXIS 4: FIFO + Direct Stock Balance + Multi-Day Revenue Stress Tests
    // =========================================================================
    group('Axis 4: FIFO Lot Tracking, Direct Stock Balance & Multi-Day Revenue', () {
      test('End-to-end multi-day lifecycle with mixed imports, positive audits, negative audits, and sales', () {
        final fifo = FifoCalculator();
        const productId = 'prod_fifo_stress_100';

        // Timeline:
        // Day 1 (Aug 1, 09:00): Import Lot 1 -> 10 units @ 10,000 đ
        final d1Import1 = InventoryTransaction(
          id: 'tx_d1_imp1',
          productId: productId,
          type: TransactionType.import,
          quantity: 10,
          date: DateTime(2026, 8, 1, 9, 0),
          note: 'Nhập hàng lô 1',
          importPrice: 10000,
        );

        // Day 1 (Aug 1, 14:00): Import Lot 2 -> 20 units @ 12,000 đ
        final d1Import2 = InventoryTransaction(
          id: 'tx_d1_imp2',
          productId: productId,
          type: TransactionType.import,
          quantity: 20,
          date: DateTime(2026, 8, 1, 14, 0),
          note: 'Nhập hàng lô 2',
          importPrice: 12000,
        );

        // Initialize FIFO with Day 1 imports
        fifo.initializeInventoryTracker([d1Import1, d1Import2]);
        var lots = fifo.getInventoryLots(productId);
        expect(lots.length, 2);
        expect(lots[0].remainingQuantity, 10);
        expect(lots[0].importPrice, 10000);
        expect(lots[1].remainingQuantity, 20);
        expect(lots[1].importPrice, 12000);

        // Day 2 (Aug 2, 11:00): Sale 1 -> 15 units sold @ 20,000 đ
        // FIFO must consume 10 units @ 10,000 (Lot 1) + 5 units @ 12,000 (Lot 2) = COGS 160,000
        final d2SaleCost = fifo.calculateCostForSale(
          productId: productId,
          quantity: 15,
          saleDate: DateTime(2026, 8, 2, 11, 0),
          fallbackCostPrice: 12000,
        );
        expect(d2SaleCost, (10 * 10000) + (5 * 12000)); // 160,000 đ
        const d2Revenue = 15 * 20000.0; // 300,000 đ
        final d2Profit = d2Revenue - d2SaleCost; // 140,000 đ
        final d2ProfitMargin = FifoCalculator.calculateProfitMargin(d2Revenue, d2SaleCost);
        expect(d2Profit, 140000.0);
        expect(d2ProfitMargin, closeTo((140000 / 300000) * 100, 0.01));

        lots = fifo.getInventoryLots(productId);
        expect(lots[0].remainingQuantity, 0); // Lot 1 exhausted
        expect(lots[1].remainingQuantity, 15); // Lot 2 has 15 left

        // Day 3 (Aug 3, 08:30): Direct Stock Balance (Positive Audit +10 units @ 15,000 đ)
        // Store manager finds 10 extra units and updates stock (+10)
        final d3PositiveAudit = InventoryTransaction(
          id: 'tx_d3_audit_pos',
          productId: productId,
          type: TransactionType.inventoryAudit,
          quantity: 10,
          date: DateTime(2026, 8, 3, 8, 30),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 15 -> Tồn mới: 25, chênh lệch: +10)',
          importPrice: 15000,
        );

        // Re-initialize FIFO tracker with full transaction history up to Day 3
        fifo.initializeInventoryTracker([d1Import1, d1Import2, d3PositiveAudit]);
        lots = fifo.getInventoryLots(productId);
        expect(lots.length, 3);
        expect(lots[0].remainingQuantity, 10);
        expect(lots[1].remainingQuantity, 20);
        expect(lots[2].remainingQuantity, 10);
        expect(lots[2].importPrice, 15000);

        // Replay Day 2 sale
        final replayedD2Cost = fifo.calculateCostForSale(
          productId: productId,
          quantity: 15,
          saleDate: DateTime(2026, 8, 2, 11, 0),
        );
        expect(replayedD2Cost, 160000.0);
        expect(lots[0].remainingQuantity, 0);
        expect(lots[1].remainingQuantity, 15);
        expect(lots[2].remainingQuantity, 10);

        // Day 4 (Aug 4, 16:00): Direct Stock Balance (Negative Audit -5 units)
        final d4NegativeAudit = InventoryTransaction(
          id: 'tx_d4_audit_neg',
          productId: productId,
          type: TransactionType.inventoryAudit,
          quantity: 5,
          date: DateTime(2026, 8, 4, 16, 0),
          note: 'Cân bằng kho trực tiếp (Tồn cũ: 25 -> Tồn mới: 20, chênh lệch: -5)',
          importPrice: 15000,
        );

        // Re-init with all 4 transactions
        fifo.initializeInventoryTracker([d1Import1, d1Import2, d3PositiveAudit, d4NegativeAudit]);
        // Day 5 (Aug 5): Sale of 15 units sold @ 25,000 đ
        final d5SaleCost = fifo.calculateCostForSale(
          productId: productId,
          quantity: 15,
          saleDate: DateTime(2026, 8, 5, 10, 0),
          fallbackCostPrice: 15000,
        );
        // Consumes 5 @ 10,000 (Lot 1) + 10 @ 12,000 (Lot 2) = 170,000 đ
        expect(d5SaleCost, (5 * 10000) + (10 * 12000));
        const d5Revenue = 15 * 25000.0; // 375,000 đ
        final d5Profit = d5Revenue - d5SaleCost; // 205,000 đ
        expect(d5Profit, 205000.0);

        // Day 6: Overselling scenario (Selling 25 units when only 10 from Lot 2 + 10 from Lot 3 = 20 left)
        final d6SaleCost = fifo.calculateCostForSale(
          productId: productId,
          quantity: 25,
          saleDate: DateTime(2026, 8, 6, 12, 0),
          fallbackCostPrice: 16000,
        );
        // Consumes remaining: 10 @ 12,000 (Lot 2) + 10 @ 15,000 (Lot 3) + 5 @ 16,000 (fallback) = 120,000 + 150,000 + 80,000 = 350,000
        expect(d6SaleCost, (10 * 12000) + (10 * 15000) + (5 * 16000));
      });

      test('Multi-product FIFO calculator isolation prevents cross-product lot contamination', () {
        final fifo = FifoCalculator();

        final txA = InventoryTransaction(
          id: 'tx_a',
          productId: 'prod_alpha',
          type: TransactionType.import,
          quantity: 100,
          date: DateTime(2026, 8, 1),
          note: 'Product Alpha Import',
          importPrice: 50000,
        );

        final txB = InventoryTransaction(
          id: 'tx_b',
          productId: 'prod_beta',
          type: TransactionType.import,
          quantity: 50,
          date: DateTime(2026, 8, 1),
          note: 'Product Beta Import',
          importPrice: 10000,
        );

        fifo.initializeInventoryTracker([txA, txB]);

        // Sale of Alpha must NOT deplete Beta
        final costAlpha = fifo.calculateCostForSale(
          productId: 'prod_alpha',
          quantity: 30,
          saleDate: DateTime(2026, 8, 2),
        );
        expect(costAlpha, 30 * 50000.0);

        final lotsAlpha = fifo.getInventoryLots('prod_alpha');
        final lotsBeta = fifo.getInventoryLots('prod_beta');

        expect(lotsAlpha.first.remainingQuantity, 70);
        expect(lotsBeta.first.remainingQuantity, 50); // Unchanged

        // Non-existent product sale uses fallback cost safely
        final costGamma = fifo.calculateCostForSale(
          productId: 'prod_gamma',
          quantity: 10,
          saleDate: DateTime(2026, 8, 2),
          fallbackCostPrice: 25000,
        );
        expect(costGamma, 10 * 25000.0);

        // Zero quantity sale returns 0.0
        expect(
          fifo.calculateCostForSale(productId: 'prod_alpha', quantity: 0, saleDate: DateTime(2026, 8, 2)),
          0.0,
        );
        expect(
          fifo.calculateCostForSale(productId: 'prod_alpha', quantity: -5, saleDate: DateTime(2026, 8, 2)),
          0.0,
        );
      });
    });
  });
}
