import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';

void main() {
  group('CartItem Discount and Note Tests', () {
    const sampleProduct = Product(
      id: 'p_01',
      name: 'Bàn ăn cao cấp',
      code: 'BA01',
      price: 1000000.0,
      costPrice: 700000.0,
      branchStocks: {'store_001': 10},
      category: 'Bàn ghế',
    );

    test('Default CartItem has zero discount and null note', () {
      const item = CartItem(product: sampleProduct, quantity: 2);
      expect(item.discount, 0.0);
      expect(item.isDiscountPercent, false);
      expect(item.note, isNull);
      expect(item.unitDiscountAmount, 0.0);
      expect(item.effectivePrice, 1000000.0);
      expect(item.total, 2000000.0);
      expect(item.totalDiscount, 0.0);
    });

    test('CartItem calculates direct cash discount correctly', () {
      final item = const CartItem(product: sampleProduct, quantity: 2)
          .copyWith(discount: 50000.0, isDiscountPercent: false, note: 'Tặng kèm lót');
      
      expect(item.unitDiscountAmount, 50000.0);
      expect(item.effectivePrice, 950000.0);
      expect(item.total, 1900000.0);
      expect(item.totalDiscount, 100000.0);
      expect(item.note, 'Tặng kèm lót');
    });

    test('CartItem calculates percent discount correctly', () {
      final item = const CartItem(product: sampleProduct, quantity: 3)
          .copyWith(discount: 10.0, isDiscountPercent: true, note: 'Giảm 10% khai trương');
      
      expect(item.unitDiscountAmount, 100000.0);
      expect(item.effectivePrice, 900000.0);
      expect(item.total, 2700000.0);
      expect(item.totalDiscount, 300000.0);
    });

    test('OrderItem calculations with discount and notes', () {
      final now = DateTime.now();
      final orderItem = OrderItem(
        productId: sampleProduct.id,
        productName: sampleProduct.name,
        quantity: 2,
        price: 900000.0, // effective price
        originalPrice: 1000000.0,
        discount: 10.0,
        isDiscountPercent: true,
        note: 'Giao sau 18h',
        warrantyMonths: 12,
        purchaseDate: now,
      );

      expect(orderItem.effectiveOriginalPrice, 1000000.0);
      expect(orderItem.totalDiscountAmount, 200000.0);
      expect(orderItem.lineTotal, 1800000.0);
      expect(orderItem.note, 'Giao sau 18h');
    });

    test('populateCart accurately preserves effectivePrice when originalPrice > price and discount is 0', () {
      final multiNotifier = MultiCartNotifier();
      final now = DateTime.now();

      final itemWithImplicitDiscount = OrderItem(
        productId: sampleProduct.id,
        productName: sampleProduct.name,
        quantity: 2,
        price: 800000.0, // Sold at 800k
        originalPrice: 1000000.0, // Catalog price was 1000k
        discount: 0.0, // No explicit discount field
        isDiscountPercent: false,
        note: 'Giá ưu đãi khách quen',
        warrantyMonths: 12,
        purchaseDate: now,
      );

      multiNotifier.populateCart(
        [itemWithImplicitDiscount],
        [sampleProduct],
        orderId: 'HD001.01',
      );

      final loadedItem = multiNotifier.state.activeTab.items[sampleProduct.id]!;
      expect(loadedItem.price, 1000000.0); // Base price
      expect(loadedItem.discount, 200000.0); // Computed implicit discount
      expect(loadedItem.isDiscountPercent, false);
      expect(loadedItem.effectivePrice, 800000.0); // Exactly matches sold price!
      expect(loadedItem.total, 1600000.0);
      expect(loadedItem.note, 'Giá ưu đãi khách quen');
    });

    test('populateCart accurately handles 100% discount gift items with catalog fallback', () {
      final multiNotifier = MultiCartNotifier();
      final now = DateTime.now();

      final freeGiftItem = OrderItem(
        productId: sampleProduct.id,
        productName: sampleProduct.name,
        quantity: 1,
        price: 0.0, // Free
        originalPrice: 0.0,
        discount: 100.0, // 100% discount
        isDiscountPercent: true,
        note: 'Quà tặng',
        warrantyMonths: 12,
        purchaseDate: now,
      );

      multiNotifier.populateCart(
        [freeGiftItem],
        [sampleProduct],
        orderId: 'HD002.01',
      );

      final loadedItem = multiNotifier.state.activeTab.items[sampleProduct.id]!;
      expect(loadedItem.price, 1000000.0); // Fallback to catalog price
      expect(loadedItem.discount, 100.0);
      expect(loadedItem.isDiscountPercent, true);
      expect(loadedItem.effectivePrice, 0.0);
      expect(loadedItem.total, 0.0);
      expect(loadedItem.note, 'Quà tặng');
    });
  });
}
