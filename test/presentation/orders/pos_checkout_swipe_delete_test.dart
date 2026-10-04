import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';

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

class _FakeCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _FakeCustomerListNotifier(this._initialCustomers);

  final List<Customer> _initialCustomers;

  @override
  Future<List<Customer>> build() async {
    return _initialCustomers;
  }

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialCustomers);
  }
}

void main() {
  const staffUser = UserAccount(
    username: 'staff_cashier',
    displayName: 'Thu ngân',
    role: 'nhanvien',
    storeId: 'store_001',
  );

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
    name: 'Trà đào cam sả',
    code: 'TDCS',
    price: 45000,
    costPrice: 22000,
    branchStocks: {'store_001': 15},
    category: 'Tea',
    allowSale: true,
  );

  setUp(() {
    MultiCartNotifier.resetBranchCartsCache();
  });

  group('POS Checkout Swipe-To-Delete & Undo Widget Tests (R1)', () {
    testWidgets(
      'Vuốt xóa sản phẩm -> giỏ hàng giảm món, cập nhật tổng tiền & tổng số lượng',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh 1',
                }),
            productListProvider.overrideWith((ref) => Stream.value([productA, productB])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
          ],
        );

        // Add 2 items for productA and 1 for productB
        container.read(cartProvider.notifier).addToCart(productA, quantity: 2);
        container.read(cartProvider.notifier).addToCart(productB, quantity: 1);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('vi'),
              home: POSCheckoutPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Check both items exist initially
        expect(find.text('Cà phê Robusta'), findsOneWidget);
        expect(find.text('Trà đào cam sả'), findsOneWidget);
        // Total items: 2 + 1 = 3
        expect(find.text('3'), findsOneWidget);
        // Total amount: (35k * 2) + 45k = 115k
        expect(find.text('115.000 đ'), findsOneWidget);

        // Swipe productA left to delete
        final dismissibleA = find.byKey(const Key('dismissible_cart_item_prod_1'));
        expect(dismissibleA, findsOneWidget);

        await tester.drag(dismissibleA, const Offset(-500, 0));
        await tester.pumpAndSettle();

        // productA is removed
        expect(find.text('Cà phê Robusta'), findsNothing);
        expect(find.text('Trà đào cam sả'), findsOneWidget);

        // Total items is updated to 1 (present in stepper and summary badge)
        expect(find.text('1'), findsWidgets);
        // Total amount is updated to 45k (present in product row and summary total)
        expect(find.text('45.000'), findsWidgets);

        // SnackBar appears with undo action
        expect(find.text('Đã xóa "Cà phê Robusta" khỏi giỏ hàng'), findsOneWidget);
        expect(find.text('Hoàn tác'), findsOneWidget);
      },
    );

    testWidgets(
      'Nhấn nút "Hoàn tác" -> món hàng được khôi phục về giỏ hàng với đầy đủ thông tin',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh 1',
                }),
            productListProvider.overrideWith((ref) => Stream.value([productA, productB])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
          ],
        );

        // Add productA with custom details (quantity 2, discount 5000, note)
        container.read(cartProvider.notifier).addToCart(productA, quantity: 2);
        container.read(cartProvider.notifier).updateItemDetails(
              productA.id,
              discount: 5000,
              isDiscountPercent: false,
              note: 'Ít ngọt',
            );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('vi'),
              home: POSCheckoutPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Cà phê Robusta'), findsOneWidget);
        expect(find.text('Ít ngọt'), findsOneWidget);

        // Swipe to delete
        final dismissible = find.byKey(const Key('dismissible_cart_item_prod_1'));
        await tester.drag(dismissible, const Offset(-500, 0));
        await tester.pumpAndSettle();

        // Verify it disappeared and cart is empty
        expect(find.text('Cà phê Robusta'), findsNothing);
        expect(find.text('Giỏ hàng đang trống'), findsOneWidget);

        // Tap Hoàn tác
        final undoButton = find.text('Hoàn tác');
        expect(undoButton, findsOneWidget);
        await tester.tap(undoButton);
        await tester.pumpAndSettle();

        // Product is restored back into cart
        expect(find.text('Cà phê Robusta'), findsOneWidget);
        expect(find.text('Ít ngọt'), findsOneWidget);
        expect(find.text('-5.000đ'), findsOneWidget);
        // Effective price (35k - 5k) * 2 = 60k
        expect(find.text('60.000 đ'), findsOneWidget);
        expect(find.text('2'), findsWidgets);
      },
    );

    testWidgets(
      'Vuốt xóa, hoàn tác, rồi vuốt xóa lại cùng sản phẩm -> Không crash Dismissible tree, tính lại giỏ chính xác',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh 1',
                }),
            productListProvider
                .overrideWith((ref) => Stream.value([productA, productB])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
          ],
        );

        container.read(cartProvider.notifier).addToCart(productA, quantity: 2);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('vi'),
              home: POSCheckoutPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. First swipe to delete
        final dismissible =
            find.byKey(const Key('dismissible_cart_item_prod_1'));
        await tester.drag(dismissible, const Offset(-500, 0));
        await tester.pumpAndSettle();

        expect(find.text('Cà phê Robusta'), findsNothing);
        expect(find.text('Giỏ hàng đang trống'), findsOneWidget);

        // 2. Undo
        await tester.tap(find.text('Hoàn tác'));
        await tester.pumpAndSettle();

        expect(find.text('Cà phê Robusta'), findsOneWidget);
        expect(find.text('70.000 đ'), findsOneWidget);

        // 3. Swipe to delete AGAIN on the restored widget
        final dismissibleRestored =
            find.byKey(const Key('dismissible_cart_item_prod_1'));
        await tester.drag(dismissibleRestored, const Offset(500, 0)); // swipe right
        await tester.pumpAndSettle();

        expect(find.text('Cà phê Robusta'), findsNothing);
        expect(find.text('Giỏ hàng đang trống'), findsOneWidget);
        expect(find.text('Đã xóa "Cà phê Robusta" khỏi giỏ hàng'), findsOneWidget);
      },
    );

    testWidgets(
      'Vuốt xóa nhanh nhiều sản phẩm liên tiếp -> Giỏ hàng cập nhật đúng, hoàn tác sản phẩm gần nhất thành công',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh 1',
                }),
            productListProvider
                .overrideWith((ref) => Stream.value([productA, productB])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
          ],
        );

        container.read(cartProvider.notifier).addToCart(productA, quantity: 2);
        container.read(cartProvider.notifier).addToCart(productB, quantity: 1);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('vi'),
              home: POSCheckoutPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Total items = 3 (2 of A, 1 of B), Total amount = 115k
        expect(find.text('115.000 đ'), findsOneWidget);

        // Swipe product A
        await tester.drag(
          find.byKey(const Key('dismissible_cart_item_prod_1')),
          const Offset(-500, 0),
        );
        await tester.pumpAndSettle();

        expect(find.text('Cà phê Robusta'), findsNothing);
        expect(find.text('Trà đào cam sả'), findsOneWidget);

        // Immediately swipe product B
        await tester.drag(
          find.byKey(const Key('dismissible_cart_item_prod_2')),
          const Offset(-500, 0),
        );
        await tester.pumpAndSettle();

        expect(find.text('Trà đào cam sả'), findsNothing);
        expect(find.text('Giỏ hàng đang trống'), findsOneWidget);

        // Tap Hoàn tác for product B
        await tester.tap(find.text('Hoàn tác'));
        await tester.pumpAndSettle();

        expect(find.text('Trà đào cam sả'), findsOneWidget);
        expect(find.text('45.000'), findsWidgets);
        expect(find.text('1'), findsWidgets);
      },
    );

    testWidgets(
      'Kéo nhẹ dưới ngưỡng (drag offset nhỏ) -> huỷ thao tác, sản phẩm vẫn còn nguyên trong giỏ',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh 1',
                }),
            productListProvider
                .overrideWith((ref) => Stream.value([productA, productB])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
          ],
        );

        container.read(cartProvider.notifier).addToCart(productA, quantity: 2);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('vi'),
              home: POSCheckoutPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Drag only 20px horizontally
        final dismissible =
            find.byKey(const Key('dismissible_cart_item_prod_1'));
        await tester.drag(dismissible, const Offset(-20, 0));
        await tester.pumpAndSettle();

        // Product remains
        expect(find.text('Cà phê Robusta'), findsOneWidget);
        expect(find.text('70.000 đ'), findsOneWidget);
        // SnackBar does not appear
        expect(find.text('Hoàn tác'), findsNothing);
      },
    );

    testWidgets(
      'Vuốt xóa ở Tab 1, sau đó tab active đổi sang Tab 2, nhấn Hoàn tác -> Sản phẩm được khôi phục về Tab 1',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh 1',
                }),
            productListProvider
                .overrideWith((ref) => Stream.value([productA, productB])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
          ],
        );

        final tab1Id = container.read(multiCartProvider).activeTabId;
        container.read(cartProvider.notifier).addToCart(productA, quantity: 2);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale('vi'),
              home: POSCheckoutPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Cà phê Robusta'), findsOneWidget);

        // 1. Swipe delete on Tab 1
        final dismissible =
            find.byKey(const Key('dismissible_cart_item_prod_1'));
        await tester.drag(dismissible, const Offset(-500, 0));
        await tester.pumpAndSettle();

        expect(find.text('Cà phê Robusta'), findsNothing);

        // 2. Add Tab 2 and switch active tab to Tab 2
        final tab2Id =
            container.read(multiCartProvider.notifier).addNewTab(title: 'Hóa đơn 2');
        await tester.pumpAndSettle();
        expect(container.read(multiCartProvider).activeTabId, tab2Id);

        // 3. Tap Hoàn tác on the active SnackBar
        final undoBtn = find.text('Hoàn tác');
        expect(undoBtn, findsOneWidget);
        await tester.tap(undoBtn);
        await tester.pumpAndSettle();

        // Tab 1 should now have productA restored!
        final tab1 = container
            .read(multiCartProvider)
            .tabs
            .firstWhere((t) => t.id == tab1Id);
        expect(tab1.items.containsKey(productA.id), true);
        expect(tab1.items[productA.id]!.quantity, 2);

        // Tab 2 remains empty!
        final tab2 = container
            .read(multiCartProvider)
            .tabs
            .firstWhere((t) => t.id == tab2Id);
        expect(tab2.items.containsKey(productA.id), false);
      },
    );

    testWidgets(
      'Vuốt xóa món hàng, đóng/pop trang POSCheckoutPage, sau đó nhấn Hoàn tác -> Không crash và khôi phục món hàng thành công',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh 1',
                }),
            productListProvider
                .overrideWith((ref) => Stream.value([productA, productB])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier([])),
          ],
        );

        container.read(cartProvider.notifier).addToCart(productA, quantity: 2);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('vi'),
              home: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const POSCheckoutPage(),
                        ),
                      );
                    },
                    child: const Text('Go to Checkout'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to POSCheckoutPage
        await tester.tap(find.text('Go to Checkout'));
        await tester.pumpAndSettle();

        expect(find.text('Cà phê Robusta'), findsOneWidget);

        // Swipe delete productA
        final dismissible =
            find.byKey(const Key('dismissible_cart_item_prod_1'));
        await tester.drag(dismissible, const Offset(-500, 0));
        await tester.pumpAndSettle();

        expect(find.text('Cà phê Robusta'), findsNothing);
        expect(find.text('Hoàn tác'), findsOneWidget);

        // Now pop POSCheckoutPage (unmounting the ConsumerState)
        Navigator.of(tester.element(find.byType(POSCheckoutPage))).pop();
        await tester.pumpAndSettle();

        // POSCheckoutPage is unmounted, back to root page
        expect(find.byType(POSCheckoutPage), findsNothing);
        expect(find.text('Go to Checkout'), findsOneWidget);
        // SnackBar is still visible on root scaffold messenger
        expect(find.text('Hoàn tác'), findsOneWidget);

        // Tap Hoàn tác on the visible SnackBar
        await tester.tap(find.text('Hoàn tác'));
        await tester.pumpAndSettle();

        // Cart in container has productA restored!
        final cart = container.read(cartProvider);
        expect(cart.containsKey(productA.id), true);
        expect(cart[productA.id]!.quantity, 2);
      },
    );
  });
}
