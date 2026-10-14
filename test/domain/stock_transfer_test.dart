import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/usecases/stock_transfer_use_cases.dart';
import 'package:stores/domain/entities/notification_type.dart';
import 'package:stores/domain/entities/stock_transfer.dart';

void main() {
  StockTransfer build(int received, StockTransferStatus s) => StockTransfer(
        id: 'a',
        code: 'TRF000001',
        status: s,
        sourceStoreId: 'store_001',
        sourceStoreName: 'A',
        targetStoreId: 'store_002',
        targetStoreName: 'B',
        createdAt: DateTime(2026, 1, 1),
        items: [
          StockTransferItem(
              productId: 'p',
              name: 'xyz',
              code: 'X',
              unitPrice: 100,
              quantity: 2,
              receivedQuantity: received),
        ],
      );

  test('partial receive: 2 sent, 1 received', () {
    final t = build(1, StockTransferStatus.received);
    expect(t.receivedSummary, '1/2');
    expect(t.totalValue, 200);
    expect(t.totalReceivedValue, 100);
  });

  test('map round trip + in-transit shows 0/N', () {
    final t =
        StockTransfer.fromMap(build(0, StockTransferStatus.inTransit).toMap());
    expect(t.isInTransit, true);
    expect(t.receivedSummary, '0/2');
  });

  test('applyStoreStock syncs aliases', () {
    final m = applyStoreStock({'store_002': 5}, 'store_001', 3);
    expect(m['store_001'], 3);
    expect(m['branch_1'], 3);
    expect(m['store_002'], 5);
  });

  test('notification type parses stock_transfer', () {
    expect(NotificationType.fromString('stock_transfer'),
        NotificationType.stockTransfer);
  });
}
