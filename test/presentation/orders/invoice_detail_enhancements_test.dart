import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';

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
  Future<List<Customer>> build() async => _initialCustomers;

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialCustomers);
  }
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: child,
    ),
  );
}

void main() {
  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const customerVIP = Customer(
    id: 'cust_001',
    name: 'Nguyễn Văn A',
    phone: '0901234567',
    email: 'a@example.com',
    address: 'Hà Nội',
    purchases: [],
  );

  final testProducts = [
    const Product(
      id: 'prod_001',
      name: 'Nệm Cao Su Thiên Nhiên',
      code: 'NCS01',
      price: 5000000.0,
      costPrice: 3500000.0,
      branchStocks: {'store_001': 10},
      category: 'Nệm',
    ),
    const Product(
      id: 'prod_002',
      name: 'Gối Foam Công Thái Học',
      code: 'GCTH01',
      price: 800000.0,
      costPrice: 400000.0,
      branchStocks: {'store_001': 15},
      category: 'Gối',
    ),
  ];

  final testOrderWithDiscountsAndNotes = Order(
    id: 'HD013259',
    customerId: 'cust_001',
    createdAt: DateTime(2026, 10, 4, 10, 30),
    items: [
      // Product 1: Has discount (originalPrice = 5.000.000, price = 4.500.000) & item note
      OrderItem(
        productId: 'prod_001',
        productName: 'Nệm Cao Su Thiên Nhiên',
        quantity: 2,
        price: 4500000.0, // Đơn giá sau giảm
        originalPrice: 5000000.0, // Giá gốc trước giảm
        discount: 500000.0,
        isDiscountPercent: false,
        note: 'Giao hàng tận phòng tầng 3',
        warrantyMonths: 24,
        purchaseDate: DateTime(2026, 10, 4),
      ),
      // Product 2: Standard price without discount, with note
      OrderItem(
        productId: 'prod_002',
        productName: 'Gối Foam Công Thái Học',
        quantity: 1,
        price: 800000.0,
        originalPrice: 800000.0,
        discount: 0.0,
        note: 'Tặng kèm áo gối màu xám',
        warrantyMonths: 12,
        purchaseDate: DateTime(2026, 10, 4),
      ),
    ],
    total: 10800000.0, // 5.000.000 x 2 + 800.000 = 10.800.000
    discount: 1000000.0,
    amountPaid: 9800000.0,
    debtAmount: 0.0,
    status: 'completed',
    paymentMethod: 'cash',
    storeId: 'store_001',
    note: 'Đơn hàng VIP khách quen',
  );

  testWidgets(
      'Invoice details bottom sheet displays customer phone and copies to clipboard with SnackBar',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // Mock clipboard
    String? clipboardContent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        clipboardContent = (methodCall.arguments as Map)['text'];
        return null;
      } else if (methodCall.method == 'Clipboard.getData') {
        return {'text': clipboardContent};
      }
      return null;
    });

    await tester.pumpWidget(
      _buildTestApp(
        child: const InvoicesPage(),
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
          productListProvider.overrideWith((ref) => Stream.value(testProducts)),
          allBranchesOrdersByDateRangeProvider
              .overrideWith((ref, range) => Stream.value([testOrderWithDiscountsAndNotes])),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier([customerVIP])),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Tap on invoice card to open Invoice Details Bottom Sheet
    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();

    // 1. Verify customer phone is displayed
    expect(find.text('Số điện thoại'), findsOneWidget);
    expect(find.text('0901234567'), findsOneWidget);

    // 2. Verify copy button exists and tapping it copies to clipboard & shows SnackBar
    final copyPhoneBtn = find.byKey(const Key('copy_customer_phone_button'));
    expect(copyPhoneBtn, findsOneWidget);

    await tester.tap(copyPhoneBtn);
    await tester.pump(); // Start SnackBar animation
    await tester.pump(const Duration(milliseconds: 300));

    expect(clipboardContent, '0901234567');
    expect(find.text('Đã sao chép số điện thoại'), findsOneWidget);
  });

  testWidgets(
      'Invoice details bottom sheet displays item.note under product name and handles price before/after discount',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      _buildTestApp(
        child: const InvoicesPage(),
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
          productListProvider.overrideWith((ref) => Stream.value(testProducts)),
          allBranchesOrdersByDateRangeProvider
              .overrideWith((ref, range) => Stream.value([testOrderWithDiscountsAndNotes])),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier([customerVIP])),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Open details bottom sheet
    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();

    // 1. Verify item notes are rendered under each product name
    expect(find.text('Giao hàng tận phòng tầng 3'), findsOneWidget);
    expect(find.text('Tặng kèm áo gối màu xám'), findsOneWidget);

    // 2. Verify product 1: Original price 5.000.000 đ with line-through decoration
    final lineThroughWidget = tester.widget<Text>(find.byWidgetPredicate(
      (w) => w is Text && w.style?.decoration == TextDecoration.lineThrough,
    ));
    expect(lineThroughWidget.data, contains('5.000.000 đ'));

    // Verify discounted unit price 4.500.000 đ is displayed next to it
    expect(find.text('4.500.000 đ'), findsOneWidget);

    // Verify line total = unit discounted price * quantity = 4.500.000 * 2 = 9.000.000 đ
    expect(find.text('9.000.000 đ'), findsOneWidget);

    // 3. Verify product 2 without discount displays regular unit price
    expect(find.text('1 x 800.000 đ'), findsOneWidget);
    expect(find.text('800.000 đ'), findsOneWidget); // Line total

    // 4. Verify "Sửa hóa đơn" button exists
    expect(find.byKey(const Key('edit_invoice_action_button')), findsOneWidget);
    expect(find.text('Sửa hóa đơn'), findsOneWidget);
  });

  testWidgets(
      'Adversarial: Walk-in customer with order.customerPhone displays phone row, and multiline note renders in full without truncation',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final walkInOrder = Order(
      id: 'HD099999',
      customerId: 'khach_le',
      customerName: 'Khách lẻ',
      customerPhone: '0977889900',
      createdAt: DateTime(2026, 10, 4, 14, 0),
      items: [
        OrderItem(
          productId: 'prod_001',
          productName: 'Nệm Cao Su Thiên Nhiên',
          quantity: 1,
          price: 5000000.0,
          originalPrice: 5000000.0,
          discount: 0.0,
          note: 'Dòng 1: Giao hỏa tốc\nDòng 2: Gọi trước khi đến 15 phút\nDòng 3: Mang lên tầng 4',
          warrantyMonths: 24,
          purchaseDate: DateTime(2026, 10, 4),
        ),
      ],
      total: 5000000.0,
      discount: 0.0,
      amountPaid: 5000000.0,
      debtAmount: 0.0,
      status: 'completed',
      paymentMethod: 'cash',
      storeId: 'store_001',
    );

    await tester.pumpWidget(
      _buildTestApp(
        child: const InvoicesPage(),
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
          productListProvider.overrideWith((ref) => Stream.value(testProducts)),
          allBranchesOrdersByDateRangeProvider
              .overrideWith((ref, range) => Stream.value([walkInOrder])),
          customerListNotifierProvider.overrideWith(
              () => _FakeCustomerListNotifier([])),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Tap invoice to open bottom sheet
    await tester.tap(find.text('Khách lẻ'));
    await tester.pumpAndSettle();

    // 1. Verify customer phone from order is displayed even for walk-in customer
    expect(find.text('0977889900'), findsOneWidget);
    expect(find.byKey(const Key('copy_customer_phone_button')), findsOneWidget);

    // 2. Verify multiline note is rendered without maxLines constraint
    final noteFinder = find.text(
        'Dòng 1: Giao hỏa tốc\nDòng 2: Gọi trước khi đến 15 phút\nDòng 3: Mang lên tầng 4');
    expect(noteFinder, findsOneWidget);
    final noteWidget = tester.widget<Text>(noteFinder);
    expect(noteWidget.maxLines, isNull);
  });
}
