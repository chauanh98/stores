import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_item_card.dart';

Widget _buildTestApp({required Widget child}) {
  return MaterialApp(
    home: Scaffold(
      body: child,
    ),
  );
}

void main() {
  group('StockInItemCard Widget Tests', () {
    const testItem = StockInReceiptItem(
      transactionId: 'TX_ITEM_01',
      productId: 'PROD_ST25',
      quantity: 2,
      unitPrice: 120000.0,
      originalPrice: 120000.0,
      productName: 'Gạo ST25 Thượng Hạng',
      productCode: 'ST25',
      imageUrl: null,
    );

    testWidgets('Renders product name, code, stock, unit price and line total in VND', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const StockInItemCard(
            item: testItem,
            currentStock: 15,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gạo ST25 Thượng Hạng'), findsOneWidget);
      expect(find.text('Mã: ST25 • Tồn kho: 15'), findsOneWidget);
      expect(find.text('Đơn giá: 120.000 đ'), findsOneWidget);
      expect(find.text('240.000 đ'), findsOneWidget); // 120,000 * 2
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('Stepper increment calls onQuantityChanged with quantity + 1', (tester) async {
      int? updatedQty;
      await tester.pumpWidget(
        _buildTestApp(
          child: StockInItemCard(
            item: testItem,
            currentStock: 15,
            onQuantityChanged: (qty) => updatedQty = qty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stepper_inc_PROD_ST25')));
      await tester.pumpAndSettle();

      expect(updatedQty, equals(3));
    });

    testWidgets('Stepper decrement calls onQuantityChanged with quantity - 1 when qty > 1', (tester) async {
      int? updatedQty;
      await tester.pumpWidget(
        _buildTestApp(
          child: StockInItemCard(
            item: testItem,
            currentStock: 15,
            onQuantityChanged: (qty) => updatedQty = qty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stepper_dec_PROD_ST25')));
      await tester.pumpAndSettle();

      expect(updatedQty, equals(1));
    });

    testWidgets('Stepper decrement when quantity is 1 triggers delete confirmation dialog', (tester) async {
      const singleItem = StockInReceiptItem(
        transactionId: 'TX_ITEM_SINGLE',
        productId: 'PROD_ST25',
        quantity: 1,
        unitPrice: 120000.0,
        productName: 'Gạo ST25 Thượng Hạng',
        productCode: 'ST25',
      );

      bool deleted = false;
      await tester.pumpWidget(
        _buildTestApp(
          child: StockInItemCard(
            item: singleItem,
            currentStock: 15,
            onDelete: () => deleted = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stepper_dec_PROD_ST25')));
      await tester.pumpAndSettle();

      // Confirmation dialog must appear
      expect(find.byKey(const Key('delete_confirmation_dialog')), findsOneWidget);
      expect(find.text('Xóa hàng hóa này khỏi phiếu nhập?'), findsOneWidget);
      expect(find.text('Bạn có chắc muốn xóa mặt hàng này khỏi phiếu nhập?'), findsOneWidget);

      // Confirm delete
      await tester.tap(find.byKey(const Key('btn_confirm_delete')));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });

    testWidgets('Swipe-to-delete reveals confirmation dialog; cancel retains item', (tester) async {
      bool deleted = false;
      await tester.pumpWidget(
        _buildTestApp(
          child: StockInItemCard(
            item: testItem,
            currentStock: 15,
            onDelete: () => deleted = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Swipe left on item card
      await tester.drag(find.byKey(const Key('item_card_PROD_ST25')), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_confirmation_dialog')), findsOneWidget);

      // Tap Cancel button
      await tester.tap(find.byKey(const Key('btn_cancel_delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_confirmation_dialog')), findsNothing);
      expect(deleted, isFalse);
    });

    testWidgets('Swipe-to-delete and confirming invokes onDelete callback', (tester) async {
      bool deleted = false;
      await tester.pumpWidget(
        _buildTestApp(
          child: StockInItemCard(
            item: testItem,
            currentStock: 15,
            onDelete: () => deleted = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Swipe left
      await tester.drag(find.byKey(const Key('item_card_PROD_ST25')), const Offset(-400, 0));
      await tester.pumpAndSettle();

      // Tap confirm delete
      await tester.tap(find.byKey(const Key('btn_confirm_delete')));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });

    testWidgets('Tapping item card triggers onTap callback to re-open edit sheet', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _buildTestApp(
          child: StockInItemCard(
            item: testItem,
            currentStock: 15,
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('item_card_PROD_ST25')));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('Masked mode replaces cost price and total with asterisks for staff', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const StockInItemCard(
            item: testItem,
            currentStock: 15,
            isMasked: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('***'), findsWidgets);
      expect(find.text('120.000 đ'), findsNothing);
      expect(find.text('240.000 đ'), findsNothing);
    });
  });
}
