import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/orders/widgets/pos_cart_tab_bar.dart';

void main() {
  const sampleProduct = Product(
    id: 'prod_001',
    name: 'Sữa chua Vinamilk 100g',
    code: 'SCVM',
    price: 8000,
    costPrice: 5000,
    branchStocks: {'store_001': 20},
    category: 'Dairy',
    allowSale: true,
  );

  Widget createTestWidget({ProviderContainer? container}) {
    const widget = MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            PosCartTabBar(),
          ],
        ),
      ),
    );

    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: widget,
      );
    }
    return const ProviderScope(child: widget);
  }

  testWidgets('PosCartTabBar renders initial default tab and add tab button', (tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Hóa đơn 1'), findsOneWidget);
    expect(find.text('Thêm đơn'), findsOneWidget);
    expect(find.byKey(const Key('pos_cart_add_tab_btn')), findsOneWidget);
  });

  testWidgets('Tapping Thêm đơn adds Hóa đơn 2 and switches to it', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(createTestWidget(container: container));
    await tester.pumpAndSettle();

    // Tap add tab
    await tester.tap(find.byKey(const Key('pos_cart_add_tab_btn')));
    await tester.pumpAndSettle();

    expect(find.text('Hóa đơn 1'), findsOneWidget);
    expect(find.text('Hóa đơn 2'), findsOneWidget);

    final multiState = container.read(multiCartProvider);
    expect(multiState.tabs.length, equals(2));
    expect(multiState.activeTab.title, equals('Hóa đơn 2'));
  });

  testWidgets('Adding items to tab shows item counter badge', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(createTestWidget(container: container));
    await tester.pumpAndSettle();

    // Add 3 items to active tab
    container.read(multiCartProvider.notifier).addToCart(sampleProduct, quantity: 3);
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('Switching tab changes active tab state', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(createTestWidget(container: container));
    await tester.pumpAndSettle();

    // Add Tab 2
    await tester.tap(find.byKey(const Key('pos_cart_add_tab_btn')));
    await tester.pumpAndSettle();

    final tab1Id = container.read(multiCartProvider).tabs.first.id;

    // Switch to Tab 1
    await tester.tap(find.byKey(Key('pos_cart_tab_$tab1Id')));
    await tester.pumpAndSettle();

    expect(container.read(multiCartProvider).activeTabId, equals(tab1Id));
  });

  testWidgets('Closing empty tab closes immediately without dialog', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(createTestWidget(container: container));
    await tester.pumpAndSettle();

    // Add Tab 2
    await tester.tap(find.byKey(const Key('pos_cart_add_tab_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Hóa đơn 2'), findsOneWidget);

    final tab2Id = container.read(multiCartProvider).activeTabId;

    // Close Tab 2 (which is empty)
    await tester.tap(find.byKey(Key('pos_cart_tab_close_$tab2Id')));
    await tester.pumpAndSettle();

    expect(find.text('Hóa đơn 2'), findsNothing);
    expect(container.read(multiCartProvider).tabs.length, equals(1));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Closing non-empty tab shows confirmation dialog and cancels on Bỏ qua', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(createTestWidget(container: container));
    await tester.pumpAndSettle();

    final tab1Id = container.read(multiCartProvider).activeTabId;
    container.read(multiCartProvider.notifier).addToCart(sampleProduct, quantity: 2);
    await tester.pumpAndSettle();

    // Tap close on non-empty Tab 1
    await tester.tap(find.byKey(Key('pos_cart_tab_close_$tab1Id')));
    await tester.pumpAndSettle();

    // Dialog appears
    expect(find.text('Đóng hóa đơn tạm?'), findsOneWidget);
    expect(find.text('Bỏ qua'), findsOneWidget);
    expect(find.text('Đóng hóa đơn'), findsOneWidget);

    // Tap Bỏ qua
    await tester.tap(find.text('Bỏ qua'));
    await tester.pumpAndSettle();

    // Tab 1 still exists
    expect(find.text('Hóa đơn 1'), findsOneWidget);
    expect(container.read(multiCartProvider).tabs.length, equals(1));
    expect(container.read(multiCartProvider).activeTab.totalItems, equals(2));
  });

  testWidgets('Closing non-empty tab removes tab when confirmed', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(createTestWidget(container: container));
    await tester.pumpAndSettle();

    // Add Tab 2
    await tester.tap(find.byKey(const Key('pos_cart_add_tab_btn')));
    await tester.pumpAndSettle();

    final tab2Id = container.read(multiCartProvider).activeTabId;
    container.read(multiCartProvider.notifier).addToCart(sampleProduct, quantity: 5);
    await tester.pumpAndSettle();

    // Tap close on Tab 2
    await tester.tap(find.byKey(Key('pos_cart_tab_close_$tab2Id')));
    await tester.pumpAndSettle();

    // Confirm close
    await tester.tap(find.text('Đóng hóa đơn'));
    await tester.pumpAndSettle();

    expect(find.text('Hóa đơn 2'), findsNothing);
    expect(container.read(multiCartProvider).tabs.length, equals(1));
    expect(container.read(multiCartProvider).activeTab.title, equals('Hóa đơn 1'));
  });
}
