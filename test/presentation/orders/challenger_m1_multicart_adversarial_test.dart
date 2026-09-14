import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/orders/widgets/pos_cart_tab_bar.dart';

void main() {
  const p1 = Product(
    id: 'prod_1',
    name: 'Cà phê sữa đá',
    code: 'CFSD',
    price: 25000,
    costPrice: 10000,
    branchStocks: {'store_001': 50, 'store_002': 30},
    category: 'Drinks',
    allowSale: true,
  );

  const p2 = Product(
    id: 'prod_2',
    name: 'Bánh mì thịt nướng',
    code: 'BMTN',
    price: 35000,
    costPrice: 18000,
    branchStocks: {'store_001': 20, 'store_002': 15},
    category: 'Food',
    allowSale: true,
  );

  const p3 = Product(
    id: 'prod_3',
    name: 'Trà đào cam sả',
    code: 'TDCS',
    price: 40000,
    costPrice: 15000,
    branchStocks: {'store_001': 100},
    category: 'Drinks',
    allowSale: true,
  );

  const cust1 = Customer(
    id: 'c_01',
    name: 'Nguyễn Văn Minh',
    phone: '0901112233',
    email: 'minh@example.com',
    address: 'Cần Thơ',
    purchases: [],
  );

  const cust2 = Customer(
    id: 'c_02',
    name: 'Trần Thị Lan',
    phone: '0904445566',
    email: 'lan@example.com',
    address: 'Hậu Giang',
    purchases: [],
  );

  group('Adversarial Challenge 1: Backward Compatibility of Cart Providers', () {
    test('Standalone CartNotifier without Ref functions independently without errors', () {
      final standaloneNotifier = CartNotifier();
      expect(standaloneNotifier.state, isEmpty);

      standaloneNotifier.addToCart(p1, quantity: 2);
      expect(standaloneNotifier.state.length, equals(1));
      expect(standaloneNotifier.state['prod_1']!.quantity, equals(2));
      expect(standaloneNotifier.state['prod_1']!.total, equals(50000));

      standaloneNotifier.increaseQuantity('prod_1');
      expect(standaloneNotifier.state['prod_1']!.quantity, equals(3));

      standaloneNotifier.decreaseQuantity('prod_1');
      expect(standaloneNotifier.state['prod_1']!.quantity, equals(2));

      standaloneNotifier.updateQuantity('prod_1', 10);
      expect(standaloneNotifier.state['prod_1']!.quantity, equals(10));

      standaloneNotifier.updatePrice('prod_1', 20000);
      expect(standaloneNotifier.state['prod_1']!.customPrice, equals(20000));
      expect(standaloneNotifier.state['prod_1']!.total, equals(200000));

      standaloneNotifier.removeFromCart('prod_1');
      expect(standaloneNotifier.state, isEmpty);

      standaloneNotifier.populateCart(
        [
          OrderItem(
            productId: 'prod_2',
            productName: 'Bánh mì thịt nướng',
            quantity: 5,
            price: 32000,
            warrantyMonths: 0,
            purchaseDate: DateTime.now(),
          ),
        ],
        [p2],
      );
      expect(standaloneNotifier.state.length, equals(1));
      expect(standaloneNotifier.state['prod_2']!.quantity, equals(5));
      expect(standaloneNotifier.state['prod_2']!.customPrice, equals(32000));

      standaloneNotifier.clearCart();
      expect(standaloneNotifier.state, isEmpty);
    });

    test('cartProvider bridges with multiCartProvider across all operations in lockstep', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Verify initial state
      expect(container.read(cartProvider), isEmpty);
      expect(container.read(cartTotalItemsProvider), equals(0));
      expect(container.read(cartTotalAmountProvider), equals(0.0));

      // 1. Add item via legacy cartProvider.notifier
      container.read(cartProvider.notifier).addToCart(p1, quantity: 2);
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider)['prod_1']!.quantity, equals(2));
      expect(container.read(cartTotalItemsProvider), equals(2));
      expect(container.read(cartTotalAmountProvider), equals(50000.0));

      // multiCartProvider active tab must match
      final multiState = container.read(multiCartProvider);
      expect(multiState.activeTab.totalItems, equals(2));
      expect(multiState.activeTab.totalAmount, equals(50000.0));
      expect(multiState.activeTab.items['prod_1']!.quantity, equals(2));

      // 2. Increase quantity via cartProvider.notifier
      container.read(cartProvider.notifier).increaseQuantity('prod_1');
      expect(container.read(cartTotalItemsProvider), equals(3));
      expect(container.read(cartTotalAmountProvider), equals(75000.0));

      // 3. Update price via cartProvider.notifier
      container.read(cartProvider.notifier).updatePrice('prod_1', 22000.0);
      expect(container.read(cartProvider)['prod_1']!.customPrice, equals(22000.0));
      expect(container.read(cartTotalAmountProvider), equals(66000.0));

      // 4. Decrease quantity via cartProvider.notifier
      container.read(cartProvider.notifier).decreaseQuantity('prod_1');
      expect(container.read(cartTotalItemsProvider), equals(2));
      expect(container.read(cartTotalAmountProvider), equals(44000.0));

      // 5. Add second product
      container.read(cartProvider.notifier).addToCart(p2, quantity: 1);
      expect(container.read(cartTotalItemsProvider), equals(3));
      expect(container.read(cartTotalAmountProvider), equals(44000.0 + 35000.0));

      // 6. Remove product via cartProvider.notifier
      container.read(cartProvider.notifier).removeFromCart('prod_1');
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider).containsKey('prod_1'), isFalse);
      expect(container.read(cartTotalItemsProvider), equals(1));
      expect(container.read(cartTotalAmountProvider), equals(35000.0));

      // 7. Clear cart via cartProvider.notifier
      container.read(cartProvider.notifier).clearCart();
      expect(container.read(cartProvider), isEmpty);
      expect(container.read(cartTotalItemsProvider), equals(0));
      expect(container.read(cartTotalAmountProvider), equals(0.0));
    });
  });

  group('Adversarial Challenge 2: Multi-Tab Scaling & Strict Data Isolation', () {
    test('Creating 20 tabs sequentially numbers titles cleanly and maintains active selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final multiNotifier = container.read(multiCartProvider.notifier);

      for (int i = 2; i <= 20; i++) {
        final newId = multiNotifier.addNewTab();
        final state = container.read(multiCartProvider);
        expect(state.tabs.length, equals(i));
        expect(state.activeTabId, equals(newId));
        expect(state.activeTab.title, equals('Hóa đơn $i'));
      }

      final finalState = container.read(multiCartProvider);
      expect(finalState.tabs.length, equals(20));
      expect(finalState.tabs.map((t) => t.title).toList(), [
        for (int i = 1; i <= 20; i++) 'Hóa đơn $i',
      ]);
    });

    test('Multiple tabs hold strictly isolated carts, customers, discounts, and notes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final multiNotifier = container.read(multiCartProvider.notifier);

      // Tab 1: Product 1 (qty 2), Customer 1, Discount 10%
      final tab1Id = container.read(multiCartProvider).activeTabId;
      multiNotifier.addToCart(p1, quantity: 2);
      multiNotifier.setCustomer(cust1);
      multiNotifier.setDiscount(10.0, true);
      multiNotifier.setNote('Khách quen Tab 1');
      multiNotifier.setActiveOrderId('order_draft_1');

      // Tab 2: Product 2 (qty 3), Customer 2, Discount 50,000 VND
      final tab2Id = multiNotifier.addNewTab();
      multiNotifier.addToCart(p2, quantity: 3);
      multiNotifier.setCustomer(cust2);
      multiNotifier.setDiscount(50000.0, false);
      multiNotifier.setNote('Giao trưa Tab 2');
      multiNotifier.setActiveOrderId('order_draft_2');

      // Tab 3: Product 3 (qty 5), No customer, No discount
      final tab3Id = multiNotifier.addNewTab();
      multiNotifier.addToCart(p3, quantity: 5);
      multiNotifier.setNote('Tab 3 khách lẻ');

      // --- Verify Tab 3 state ---
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider)['prod_3']!.quantity, equals(5));
      expect(container.read(cartTotalItemsProvider), equals(5));
      expect(container.read(cartTotalAmountProvider), equals(200000.0));
      expect(container.read(multiCartProvider).activeTab.customer, isNull);
      expect(container.read(multiCartProvider).activeTab.discount, equals(0.0));

      // --- Switch to Tab 1 ---
      multiNotifier.switchTab(tab1Id);
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider)['prod_1']!.quantity, equals(2));
      expect(container.read(cartTotalItemsProvider), equals(2));
      expect(container.read(cartTotalAmountProvider), equals(50000.0));
      expect(container.read(multiCartProvider).activeTab.customer, equals(cust1));
      expect(container.read(multiCartProvider).activeTab.discount, equals(10.0));
      expect(container.read(multiCartProvider).activeTab.isDiscountPercent, isTrue);
      expect(container.read(multiCartProvider).activeTab.note, equals('Khách quen Tab 1'));
      expect(container.read(multiCartProvider).activeTab.activeOrderId, equals('order_draft_1'));

      // --- Switch to Tab 2 ---
      multiNotifier.switchTab(tab2Id);
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider)['prod_2']!.quantity, equals(3));
      expect(container.read(cartTotalItemsProvider), equals(3));
      expect(container.read(cartTotalAmountProvider), equals(105000.0));
      expect(container.read(multiCartProvider).activeTab.customer, equals(cust2));
      expect(container.read(multiCartProvider).activeTab.discount, equals(50000.0));
      expect(container.read(multiCartProvider).activeTab.isDiscountPercent, isFalse);
      expect(container.read(multiCartProvider).activeTab.note, equals('Giao trưa Tab 2'));
      expect(container.read(multiCartProvider).activeTab.activeOrderId, equals('order_draft_2'));

      // --- Checkout simulation on Tab 2: clearCart only affects Tab 2 ---
      container.read(cartProvider.notifier).clearCart();
      expect(container.read(cartProvider), isEmpty);
      expect(container.read(cartTotalItemsProvider), equals(0));

      // Switch back to Tab 1 -> Tab 1 is fully intact!
      multiNotifier.switchTab(tab1Id);
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider)['prod_1']!.quantity, equals(2));
      expect(container.read(multiCartProvider).activeTab.customer, equals(cust1));

      // Switch back to Tab 3 -> Tab 3 is fully intact!
      multiNotifier.switchTab(tab3Id);
      expect(container.read(cartProvider).length, equals(1));
      expect(container.read(cartProvider)['prod_3']!.quantity, equals(5));
    });
  });

  group('Adversarial Challenge 3: Complex Tab Closure, Re-indexing & Self-Healing', () {
    test('Closing middle active tab safely focuses preceding neighbor', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final multiNotifier = container.read(multiCartProvider.notifier);
      final tab1Id = container.read(multiCartProvider).activeTabId;
      final tab2Id = multiNotifier.addNewTab();
      final tab3Id = multiNotifier.addNewTab();

      // Active is tab3 (index 2). Switch to middle tab2 (index 1).
      multiNotifier.switchTab(tab2Id);
      expect(container.read(multiCartProvider).activeTabId, equals(tab2Id));

      // Close tab2 -> should shift to tab1 (index 0)
      multiNotifier.closeTab(tab2Id);
      final state = container.read(multiCartProvider);
      expect(state.tabs.length, equals(2));
      expect(state.tabs.map((t) => t.id).toList(), [tab1Id, tab3Id]);
      expect(state.activeTabId, equals(tab1Id));
    });

    test('Closing active first tab shifts focus to new first tab', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final multiNotifier = container.read(multiCartProvider.notifier);
      final tab1Id = container.read(multiCartProvider).activeTabId;
      final tab2Id = multiNotifier.addNewTab();
      multiNotifier.addNewTab();

      // Switch to first tab (tab1Id)
      multiNotifier.switchTab(tab1Id);
      expect(container.read(multiCartProvider).activeTabId, equals(tab1Id));

      // Close first tab -> should focus new first tab (tab2Id)
      multiNotifier.closeTab(tab1Id);
      final state = container.read(multiCartProvider);
      expect(state.tabs.length, equals(2));
      expect(state.activeTabId, equals(tab2Id));
    });

    test('Closing all tabs down to zero triggers automatic self-healing default tab', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final multiNotifier = container.read(multiCartProvider.notifier);
      final tab1Id = container.read(multiCartProvider).activeTabId;
      final tab2Id = multiNotifier.addNewTab();

      multiNotifier.closeTab(tab1Id);
      expect(container.read(multiCartProvider).tabs.length, equals(1));

      // Close remaining tab2 -> must heal
      multiNotifier.closeTab(tab2Id);
      final healedState = container.read(multiCartProvider);
      expect(healedState.tabs.length, equals(1));
      expect(healedState.tabs.first.title, equals('Hóa đơn 1'));
      expect(healedState.activeTab.items, isEmpty);
      expect(healedState.activeTabId, equals(healedState.tabs.first.id));
    });
  });

  group('Adversarial Challenge 4: PosCartTabBar UI Lifecycle & Interactive Stress', () {
    Widget buildTestHost({required ProviderContainer container}) {
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

    testWidgets('PosCartTabBar handles rapid tab creation, tab switching, and dialog interactions', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestHost(container: container));
      await tester.pumpAndSettle();

      // Initial tab 1 visible
      expect(find.text('Hóa đơn 1'), findsOneWidget);
      expect(find.byKey(const Key('pos_cart_add_tab_btn')), findsOneWidget);

      // 1. Rapidly tap "Thêm đơn" 4 times
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('pos_cart_add_tab_btn')));
        await tester.pumpAndSettle();
      }

      expect(container.read(multiCartProvider).tabs.length, equals(5));
      expect(find.text('Hóa đơn 5'), findsOneWidget);

      // 2. Put 3 items into Hóa đơn 5
      container.read(multiCartProvider.notifier).addToCart(p1, quantity: 3);
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);

      // 3. Attempt to close non-empty Hóa đơn 5 -> Prompt modal dialog
      final tab5Id = container.read(multiCartProvider).activeTabId;
      await tester.tap(find.byKey(Key('pos_cart_tab_close_$tab5Id')));
      await tester.pumpAndSettle();

      expect(find.text('Đóng hóa đơn tạm?'), findsOneWidget);
      final currencyFormat = NumberFormat('#,###', 'vi_VN');
      final expectedMoneyStr = currencyFormat.format(75000);
      expect(find.textContaining(expectedMoneyStr), findsOneWidget);

      // 4. Cancel closing via "Bỏ qua"
      await tester.tap(find.text('Bỏ qua'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(container.read(multiCartProvider).tabs.length, equals(5));

      // 5. Re-tap close on Hóa đơn 5 and confirm "Đóng hóa đơn"
      await tester.tap(find.byKey(Key('pos_cart_tab_close_$tab5Id')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Đóng hóa đơn'));
      await tester.pumpAndSettle();

      expect(container.read(multiCartProvider).tabs.length, equals(4));
      expect(find.text('Hóa đơn 5'), findsNothing);
      // Active tab shifted to Hóa đơn 4
      expect(container.read(multiCartProvider).activeTab.title, equals('Hóa đơn 4'));

      // 6. Close an empty tab (Hóa đơn 4) -> Closes immediately with 0 dialogs
      final tab4Id = container.read(multiCartProvider).activeTabId;
      await tester.tap(find.byKey(Key('pos_cart_tab_close_$tab4Id')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(container.read(multiCartProvider).tabs.length, equals(3));
      expect(find.text('Hóa đơn 4'), findsNothing);
    });

    testWidgets('Renaming tab updates PosCartTabBar display text reactively', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildTestHost(container: container));
      await tester.pumpAndSettle();

      final tab1Id = container.read(multiCartProvider).activeTabId;
      expect(find.text('Hóa đơn 1'), findsOneWidget);

      container.read(multiCartProvider.notifier).renameTab(tab1Id, 'Bàn 04 - VIP');
      await tester.pumpAndSettle();

      expect(find.text('Hóa đơn 1'), findsNothing);
      expect(find.text('Bàn 04 - VIP'), findsOneWidget);
    });
  });
}
