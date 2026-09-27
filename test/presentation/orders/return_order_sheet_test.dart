import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/orders/usecases/process_return_order_usecase.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/orders/widgets/return_order_bottom_sheet.dart';

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

class _MockProcessReturnOrderUseCase implements ProcessReturnOrderUseCase {
  Order? capturedOriginalOrder;
  List<ReturnOrderItem>? capturedReturnItems;
  String? capturedStoreId;
  UserAccount? capturedUser;
  String? capturedReason;
  String? capturedRefundMethod;
  int executionCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<ProcessReturnOrderResult> execute({
    required Order originalOrder,
    required List<ReturnOrderItem> returnItems,
    required String storeId,
    required UserAccount currentUser,
    String? reason,
    String refundPaymentMethod = 'cash',
  }) async {
    executionCount++;
    capturedOriginalOrder = originalOrder;
    capturedReturnItems = returnItems;
    capturedStoreId = storeId;
    capturedUser = currentUser;
    capturedReason = reason;
    capturedRefundMethod = refundPaymentMethod;

    final totalReturn =
        returnItems.fold<double>(0.0, (sum, i) => sum + (i.price * i.quantity));
    final debtDeducted = totalReturn > originalOrder.remainingDebt
        ? originalOrder.remainingDebt
        : totalReturn;
    final cashRefunded = totalReturn - debtDeducted;

    final returnOrder = ReturnOrder(
      id: 'RET_001',
      orderId: originalOrder.id,
      customerId: originalOrder.customerId,
      storeId: storeId,
      createdAt: DateTime.now(),
      items: returnItems,
      totalReturnAmount: totalReturn,
      debtDeducted: debtDeducted,
      cashRefunded: cashRefunded,
      reason: reason,
      createdBy: currentUser.username,
      createdByName: currentUser.name,
      refundPaymentMethod: refundPaymentMethod,
    );

    return ProcessReturnOrderResult(
      returnOrder: returnOrder,
      updatedOrder: originalOrder,
      totalRefund: totalReturn,
      debtDeducted: debtDeducted,
      cashRefunded: cashRefunded,
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
    username: 'staff_01',
    displayName: 'Nhân viên 01',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const customer = Customer(
    id: 'cust_001',
    name: 'Khách hàng Trả Hàng',
    phone: '0988888888',
    email: '',
    address: '',
    purchases: [],
  );

  final sampleOrder = Order(
    id: 'HD000777',
    customerId: 'cust_001',
    createdAt: DateTime.now(),
    items: [
      OrderItem(
        productId: 'prod_case',
        productName: 'Ốp lưng Silicon',
        quantity: 3,
        returnedQuantity: 1,
        // 1 already returned, 2 active
        price: 200000.0,
        warrantyMonths: 0,
        purchaseDate: DateTime.now(),
      ),
      OrderItem(
        productId: 'prod_cable',
        productName: 'Cáp sạc Type-C Braided',
        quantity: 2,
        returnedQuantity: 0,
        // 2 active
        price: 300000.0,
        warrantyMonths: 6,
        purchaseDate: DateTime.now(),
      ),
    ],
    total: 1000000.0,
    // (2*200k + 2*300k) = 1.000.000
    amountPaid: 600000.0,
    // 400.000 remaining debt
    debtAmount: 400000.0,
    status: 'completed',
    paymentMethod: 'cash',
    createdBy: 'staff_01',
    createdByName: 'Nhân viên 01',
  );

  group('ReturnOrderBottomSheet Widget & Financial Preview Tests (R1)', () {
    testWidgets(
        'Renders item quantities, already returned badge, and initial summary',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: ReturnOrderBottomSheet(order: sampleOrder, customer: customer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Title & Items
      expect(find.text('Trả hàng - Hóa đơn HD000777'), findsOneWidget);
      expect(find.text('Ốp lưng Silicon'), findsOneWidget);
      expect(find.text('Cáp sạc Type-C Braided'), findsOneWidget);

      // Already returned badge for product 1
      expect(find.text('Đã trả: 1'), findsOneWidget);

      // Stepper current state: 0 / 2 for both products
      expect(find.text('0 / 2'), findsNWidgets(2));

      // Initial submit button disabled / shows prompt
      expect(find.text('Chọn sản phẩm để trả hàng'), findsOneWidget);
    });

    testWidgets(
        'Stepping quantity updates real-time financial calculations (Refund vs Debt deduction)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: ReturnOrderBottomSheet(order: sampleOrder, customer: customer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap '+' on Ốp lưng Silicon (qty: 1 -> return amount: 200.000đ)
      // Since order has 400.000 remaining debt:
      // totalReturn = 200.000
      // debtDeduction = 200.000
      // cashRefund = 0đ
      final incCaseBtn = find.byKey(const Key('increment_return_prod_case'));
      await tester.tap(incCaseBtn);
      await tester.pumpAndSettle();

      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('200.000 đ'), findsWidgets); // Total return amount
      expect(find.text('-200.000 đ'), findsOneWidget); // Debt deduction
      expect(find.text('0 đ'), findsOneWidget); // Cash refund

      // Tap '+' on Cáp sạc Type-C Braided 2 times (2 * 300.000 = 600.000đ)
      // totalReturn = 200.000 + 600.000 = 800.000đ
      // remainingDebt = 400.000đ
      // debtDeduction = min(800k, 400k) = 400.000đ
      // cashRefund = 800k - 400k = 400.000đ
      final incCableBtn = find.byKey(const Key('increment_return_prod_cable'));
      await tester.tap(incCableBtn);
      await tester.pumpAndSettle();
      await tester.tap(incCableBtn);
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('800.000 đ'), findsOneWidget); // Total return
      expect(find.text('-400.000 đ'), findsOneWidget); // Debt deduction
      expect(find.text('400.000 đ'), findsOneWidget); // Cash refund

      // Button updates to reflect total items count (1 + 2 = 3)
      expect(find.text('Xác nhận trả hàng (3 sản phẩm)'), findsOneWidget);
    });

    testWidgets(
        'Select all toggle selects all active items at max available quantities',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: ReturnOrderBottomSheet(order: sampleOrder, customer: customer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Chọn trả tất cả"
      await tester.tap(find.text('Chọn trả tất cả'));
      await tester.pumpAndSettle();

      // Both products should be at 2/2
      expect(find.text('2 / 2'), findsNWidgets(2));
      // Total return items: 2 + 2 = 4
      expect(find.text('Xác nhận trả hàng (4 sản phẩm)'), findsOneWidget);

      // Toggle changes to "Bỏ chọn tất cả"
      expect(find.text('Bỏ chọn tất cả'), findsOneWidget);

      // Tap "Bỏ chọn tất cả"
      await tester.tap(find.text('Bỏ chọn tất cả'));
      await tester.pumpAndSettle();

      expect(find.text('0 / 2'), findsNWidgets(2));
      expect(find.text('Chọn sản phẩm để trả hàng'), findsOneWidget);
    });

    testWidgets(
        'Submitting return invokes processReturnOrderUseCaseProvider with correct items and data',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockUseCase = _MockProcessReturnOrderUseCase();

      await tester.pumpWidget(
        _buildTestApp(
          child: ReturnOrderBottomSheet(order: sampleOrder, customer: customer),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            processReturnOrderUseCaseProvider.overrideWithValue(mockUseCase),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select 1 case and 1 cable
      await tester.tap(find.byKey(const Key('increment_return_prod_case')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('increment_return_prod_cable')));
      await tester.pumpAndSettle();

      // Enter return reason
      final reasonField = find.byKey(const Key('return_order_reason_field'));
      await tester.enterText(reasonField, 'Sản phẩm không vừa cỡ máy');
      await tester.pumpAndSettle();

      // Select transfer refund method if available
      final transferChip = find.widgetWithText(ChoiceChip, 'Chuyển khoản');
      if (transferChip.evaluate().isNotEmpty) {
        await tester.tap(transferChip);
        await tester.pumpAndSettle();
      }

      // Submit return
      final confirmBtn = find.byKey(const Key('confirm_return_order_button'));
      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Verify use case execution
      expect(mockUseCase.executionCount, 1);
      expect(mockUseCase.capturedOriginalOrder?.id, 'HD000777');
      expect(mockUseCase.capturedUser?.username, 'staff_01');
      expect(mockUseCase.capturedReason, 'Sản phẩm không vừa cỡ máy');
      expect(mockUseCase.capturedReturnItems?.length, 2);
      expect(mockUseCase.capturedReturnItems?[0].productId, 'prod_case');
      expect(mockUseCase.capturedReturnItems?[0].quantity, 1);
      expect(mockUseCase.capturedReturnItems?[1].productId, 'prod_cable');
      expect(mockUseCase.capturedReturnItems?[1].quantity, 1);
    });
  });
}
