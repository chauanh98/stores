import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/orders/widgets/draft_orders_bottom_sheet.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

void main() {
  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản Trị Viên',
    role: 'admin',
    storeId: 'store_001',
  );

  final sampleDraftOrder = Order(
    id: 'HD_DRAFT_001',
    customerId: 'cust_001',
    customerName: 'Nguyễn Văn A',
    createdAt: DateTime(2026, 10, 1, 14, 30),
    items: [
      OrderItem(
        productId: 'prod_001',
        productName: 'Bàn ăn cao cấp',
        quantity: 2,
        price: 5000000.0,
        warrantyMonths: 12,
        purchaseDate: DateTime(2026, 10, 1),
      ),
    ],
    total: 10000000.0,
    status: 'draft',
    storeId: 'store_001',
    note: 'Giao chiều nay',
    createdByName: 'admin',
  );

  const sampleProduct = Product(
    id: 'prod_001',
    name: 'Bàn ăn cao cấp',
    code: 'BA01',
    price: 5000000.0,
    costPrice: 4000000.0,
    branchStocks: {'store_001': 10},
    category: 'Bàn',
    allowSale: true,
  );

  Widget createTestWidget({
    List<Order> draftOrders = const [],
    ProviderContainer? container,
  }) {
    const app = MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('vi'),
      home: POSPage(),
    );

    final overrides = [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
      productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
      posDraftOrdersProvider.overrideWith((ref) => Stream.value(draftOrders)),
    ];

    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: app,
      );
    }

    return ProviderScope(
      overrides: overrides,
      child: app,
    );
  }

  testWidgets(
      'POSPage AppBar renders pos_draft_orders_action icon without duplicate storefront branch switcher',
      (tester) async {
    await tester.pumpWidget(createTestWidget(draftOrders: []));
    await tester.pumpAndSettle();

    // Verify draft orders action icon exists
    expect(find.byKey(const Key('pos_draft_orders_action')), findsOneWidget);
    expect(find.byIcon(Icons.pending_actions_outlined), findsOneWidget);

    // Verify duplicate storefront action is REMOVED
    expect(find.byKey(const Key('pos_branch_switcher_action')), findsNothing);

    // Verify branch switcher in title is intact
    expect(find.byKey(const Key('pos_branch_switcher_button')), findsOneWidget);

    // Verify badge is not visible when 0 draft orders
    final badgeFinder = find.descendant(
      of: find.byKey(const Key('pos_draft_orders_action')),
      matching: find.byType(Badge),
    );
    expect(badgeFinder, findsOneWidget);
    final badgeWidget = tester.widget<Badge>(badgeFinder);
    expect(badgeWidget.isLabelVisible, isFalse);
  });

  testWidgets(
      'POSPage AppBar shows badge with draft count when there are draft orders',
      (tester) async {
    await tester.pumpWidget(createTestWidget(draftOrders: [sampleDraftOrder]));
    await tester.pumpAndSettle();

    final badgeFinder = find.descendant(
      of: find.byKey(const Key('pos_draft_orders_action')),
      matching: find.byType(Badge),
    );
    expect(badgeFinder, findsOneWidget);
    expect(tester.widget<Badge>(badgeFinder).isLabelVisible, isTrue);
    expect(
      find.descendant(
        of: find.byKey(const Key('pos_draft_orders_action')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'Tapping pos_draft_orders_action opens DraftOrdersBottomSheet displaying draft details',
      (tester) async {
    await tester.pumpWidget(createTestWidget(draftOrders: [sampleDraftOrder]));
    await tester.pumpAndSettle();

    // Tap draft orders action
    await tester.tap(find.byKey(const Key('pos_draft_orders_action')));
    await tester.pumpAndSettle();

    // Verify bottom sheet is displayed
    expect(find.byType(DraftOrdersBottomSheet), findsOneWidget);
    expect(find.text('Đơn hàng tạm (1)'), findsOneWidget);
    expect(find.text('HD_DRAFT_001'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Giao chiều nay'), findsOneWidget);
    expect(find.text('Mở đơn'), findsOneWidget);
    expect(find.text('Hủy'), findsOneWidget);
  });

  testWidgets(
      'Resuming draft order populates cart and sets activeOrderId',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        productListProvider
            .overrideWith((ref) => Stream.value([sampleProduct])),
        posDraftOrdersProvider
            .overrideWith((ref) => Stream.value([sampleDraftOrder])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(createTestWidget(
      draftOrders: [sampleDraftOrder],
      container: container,
    ));
    await tester.pumpAndSettle();

    // Open bottom sheet
    await tester.tap(find.byKey(const Key('pos_draft_orders_action')));
    await tester.pumpAndSettle();

    // Tap "Mở đơn"
    await tester.tap(find.text('Mở đơn'));
    await tester.pumpAndSettle();

    // Bottom sheet is closed
    expect(find.byType(DraftOrdersBottomSheet), findsNothing);

    // Cart tab is populated with items and activeOrderId
    final cart = container.read(cartProvider);
    expect(cart.containsKey('prod_001'), isTrue);
    expect(cart['prod_001']!.quantity, equals(2));
    expect(container.read(activeOrderIdProvider), equals('HD_DRAFT_001'));
  });
}
