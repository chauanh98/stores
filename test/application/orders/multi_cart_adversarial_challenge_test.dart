import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/orders/widgets/pos_cart_tab_bar.dart';

void main() {
  setUp(() {
    MultiCartNotifier.resetBranchCartsCache();
  });

  tearDown(() {
    MultiCartNotifier.resetBranchCartsCache();
  });

  const sampleProduct1 = Product(
    id: 'prod_adv_01',
    name: 'Sản phẩm thử nghiệm 1',
    code: 'SP01',
    price: 150000,
    costPrice: 90000,
    branchStocks: {'store_001': 100},
    category: 'Test Category',
    allowSale: true,
  );

  const sampleProduct2 = Product(
    id: 'prod_adv_02',
    name: 'Sản phẩm thử nghiệm 2',
    code: 'SP02',
    price: 350000,
    costPrice: 200000,
    branchStocks: {'store_001': 50},
    category: 'Test Category',
    allowSale: true,
  );

  const disabledProduct = Product(
    id: 'prod_adv_disabled',
    name: 'Sản phẩm ngưng kinh doanh',
    code: 'SPDIS',
    price: 200000,
    costPrice: 100000,
    branchStocks: {'store_001': 0},
    category: 'Test Category',
    allowSale: false,
  );

  group('Adversarial Challenge 1: Heavy Scale (10+ Tabs, 100+ Items, Rapid Switching)', () {
    test('Creates 15 tabs, inserts 150 items across tabs, verifies data isolation and totals', () {
      final notifier = MultiCartNotifier();

      // Create 15 tabs
      final tabIds = <String>[notifier.state.activeTabId]; // tab 1
      for (int i = 2; i <= 15; i++) {
        final newId = notifier.addNewTab();
        tabIds.add(newId);
      }
      expect(notifier.state.tabs.length, equals(15));

      // Generate 150 unique mock products and add 10 to each tab
      final allProducts = List.generate(
        150,
        (i) => Product(
          id: 'gen_prod_$i',
          name: 'Generated Product $i',
          code: 'GP$i',
          price: (i + 1) * 10000.0,
          costPrice: (i + 1) * 5000.0,
          branchStocks: {'store_001': 100},
          category: 'HeavyLoad',
          allowSale: true,
        ),
      );

      for (int t = 0; t < 15; t++) {
        notifier.switchTab(tabIds[t]);
        for (int p = 0; p < 10; p++) {
          final product = allProducts[t * 10 + p];
          notifier.addToCart(product, quantity: p + 1);
        }
      }

      // Verify each tab independently
      for (int t = 0; t < 15; t++) {
        notifier.switchTab(tabIds[t]);
        final tab = notifier.state.activeTab;
        expect(tab.id, equals(tabIds[t]));
        expect(tab.items.length, equals(10));

        int expectedItems = 0;
        double expectedAmount = 0.0;
        for (int p = 0; p < 10; p++) {
          final product = allProducts[t * 10 + p];
          final qty = p + 1;
          expectedItems += qty;
          expectedAmount += product.price * qty;
          expect(tab.items[product.id]?.quantity, equals(qty));
        }

        expect(tab.totalItems, equals(expectedItems));
        expect(tab.totalAmount, equals(expectedAmount));
      }

      // Rapidly switch tabs 50 times in pseudo-random order
      final random = Random(42);
      for (int step = 0; step < 50; step++) {
        final targetIndex = random.nextInt(15);
        final targetId = tabIds[targetIndex];
        notifier.switchTab(targetId);
        expect(notifier.state.activeTabId, equals(targetId));
        expect(notifier.state.activeTabIndex, equals(targetIndex));
        expect(notifier.state.activeTab.items.length, equals(10));
      }
    });
  });

  group('Adversarial Challenge 2: Tab Closure Edge Cases & Boundary Conditions', () {
    test('Closing tab when only 1 tab exists resets to a clean default "Hóa đơn 1"', () {
      final notifier = MultiCartNotifier();
      final initialId = notifier.state.activeTabId;

      // Add items and metadata to the single tab
      notifier.addToCart(sampleProduct1, quantity: 5);
      notifier.setCustomer(const Customer(
        id: 'cust_01',
        name: 'John Doe',
        phone: '0987654321',
        email: 'john@example.com',
        address: 'Hanoi',
        purchases: [],
      ));
      notifier.setDiscount(20000, false);
      notifier.setNote('Giao gấp');

      expect(notifier.state.activeTab.totalItems, equals(5));

      // Close the only tab
      notifier.closeTab(initialId);

      // Must have exactly 1 tab, with title "Hóa đơn 1", empty items, no customer, no discount
      expect(notifier.state.tabs.length, equals(1));
      final cleanTab = notifier.state.activeTab;
      expect(cleanTab.title, equals('Hóa đơn 1'));
      expect(cleanTab.items, isEmpty);
      expect(cleanTab.customer, isNull);
      expect(cleanTab.discount, equals(0.0));
      expect(cleanTab.note, isEmpty);
    });

    test('Closing active tab at index 0 switches active tab to the next available tab (new index 0)', () {
      final notifier = MultiCartNotifier();
      final tab1Id = notifier.state.activeTabId;
      final tab2Id = notifier.addNewTab();
      notifier.addNewTab();

      // Switch to tab1 (index 0)
      notifier.switchTab(tab1Id);
      expect(notifier.state.activeTabIndex, equals(0));

      // Close tab1
      notifier.closeTab(tab1Id);

      expect(notifier.state.tabs.length, equals(2));
      expect(notifier.state.activeTabId, equals(tab2Id));
      expect(notifier.state.activeTabIndex, equals(0));
    });

    test('Closing active tab in middle (index 1 of 3) shifts active tab to left neighbor (index 0)', () {
      final notifier = MultiCartNotifier();
      final tab1Id = notifier.state.activeTabId;
      final tab2Id = notifier.addNewTab();
      notifier.addNewTab();

      // Switch to tab2 (middle)
      notifier.switchTab(tab2Id);
      expect(notifier.state.activeTabIndex, equals(1));

      // Close tab2
      notifier.closeTab(tab2Id);

      expect(notifier.state.tabs.length, equals(2));
      expect(notifier.state.activeTabId, equals(tab1Id));
      expect(notifier.state.activeTabIndex, equals(0));
    });

    test('Closing active tab at the end (index 2 of 3) shifts active tab to left neighbor (index 1)', () {
      final notifier = MultiCartNotifier();
      notifier.state.activeTabId;
      final tab2Id = notifier.addNewTab();
      final tab3Id = notifier.addNewTab();

      // active is tab3 (index 2)
      expect(notifier.state.activeTabId, equals(tab3Id));
      expect(notifier.state.activeTabIndex, equals(2));

      // Close tab3
      notifier.closeTab(tab3Id);

      expect(notifier.state.tabs.length, equals(2));
      expect(notifier.state.activeTabId, equals(tab2Id));
      expect(notifier.state.activeTabIndex, equals(1));
    });

    test('Closing non-existent tabId or double closing does not corrupt state or crash', () {
      final notifier = MultiCartNotifier();
      final tab1Id = notifier.state.activeTabId;
      final tab2Id = notifier.addNewTab();

      notifier.closeTab('non_existent_tab_999');
      expect(notifier.state.tabs.length, equals(2));
      expect(notifier.state.activeTabId, equals(tab2Id));

      notifier.closeTab(tab2Id);
      expect(notifier.state.tabs.length, equals(1));
      expect(notifier.state.activeTabId, equals(tab1Id));

      // Double close same id
      notifier.closeTab(tab2Id);
      expect(notifier.state.tabs.length, equals(1));
      expect(notifier.state.activeTabId, equals(tab1Id));
    });

    test('Progressively closing random tabs until empty always preserves valid activeTab', () {
      final notifier = MultiCartNotifier();
      final random = Random(1234);

      // Create 8 tabs
      for (int i = 0; i < 7; i++) {
        notifier.addNewTab();
      }
      expect(notifier.state.tabs.length, equals(8));

      // Close 8 times
      while (notifier.state.tabs.length > 1) {
        final currentTabs = notifier.state.tabs;
        final victim = currentTabs[random.nextInt(currentTabs.length)];
        notifier.closeTab(victim.id);

        // State invariant assertions
        expect(notifier.state.tabs.isNotEmpty, isTrue);
        expect(notifier.state.tabs.any((t) => t.id == notifier.state.activeTabId), isTrue);
        expect(notifier.state.activeTabIndex >= 0, isTrue);
        expect(notifier.state.activeTabIndex < notifier.state.tabs.length, isTrue);
      }

      // Close the last remaining tab
      final lastId = notifier.state.activeTabId;
      notifier.closeTab(lastId);

      expect(notifier.state.tabs.length, equals(1));
      expect(notifier.state.activeTab.title, equals('Hóa đơn 1'));
    });
  });

  group('Adversarial Challenge 3: Tab Auto-Naming & Regex Parser Invariants', () {
    test('Demonstrates ID collision risk when addNewTab is called in same millisecond with same tabNumber', () async {
      final notifier = MultiCartNotifier();
      // Initially: Hóa đơn 1
      expect(notifier.state.tabs.first.title, equals('Hóa đơn 1'));

      final tab2 = notifier.addNewTab(); // Hóa đơn 2
      expect(notifier.state.activeTab.title, equals('Hóa đơn 2'));

      // Rename tab2 to a custom name
      notifier.renameTab(tab2, 'Bàn VIP 8');
      expect(notifier.state.activeTab.title, equals('Bàn VIP 8'));

      // If we wait for next millisecond, timestamp differs so ID collision does not happen
      await Future.delayed(const Duration(milliseconds: 5));

      // Adding next tab: max regex number is 1 ("Hóa đơn 1"), so next is "Hóa đơn 2"
      final tab3 = notifier.addNewTab();
      expect(notifier.state.activeTab.title, equals('Hóa đơn 2'));

      await Future.delayed(const Duration(milliseconds: 5));

      // Rename tab3 to "Hóa đơn 50"
      notifier.renameTab(tab3, 'Hóa đơn 50');
      // Next tab should be "Hóa đơn 51"
      notifier.addNewTab();
      expect(notifier.state.activeTab.title, equals('Hóa đơn 51'));

      // Add tab with explicit title
      notifier.addNewTab(title: 'Đơn mang về');
      expect(notifier.state.activeTab.title, equals('Đơn mang về'));
    });
  });

  group('Adversarial Challenge 4: Stress-testing Rapid Interleaved Mutations & Invariants', () {
    test('Executes 500 chaotic mutations across tabs and verifies zero state corruption', () {
      final notifier = MultiCartNotifier();
      final random = Random(999);

      final products = [
        sampleProduct1,
        sampleProduct2,
        disabledProduct,
        const Product(
          id: 'prod_adv_03',
          name: 'Sản phẩm 3',
          code: 'SP03',
          price: 50000,
          costPrice: 30000,
          branchStocks: {'store_001': 100},
          category: 'Test',
          allowSale: true,
        ),
      ];

      for (int i = 0; i < 500; i++) {
        final action = random.nextInt(12);

        switch (action) {
          case 0: // Add new tab (limit max 10 tabs to keep it realistic)
            if (notifier.state.tabs.length < 10) {
              notifier.addNewTab();
            }
            break;
          case 1: // Switch to random tab
            final tabs = notifier.state.tabs;
            final targetTab = tabs[random.nextInt(tabs.length)];
            notifier.switchTab(targetTab.id);
            break;
          case 2: // Add random product
            final p = products[random.nextInt(products.length)];
            final qty = random.nextInt(5) - 1; // -1 to 3
            notifier.addToCart(p, quantity: qty);
            break;
          case 3: // Increase quantity
            final p = products[random.nextInt(products.length)];
            notifier.increaseQuantity(p.id);
            break;
          case 4: // Decrease quantity
            final p = products[random.nextInt(products.length)];
            notifier.decreaseQuantity(p.id);
            break;
          case 5: // Update quantity
            final p = products[random.nextInt(products.length)];
            final qty = random.nextInt(10) - 2; // -2 to 7
            notifier.updateQuantity(p.id, qty);
            break;
          case 6: // Update price
            final p = products[random.nextInt(products.length)];
            final price = random.nextInt(500000).toDouble();
            notifier.updatePrice(p.id, price);
            break;
          case 7: // Remove product
            final p = products[random.nextInt(products.length)];
            notifier.removeFromCart(p.id);
            break;
          case 8: // Set discount
            notifier.setDiscount(random.nextInt(50).toDouble(), random.nextBool());
            break;
          case 9: // Set note
            notifier.setNote('Note $i');
            break;
          case 10: // Close random tab
            if (notifier.state.tabs.length > 1) {
              final tabs = notifier.state.tabs;
              final targetTab = tabs[random.nextInt(tabs.length)];
              notifier.closeTab(targetTab.id);
            }
            break;
          case 11: // Clear active cart
            notifier.clearActiveCart();
            break;
        }

        // INVARIANT CHECKS AT EVERY ITERATION
        final state = notifier.state;
        expect(state.tabs.isNotEmpty, isTrue, reason: 'Iteration $i: tabs cannot be empty');
        expect(state.tabs.any((t) => t.id == state.activeTabId), isTrue,
            reason: 'Iteration $i: activeTabId must exist in tabs');
        expect(state.activeTabIndex >= 0 && state.activeTabIndex < state.tabs.length, isTrue,
            reason: 'Iteration $i: activeTabIndex out of bounds');

        // Check each tab items integrity
        for (final tab in state.tabs) {
          for (final entry in tab.items.entries) {
            expect(entry.value.quantity > 0, isTrue,
                reason: 'Iteration $i: Item quantity must be > 0 but was ${entry.value.quantity}');
            expect(entry.value.product.allowSale, isTrue,
                reason: 'Iteration $i: Disabled product should never be in cart');
          }
          expect(tab.totalItems >= 0, isTrue);
          expect(tab.totalAmount >= 0.0, isTrue);
        }
      }
    });
  });

  group('Adversarial Challenge 5: Riverpod Provider Synchronization & Memory Invariants', () {
    test('cartProvider, cartTotalItemsProvider, cartTotalAmountProvider perfectly mirror multiCart changes across tab lifecycle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Verify initial state
      expect(container.read(cartProvider), isEmpty);
      expect(container.read(cartTotalItemsProvider), equals(0));
      expect(container.read(cartTotalAmountProvider), equals(0.0));

      final multiNotifier = container.read(multiCartProvider.notifier);

      // 1. Add item to Tab 1
      multiNotifier.addToCart(sampleProduct1, quantity: 2);
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartTotalItemsProvider), equals(2));
      expect(container.read(cartTotalAmountProvider), equals(300000.0));

      // 2. Add Tab 2
      final tab2Id = multiNotifier.addNewTab();
      expect(container.read(cartProvider), isEmpty);
      expect(container.read(cartTotalItemsProvider), equals(0));
      expect(container.read(cartTotalAmountProvider), equals(0.0));

      // 3. Add item to Tab 2 via cartProvider.notifier
      container.read(cartProvider.notifier).addToCart(sampleProduct2, quantity: 3);
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider)['prod_adv_02']?.quantity, equals(3));
      expect(container.read(cartTotalItemsProvider), equals(3));
      expect(container.read(cartTotalAmountProvider), equals(1050000.0));

      // Check Tab 1 in multiCart is still intact
      final tab1 = container.read(multiCartProvider).tabs.first;
      expect(tab1.items['prod_adv_01']?.quantity, equals(2));
      expect(tab1.totalAmount, equals(300000.0));

      // 4. Switch back to Tab 1
      multiNotifier.switchTab(tab1.id);
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider)['prod_adv_01']?.quantity, equals(2));
      expect(container.read(cartTotalItemsProvider), equals(2));
      expect(container.read(cartTotalAmountProvider), equals(300000.0));

      // 5. Clear cart on Tab 1
      container.read(cartProvider.notifier).clearCart();
      expect(container.read(cartProvider), isEmpty);
      expect(container.read(cartTotalItemsProvider), equals(0));
      expect(container.read(cartTotalAmountProvider), equals(0.0));

      // Switch to Tab 2 -> Tab 2 items are still preserved!
      multiNotifier.switchTab(tab2Id);
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider)['prod_adv_02']?.quantity, equals(3));
      expect(container.read(cartTotalItemsProvider), equals(3));
      expect(container.read(cartTotalAmountProvider), equals(1050000.0));
    });
  });

  group('Adversarial Challenge 6: PopulateCart with Missing / Foreign Products', () {
    test('populateCart generates fallback Product entity when productId is missing in allProducts', () {
      final notifier = MultiCartNotifier();

      final orderItems = [
        OrderItem(
          productId: 'deleted_or_unknown_prod_99',
          productName: 'Sản phẩm đã bị xóa khỏi hệ thống',
          quantity: 2,
          price: 88000,
          warrantyMonths: 0,
          purchaseDate: DateTime.now(),
        ),
      ];

      // Empty catalog
      notifier.populateCart(orderItems, []);

      final tab = notifier.state.activeTab;
      expect(tab.items.containsKey('deleted_or_unknown_prod_99'), isTrue);
      final item = tab.items['deleted_or_unknown_prod_99']!;
      expect(item.quantity, equals(2));
      expect(item.price, equals(88000));
      expect(item.product.name, equals('Sản phẩm đã bị xóa khỏi hệ thống'));
      expect(tab.totalAmount, equals(176000.0));
    });
  });

  group('Adversarial Challenge 7: PosCartTabBar Widget Rapid Tap & Layout Stress Test', () {
    Widget buildTestWidget({required ProviderContainer container}) {
      return UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PosCartTabBar(),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('Rapidly taps Thêm đơn 10 times in UI and verifies all tabs render with correct titles', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestWidget(container: container));
      await tester.pumpAndSettle();

      for (int i = 0; i < 9; i++) {
        await tester.tap(find.byKey(const Key('pos_cart_add_tab_btn')));
        await tester.pumpAndSettle();
      }

      final state = container.read(multiCartProvider);
      expect(state.tabs.length, equals(10));
      expect(state.activeTab.title, equals('Hóa đơn 10'));

      // Check that add tab button is still findable and clickable
      expect(find.byKey(const Key('pos_cart_add_tab_btn')), findsOneWidget);
    });

    testWidgets('Non-empty cart close dialog cancel vs confirm preserves vs deletes tab in UI', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestWidget(container: container));
      await tester.pumpAndSettle();

      // Add item to Hóa đơn 1
      container.read(multiCartProvider.notifier).addToCart(sampleProduct1, quantity: 4);
      await tester.pumpAndSettle();

      // Tap add tab -> Hóa đơn 2
      await tester.tap(find.byKey(const Key('pos_cart_add_tab_btn')));
      await tester.pumpAndSettle();

      final tab1Id = container.read(multiCartProvider).tabs.first.id;

      // Tap close on Hóa đơn 1 (non-empty)
      await tester.tap(find.byKey(Key('pos_cart_tab_close_$tab1Id')));
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('đang có 4 sản phẩm'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Bỏ qua'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(container.read(multiCartProvider).tabs.length, equals(2));

      // Close again and confirm
      await tester.tap(find.byKey(Key('pos_cart_tab_close_$tab1Id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đóng hóa đơn'));
      await tester.pumpAndSettle();

      expect(container.read(multiCartProvider).tabs.length, equals(1));
      expect(container.read(multiCartProvider).activeTab.title, equals('Hóa đơn 2'));
    });
  });
}
