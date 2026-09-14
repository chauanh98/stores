import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/orders/usecases/collect_invoice_debt_usecase.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/orders/widgets/debt_collection_dialog.dart';

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

class _MockCollectInvoiceDebtUseCase implements CollectInvoiceDebtUseCase {
  Order? capturedOrder;
  double? capturedAmount;
  String? capturedPaymentMethod;
  UserAccount? capturedUser;
  String? capturedNote;
  int executionCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Order> execute({
    required Order order,
    required double amount,
    required String paymentMethod,
    required UserAccount currentUser,
    String? note,
  }) async {
    executionCount++;
    capturedOrder = order;
    capturedAmount = amount;
    capturedPaymentMethod = paymentMethod;
    capturedUser = currentUser;
    capturedNote = note;

    final newPaid = order.amountPaid + amount;
    final newDebt = (order.debtAmount - amount).clamp(0.0, double.infinity);
    return order.copyWith(
      amountPaid: newPaid,
      debtAmount: newDebt,
    );
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
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  const staffUser = UserAccount(
    username: 'cashier_01',
    displayName: 'Thu ngân 01',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const customerWithDebt = Customer(
    id: 'cust_debt_01',
    name: 'Trần Văn Nam',
    phone: '0912345678',
    email: 'nam@example.com',
    address: 'Hà Nội',
    purchases: [],
    currentDebt: 1500000.0,
  );

  final orderWithDebt = Order(
    id: 'HD000123',
    customerId: 'cust_debt_01',
    createdAt: DateTime.now(),
    items: [
      OrderItem(
        productId: 'p_keyboard',
        productName: 'Bàn phím cơ không dây',
        quantity: 1,
        price: 2500000.0,
        warrantyMonths: 12,
        purchaseDate: DateTime.now(),
      )
    ],
    total: 2500000.0,
    amountPaid: 1000000.0,
    debtAmount: 1500000.0,
    status: 'completed',
    paymentMethod: 'cash',
    createdBy: 'cashier_01',
    createdByName: 'Thu ngân 01',
  );

  group('DebtCollectionDialog Widget & Logic Tests (R3)', () {
    testWidgets('Displays customer info, invoice financial breakdown and prefilled remaining debt',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: DebtCollectionDialog(
            order: orderWithDebt,
            customer: customerWithDebt,
            remainingDebt: orderWithDebt.remainingDebt,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Title & Customer Info
      expect(find.text('Thu nợ - Hóa đơn HD000123'), findsOneWidget);
      expect(find.text('Trần Văn Nam'), findsOneWidget);
      expect(find.text('(0912345678)'), findsOneWidget);

      // Financial breakdown
      expect(find.text('2.500.000 đ'), findsOneWidget); // Total HĐ
      expect(find.text('1.000.000 đ'), findsOneWidget); // Already paid
      expect(find.text('1.500.000 đ'), findsWidgets); // Remaining debt

      // Pre-filled amount input field
      final amountField = find.byKey(const Key('debt_collection_amount_field'));
      expect(amountField, findsOneWidget);
      expect(find.text('1.500.000'), findsOneWidget);
    });

    testWidgets('Validates input amount: rejects 0 and amounts exceeding remaining debt',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockUseCase = _MockCollectInvoiceDebtUseCase();

      await tester.pumpWidget(
        _buildTestApp(
          child: DebtCollectionDialog(
            order: orderWithDebt,
            customer: customerWithDebt,
            remainingDebt: orderWithDebt.remainingDebt,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            collectInvoiceDebtUseCaseProvider.overrideWithValue(mockUseCase),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final amountField = find.byKey(const Key('debt_collection_amount_field'));
      final confirmBtn = find.byKey(const Key('confirm_debt_collection_button'));

      // Enter 0
      await tester.enterText(amountField, '0');
      await tester.pumpAndSettle();

      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(find.text('Số tiền phải lớn hơn 0'), findsOneWidget);
      expect(mockUseCase.executionCount, 0);

      // Enter amount greater than remaining debt (e.g. 2.000.000 > 1.500.000)
      await tester.enterText(amountField, '2000000');
      await tester.pumpAndSettle();

      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(find.text('Vượt quá số nợ còn lại'), findsOneWidget);
      expect(mockUseCase.executionCount, 0);
    });

    testWidgets('Supports partial collection and payment method selection',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockUseCase = _MockCollectInvoiceDebtUseCase();

      await tester.pumpWidget(
        _buildTestApp(
          child: DebtCollectionDialog(
            order: orderWithDebt,
            customer: customerWithDebt,
            remainingDebt: orderWithDebt.remainingDebt,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            collectInvoiceDebtUseCaseProvider.overrideWithValue(mockUseCase),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Enter partial amount: 500.000đ
      final amountField = find.byKey(const Key('debt_collection_amount_field'));
      await tester.enterText(amountField, '500000');
      await tester.pumpAndSettle();

      // Select 'Chuyển khoản' payment method
      await tester.tap(find.text('Chuyển khoản'));
      await tester.pumpAndSettle();

      // Enter custom note
      final noteField = find.byKey(const Key('debt_collection_note_field'));
      await tester.enterText(noteField, 'Khách chuyển khoản cọc đợt 2 qua VietQR');
      await tester.pumpAndSettle();

      // Confirm
      final confirmBtn = find.byKey(const Key('confirm_debt_collection_button'));
      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Verify use case parameters
      expect(mockUseCase.executionCount, 1);
      expect(mockUseCase.capturedAmount, 500000.0);
      expect(mockUseCase.capturedPaymentMethod, 'transfer');
      expect(mockUseCase.capturedNote, 'Khách chuyển khoản cọc đợt 2 qua VietQR');
      expect(mockUseCase.capturedUser?.username, 'cashier_01');
      expect(mockUseCase.capturedOrder?.id, 'HD000123');
    });

    testWidgets('Quick button resets collection amount to full remaining debt',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: DebtCollectionDialog(
            order: orderWithDebt,
            customer: customerWithDebt,
            remainingDebt: orderWithDebt.remainingDebt,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final amountField = find.byKey(const Key('debt_collection_amount_field'));

      // Change amount to 100k
      await tester.enterText(amountField, '100000');
      await tester.pumpAndSettle();
      expect(find.text('100.000'), findsOneWidget);

      // Tap 'Thu toàn bộ nợ'
      await tester.tap(find.text('Thu toàn bộ nợ'));
      await tester.pumpAndSettle();

      // Reset to 1.500.000
      expect(find.text('1.500.000'), findsOneWidget);
    });
  });
}
