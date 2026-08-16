# Firebase & Database Query Safety Rules

## 1. Core Rule: NEVER Fetch Unbounded Datasets

Assume tables and nodes have **tens of thousands of records**. Every query MUST be bounded.

### Firebase Realtime Database Query Rules

```dart
// ❌ FORBIDDEN - Loading the entire node
final snapshot = await database.ref('invoices').get();

// ✅ REQUIRED - Bounded with ordering and limits
final snapshot = await database.ref('invoices')
  .orderByChild('timestamp')
  .limitToLast(50)
  .get();
```

---

## 2. Server-Side vs Client-Side Filtering
Always perform filtering at the query level whenever possible.

```dart
// ❌ FORBIDDEN - Fetching all then filtering in Dart
final allProducts = await database.ref('products').get();
final activeProducts = allProducts.children.where((c) => c.child('status').value == 'active');

// ✅ REQUIRED - Query by index/status or specific sub-node
final activeSnapshot = await database.ref('products')
  .orderByChild('status')
  .equalTo('active')
  .limitToFirst(50)
  .get();
```

---

## 3. Realtime Stream Cleanliness
When subscribing to streams (`.onValue`, `.onChildAdded`), **ALWAYS** manage subscription lifecycles to avoid leaks:

```dart
// ✅ In StateNotifier or AsyncNotifier
class LiveOrdersNotifier extends AutoDisposeStreamNotifier<List<Order>> {
  @override
  Stream<List<Order>> build() {
    final ref = FirebaseDatabase.instance.ref('live_orders');
    return ref.limitToLast(20).onValue.map((event) {
      // transform to domain models
      return parseOrders(event.snapshot);
    });
  }
}
```
*Because `AutoDisposeStreamNotifier` is used, Riverpod automatically cancels the Realtime Database listener when the screen is closed.*

---

## 4. Atomic Updates and Transactions
When modifying balances, stock quantities, or invoice counters, **never** read-then-write directly. Use Firebase Transactions:

```dart
// ✅ REQUIRED for stock count decrement
final stockRef = database.ref('products/$productId/stock');
await stockRef.runTransaction((mutableData) {
  final currentStock = (mutableData as int?) ?? 0;
  if (currentStock < requestedQuantity) {
    return Transaction.abort();
  }
  return Transaction.success(currentStock - requestedQuantity);
});
```
