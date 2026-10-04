import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/domain/entities/product.dart';

void main() {
  const productA = Product(
    id: 'prod_1',
    name: 'Cà phê Robusta',
    code: 'CF01',
    price: 35000,
    costPrice: 20000,
    branchStocks: {'store_001': 10},
    category: 'Coffee',
    allowSale: true,
  );

  const productB = Product(
    id: 'prod_2',
    name: 'Trà sen vàng',
    code: 'TSV01',
    price: 45000,
    costPrice: 25000,
    branchStocks: {'store_001': 15},
    category: 'Tea',
    allowSale: true,
  );

  group('CartItem Undo / Restore Item Tests', () {
    setUp(() {
      MultiCartNotifier.resetBranchCartsCache();
    });
    test('MultiCartNotifier removes item and recalculates totalItems & totalAmount', () {
      final multiNotifier = MultiCartNotifier();
      multiNotifier.addToCart(productA, quantity: 2);
      multiNotifier.addToCart(productB, quantity: 1);

      expect(multiNotifier.state.activeTab.totalItems, 3);
      expect(multiNotifier.state.activeTab.totalAmount, 70000 + 45000);

      multiNotifier.removeFromCart(productA.id);

      expect(multiNotifier.state.activeTab.items.containsKey(productA.id), false);
      expect(multiNotifier.state.activeTab.totalItems, 1);
      expect(multiNotifier.state.activeTab.totalAmount, 45000);
    });

    test('MultiCartNotifier restores removed item with full quantity, discount, and note', () {
      final multiNotifier = MultiCartNotifier();
      multiNotifier.addToCart(productA, quantity: 3);
      multiNotifier.updateItemDetails(
        productA.id,
        discount: 5000,
        isDiscountPercent: false,
        note: 'Ít đường nhiều đá',
      );

      final originalItem = multiNotifier.state.activeTab.items[productA.id]!;
      expect(originalItem.quantity, 3);
      expect(originalItem.discount, 5000);
      expect(originalItem.note, 'Ít đường nhiều đá');
      expect(originalItem.effectivePrice, 30000);
      expect(originalItem.total, 90000);

      // Remove from cart
      multiNotifier.removeFromCart(productA.id);
      expect(multiNotifier.state.activeTab.items.containsKey(productA.id), false);
      expect(multiNotifier.state.activeTab.totalAmount, 0.0);

      // Restore via Undo
      multiNotifier.restoreCartItem(originalItem);
      expect(multiNotifier.state.activeTab.items.containsKey(productA.id), true);

      final restoredItem = multiNotifier.state.activeTab.items[productA.id]!;
      expect(restoredItem.product.id, productA.id);
      expect(restoredItem.quantity, 3);
      expect(restoredItem.discount, 5000);
      expect(restoredItem.note, 'Ít đường nhiều đá');
      expect(restoredItem.total, 90000);
      expect(multiNotifier.state.activeTab.totalAmount, 90000);
      expect(multiNotifier.state.activeTab.totalItems, 3);
    });

    test('CartNotifier standalone restores removed item with identical properties', () {
      final cartNotifier = CartNotifier();
      cartNotifier.addToCart(productA, quantity: 2);
      final item = cartNotifier.state[productA.id]!;

      cartNotifier.removeFromCart(productA.id);
      expect(cartNotifier.state.isEmpty, true);

      cartNotifier.restoreCartItem(item);
      expect(cartNotifier.state.containsKey(productA.id), true);
      expect(cartNotifier.state[productA.id]!.quantity, 2);
      expect(cartNotifier.state[productA.id]!.product.name, 'Cà phê Robusta');
    });

    test('MultiCartNotifier restores removed item to designated tabId even after active tab switches', () {
      final multiNotifier = MultiCartNotifier();
      final tab1Id = multiNotifier.state.activeTabId;

      multiNotifier.addToCart(productA, quantity: 2);
      final itemA = multiNotifier.state.activeTab.items[productA.id]!;

      // Add a second tab
      multiNotifier.addNewTab(title: 'Hóa đơn 2');
      final tab2Id = multiNotifier.state.activeTabId;
      expect(tab1Id != tab2Id, true);

      // Switch back to tab 1 and delete itemA
      multiNotifier.switchTab(tab1Id);
      multiNotifier.removeFromCart(productA.id);
      expect(multiNotifier.state.tabs.firstWhere((t) => t.id == tab1Id).items.isEmpty, true);

      // Now user switches to tab 2
      multiNotifier.switchTab(tab2Id);
      expect(multiNotifier.state.activeTabId, tab2Id);

      // Undo occurs while active on tab 2, targeting tab1Id
      multiNotifier.restoreCartItem(itemA, tabId: tab1Id);

      // Tab 1 has itemA restored
      final tab1 = multiNotifier.state.tabs.firstWhere((t) => t.id == tab1Id);
      expect(tab1.items.containsKey(productA.id), true);
      expect(tab1.items[productA.id]!.quantity, 2);

      // Tab 2 remains unaffected
      final tab2 = multiNotifier.state.tabs.firstWhere((t) => t.id == tab2Id);
      expect(tab2.items.containsKey(productA.id), false);
    });

    test('MultiCartNotifier falls back to active tab if target tab was closed', () {
      final multiNotifier = MultiCartNotifier();
      final tab1Id = multiNotifier.state.activeTabId;
      multiNotifier.addToCart(productA, quantity: 1);
      final itemA = multiNotifier.state.activeTab.items[productA.id]!;

      multiNotifier.addNewTab(title: 'Hóa đơn 2');
      final tab2Id = multiNotifier.state.activeTabId;

      // Close tab 1
      multiNotifier.closeTab(tab1Id);
      expect(multiNotifier.state.tabs.any((t) => t.id == tab1Id), false);
      expect(multiNotifier.state.activeTabId, tab2Id);

      // Restoring with defunct tab1Id should safely restore to active tab (tab2)
      multiNotifier.restoreCartItem(itemA, tabId: tab1Id);
      final activeTab = multiNotifier.state.activeTab;
      expect(activeTab.items.containsKey(productA.id), true);
      expect(activeTab.items[productA.id]!.quantity, 1);
    });
  });
}
