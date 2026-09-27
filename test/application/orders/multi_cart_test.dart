import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';

void main() {
  setUp(() {
    MultiCartNotifier.resetBranchCartsCache();
  });

  tearDown(() {
    MultiCartNotifier.resetBranchCartsCache();
  });

  group('CartTab & MultiCartState Domain Model Tests', () {
    const productA = Product(
      id: 'p_01',
      name: 'Product A',
      code: 'PA01',
      price: 50000,
      costPrice: 30000,
      branchStocks: {'store_001': 10},
      category: 'Food',
    );

    const productB = Product(
      id: 'p_02',
      name: 'Product B',
      code: 'PB02',
      price: 120000,
      costPrice: 80000,
      branchStocks: {'store_001': 5},
      category: 'Beverage',
    );

    test('CartTab calculates totalItems and totalAmount correctly', () {
      final tab = CartTab(
        id: 'tab_1',
        title: 'Hóa đơn 1',
        items: {
          'p_01': const CartItem(product: productA, quantity: 2), // 100,000
          'p_02': const CartItem(
            product: productB,
            quantity: 1,
            customPrice: 100000,
          ), // 100,000
        },
        createdAt: DateTime.now(),
      );

      expect(tab.totalItems, equals(3));
      expect(tab.totalAmount, equals(200000.0));
    });

    test('CartTab copyWith updates and clears fields accurately', () {
      final now = DateTime.now();
      final tab = CartTab(
        id: 'tab_1',
        title: 'Hóa đơn 1',
        customer: const Customer(
          id: 'c1',
          name: 'Nguyen Van A',
          phone: '0901234567',
          email: 'a@example.com',
          address: 'Can Tho',
          purchases: [],
        ),
        discount: 10.0,
        isDiscountPercent: true,
        note: 'Giao buổi sáng',
        activeOrderId: 'order_123',
        createdAt: now,
      );

      final updated = tab.copyWith(
        title: 'Hóa đơn VIP',
        clearCustomer: true,
        clearActiveOrderId: true,
        note: 'Đã đổi ghi chú',
      );

      expect(updated.title, equals('Hóa đơn VIP'));
      expect(updated.customer, isNull);
      expect(updated.activeOrderId, isNull);
      expect(updated.note, equals('Đã đổi ghi chú'));
      expect(updated.discount, equals(10.0));
      expect(updated.isDiscountPercent, isTrue);
    });

    test('MultiCartState activeTab and activeTabIndex getters handle valid and fallback cases', () {
      final tab1 = CartTab(id: 'tab_1', title: 'Hóa đơn 1', createdAt: DateTime.now());
      final tab2 = CartTab(id: 'tab_2', title: 'Hóa đơn 2', createdAt: DateTime.now());

      final state = MultiCartState(
        tabs: [tab1, tab2],
        activeTabId: 'tab_2',
      );

      expect(state.activeTab.id, equals('tab_2'));
      expect(state.activeTabIndex, equals(1));

      final stateFallback = MultiCartState(
        tabs: [tab1, tab2],
        activeTabId: 'non_existent_tab',
      );
      expect(stateFallback.activeTab.id, equals('tab_1'));
      expect(stateFallback.activeTabIndex, equals(0));
    });
  });

  group('MultiCartNotifier Unit & Tab Management Tests', () {
    const activeProduct = Product(
      id: 'act_01',
      name: 'Bánh gạo',
      code: 'BG01',
      price: 25000,
      costPrice: 15000,
      branchStocks: {'store_001': 20},
      category: 'Food',
      allowSale: true,
    );

    const disabledProduct = Product(
      id: 'dis_01',
      name: 'Sản phẩm ngưng bán',
      code: 'DIS01',
      price: 50000,
      costPrice: 30000,
      branchStocks: {'store_001': 10},
      category: 'Food',
      allowSale: false,
    );

    late MultiCartNotifier multiCartNotifier;

    setUp(() {
      multiCartNotifier = MultiCartNotifier();
    });

    test('Initial state contains 1 default tab titled "Hóa đơn 1"', () {
      expect(multiCartNotifier.state.tabs.length, equals(1));
      expect(multiCartNotifier.state.activeTab.title, equals('Hóa đơn 1'));
      expect(multiCartNotifier.state.activeTab.items, isEmpty);
    });

    test('addNewTab appends a new tab with incremented title and sets it active', () {
      final tab2Id = multiCartNotifier.addNewTab();
      expect(multiCartNotifier.state.tabs.length, equals(2));
      expect(multiCartNotifier.state.activeTabId, equals(tab2Id));
      expect(multiCartNotifier.state.activeTab.title, equals('Hóa đơn 2'));

      final tab3Id = multiCartNotifier.addNewTab();
      expect(multiCartNotifier.state.tabs.length, equals(3));
      expect(multiCartNotifier.state.activeTabId, equals(tab3Id));
      expect(multiCartNotifier.state.activeTab.title, equals('Hóa đơn 3'));
    });

    test('switchTab switches activeTabId between existing tabs', () {
      final tab1Id = multiCartNotifier.state.activeTabId;
      final tab2Id = multiCartNotifier.addNewTab();

      expect(multiCartNotifier.state.activeTabId, equals(tab2Id));
      multiCartNotifier.switchTab(tab1Id);
      expect(multiCartNotifier.state.activeTabId, equals(tab1Id));

      // Switching to invalid tab does nothing
      multiCartNotifier.switchTab('unknown_tab_id');
      expect(multiCartNotifier.state.activeTabId, equals(tab1Id));
    });

    test('Carts maintain independent items and do not bleed into each other', () {
      final tab1Id = multiCartNotifier.state.activeTabId;
      multiCartNotifier.addToCart(activeProduct, quantity: 2);
      expect(multiCartNotifier.state.activeTab.totalItems, equals(2));

      // Create and switch to tab 2
      multiCartNotifier.addNewTab();
      expect(multiCartNotifier.state.activeTab.items, isEmpty);
      expect(multiCartNotifier.state.activeTab.totalItems, equals(0));

      // Tab 1 still holds its 2 items
      final tab1 = multiCartNotifier.state.tabs.firstWhere((t) => t.id == tab1Id);
      expect(tab1.totalItems, equals(2));
      expect(tab1.items['act_01']!.quantity, equals(2));

      // Switch back to tab 1
      multiCartNotifier.switchTab(tab1Id);
      expect(multiCartNotifier.state.activeTab.totalItems, equals(2));
    });

    test('addToCart rejects products with allowSale: false or quantity <= 0', () {
      multiCartNotifier.addToCart(disabledProduct);
      expect(multiCartNotifier.state.activeTab.items, isEmpty);

      multiCartNotifier.addToCart(activeProduct, quantity: 0);
      expect(multiCartNotifier.state.activeTab.items, isEmpty);

      multiCartNotifier.addToCart(activeProduct, quantity: -1);
      expect(multiCartNotifier.state.activeTab.items, isEmpty);
    });

    test('updateQuantity, increaseQuantity, decreaseQuantity, updatePrice and removeFromCart work on active tab', () {
      multiCartNotifier.addToCart(activeProduct, quantity: 1);
      expect(multiCartNotifier.state.activeTab.items['act_01']!.quantity, equals(1));

      multiCartNotifier.increaseQuantity('act_01');
      expect(multiCartNotifier.state.activeTab.items['act_01']!.quantity, equals(2));

      multiCartNotifier.updatePrice('act_01', 30000);
      expect(multiCartNotifier.state.activeTab.items['act_01']!.customPrice, equals(30000));
      expect(multiCartNotifier.state.activeTab.totalAmount, equals(60000));

      multiCartNotifier.decreaseQuantity('act_01');
      expect(multiCartNotifier.state.activeTab.items['act_01']!.quantity, equals(1));

      multiCartNotifier.decreaseQuantity('act_01');
      expect(multiCartNotifier.state.activeTab.items.containsKey('act_01'), isFalse);
      expect(multiCartNotifier.state.activeTab.items, isEmpty);

      // Re-add and test updateQuantity(0) removes
      multiCartNotifier.addToCart(activeProduct, quantity: 5);
      multiCartNotifier.updateQuantity('act_01', 3);
      expect(multiCartNotifier.state.activeTab.items['act_01']!.quantity, equals(3));
      multiCartNotifier.updateQuantity('act_01', 0);
      expect(multiCartNotifier.state.activeTab.items.containsKey('act_01'), isFalse);
    });

    test('clearActiveCart resets active tab metadata and items', () {
      multiCartNotifier.addToCart(activeProduct, quantity: 3);
      multiCartNotifier.setCustomer(const Customer(
        id: 'c1',
        name: 'Test Customer',
        phone: '0909999999',
        email: 'test@example.com',
        address: 'HCM',
        purchases: [],
      ));
      multiCartNotifier.setDiscount(50000, false);
      multiCartNotifier.setNote('Giao gap');
      multiCartNotifier.setActiveOrderId('order_draft_1');

      expect(multiCartNotifier.state.activeTab.totalItems, equals(3));
      expect(multiCartNotifier.state.activeTab.customer, isNotNull);
      expect(multiCartNotifier.state.activeTab.discount, equals(50000));
      expect(multiCartNotifier.state.activeTab.note, equals('Giao gap'));
      expect(multiCartNotifier.state.activeTab.activeOrderId, equals('order_draft_1'));

      multiCartNotifier.clearActiveCart();

      expect(multiCartNotifier.state.activeTab.items, isEmpty);
      expect(multiCartNotifier.state.activeTab.customer, isNull);
      expect(multiCartNotifier.state.activeTab.discount, equals(0.0));
      expect(multiCartNotifier.state.activeTab.note, isEmpty);
      expect(multiCartNotifier.state.activeTab.activeOrderId, isNull);
    });

    test('closeTab handles neighbor selection and recreation when last tab is closed', () {
      final tab1Id = multiCartNotifier.state.activeTabId;
      final tab2Id = multiCartNotifier.addNewTab();
      final tab3Id = multiCartNotifier.addNewTab();

      expect(multiCartNotifier.state.activeTabId, equals(tab3Id));

      // Close active tab3 -> shifts to neighbor tab2
      multiCartNotifier.closeTab(tab3Id);
      expect(multiCartNotifier.state.tabs.length, equals(2));
      expect(multiCartNotifier.state.activeTabId, equals(tab2Id));

      // Close tab1 (non-active) -> leaves active tab2 as active
      multiCartNotifier.closeTab(tab1Id);
      expect(multiCartNotifier.state.tabs.length, equals(1));
      expect(multiCartNotifier.state.activeTabId, equals(tab2Id));

      // Close the only remaining tab2 -> automatically recreates fresh default tab
      multiCartNotifier.closeTab(tab2Id);
      expect(multiCartNotifier.state.tabs.length, equals(1));
      expect(multiCartNotifier.state.tabs.first.title, equals('Hóa đơn 1'));
      expect(multiCartNotifier.state.activeTabId, equals(multiCartNotifier.state.tabs.first.id));
    });

    test('populateCart restores items and order metadata into active tab', () {
      final items = <OrderItem>[
        OrderItem(
          productId: 'act_01',
          productName: 'Bánh gạo',
          quantity: 4,
          price: 25000,
          warrantyMonths: 0,
          purchaseDate: DateTime.now(),
        ),
      ];
      final allProducts = [activeProduct];

      multiCartNotifier.populateCart(
        items,
        allProducts,
        orderId: 'restored_order_99',
        customer: const Customer(
          id: 'c99',
          name: 'VIP Buyer',
          phone: '0911223344',
          email: 'vip@example.com',
          address: 'Can Tho',
          purchases: [],
        ),
        discount: 15.0,
        isDiscountPercent: true,
        note: 'Don phuc hoi tu lich su',
      );

      final tab = multiCartNotifier.state.activeTab;
      expect(tab.items.length, equals(1));
      expect(tab.items['act_01']!.quantity, equals(4));
      expect(tab.activeOrderId, equals('restored_order_99'));
      expect(tab.customer?.name, equals('VIP Buyer'));
      expect(tab.discount, equals(15.0));
      expect(tab.isDiscountPercent, isTrue);
      expect(tab.note, equals('Don phuc hoi tu lich su'));
    });
  });

  group('Riverpod Provider Backward Compatibility & Multi-Cart Sync Tests', () {
    const sampleProduct = Product(
      id: 'sp_10',
      name: 'Nước suối Aquafina 500ml',
      code: 'AQ500',
      price: 10000,
      costPrice: 5000,
      branchStocks: {'store_001': 50},
      category: 'Drinks',
      allowSale: true,
    );

    test('cartProvider bridges seamlessly with multiCartProvider and updates reactively', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 1. Initially cartProvider is empty map
      expect(container.read(cartProvider), isEmpty);
      expect(container.read(cartTotalItemsProvider), equals(0));
      expect(container.read(cartTotalAmountProvider), equals(0.0));

      // 2. Add item through cartProvider.notifier
      container.read(cartProvider.notifier).addToCart(sampleProduct, quantity: 3);

      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider)['sp_10']!.quantity, equals(3));
      expect(container.read(cartTotalItemsProvider), equals(3));
      expect(container.read(cartTotalAmountProvider), equals(30000.0));

      // 3. multiCartProvider activeTab reflects the exact same items
      final multiState = container.read(multiCartProvider);
      expect(multiState.activeTab.totalItems, equals(3));
      expect(multiState.activeTab.totalAmount, equals(30000.0));

      // 4. Create new tab via multiCartProvider
      container.read(multiCartProvider.notifier).addNewTab();

      // cartProvider now reflects the new active tab (empty)
      expect(container.read(cartProvider), isEmpty);
      expect(container.read(cartTotalItemsProvider), equals(0));
      expect(container.read(cartTotalAmountProvider), equals(0.0));

      // Add 1 item to Tab 2 via multiCartProvider.notifier
      container.read(multiCartProvider.notifier).addToCart(sampleProduct, quantity: 1);
      expect(container.read(cartProvider)['sp_10']!.quantity, equals(1));
      expect(container.read(cartTotalItemsProvider), equals(1));
      expect(container.read(cartTotalAmountProvider), equals(10000.0));

      // Switch back to Tab 1
      container.read(multiCartProvider.notifier).switchTab(multiState.tabs.first.id);
      expect(container.read(cartProvider)['sp_10']!.quantity, equals(3));
      expect(container.read(cartTotalItemsProvider), equals(3));
      expect(container.read(cartTotalAmountProvider), equals(30000.0));
    });

    test('Standalone CartNotifier instance behaves properly for standalone unit tests', () {
      final standaloneNotifier = CartNotifier();
      expect(standaloneNotifier.state, isEmpty);

      standaloneNotifier.addToCart(sampleProduct, quantity: 2);
      expect(standaloneNotifier.state.length, equals(1));
      expect(standaloneNotifier.state['sp_10']!.quantity, equals(2));

      standaloneNotifier.increaseQuantity('sp_10');
      expect(standaloneNotifier.state['sp_10']!.quantity, equals(3));

      standaloneNotifier.decreaseQuantity('sp_10');
      expect(standaloneNotifier.state['sp_10']!.quantity, equals(2));

      standaloneNotifier.updatePrice('sp_10', 12000);
      expect(standaloneNotifier.state['sp_10']!.customPrice, equals(12000));

      standaloneNotifier.clearCart();
      expect(standaloneNotifier.state, isEmpty);
    });
  });
}
