# Riverpod 2.x Architecture & Best Practice Rules

## 1. Provider Declaration Standards
- **Always use `autoDispose`** for providers scoped to a specific screen or flow:
  ```dart
  // ✅ REQUIRED for Screen/Form states
  final productDetailProvider = AutoDisposeAsyncNotifierProvider<ProductDetailNotifier, ProductDetailState>(
    ProductDetailNotifier.new,
  );
  ```
- Keep global providers (like `authRepositoryProvider`, `currentSessionProvider`) long-lived without `autoDispose` only if they represent app-wide state.

---

## 2. Reading vs Watching Providers in Widgets
- **`ref.watch()`**: Use strictly inside `build()` method to reactively trigger rebuilds when state changes.
  ```dart
  // ✅ In build(BuildContext context, WidgetRef ref)
  final productState = ref.watch(productDetailProvider);
  ```
- **`ref.read()`**: Use inside button `onPressed`, callbacks, or lifecycle handlers where you need a one-time value or call a notifier method.
  ```dart
  // ✅ In button callback
  ElevatedButton(
    onPressed: () => ref.read(productDetailProvider.notifier).saveProduct(),
    child: const Text('Save'),
  )
  ```
- **`ref.listen()`**: Use inside `build()` to handle side-effects like showing SnackBars, Dialogs, or triggering Navigation:
  ```dart
  ref.listen<AsyncValue<void>>(
    productDetailProvider.select((s) => s.actionState),
    (previous, next) {
      next.whenOrNull(
        error: (err, stack) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err.toString())),
        ),
      );
    },
  );
  ```

---

## 3. Handling Async States with AsyncValue
Never store multiple boolean flags (`isLoading`, `hasError`, `isSuccess`) in your state. Always encapsulate with `AsyncValue<T>` or Freezed Union:

```dart
// ❌ FORBIDDEN
class ScreenState {
  final bool isLoading;
  final bool isError;
  final Data? data;
}

// ✅ REQUIRED
class ProductDetailNotifier extends AutoDisposeAsyncNotifier<Product> {
  @override
  Future<Product> build() async {
    return ref.read(productRepositoryProvider).fetchProduct();
  }

  Future<void> updatePrice(double newPrice) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final updated = await ref.read(productRepositoryProvider).updatePrice(newPrice);
      return updated;
    });
  }
}
```

In the UI:
```dart
return productState.when(
  data: (product) => ProductContent(product: product),
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (error, stack) => ErrorView(message: error.toString()),
);
```

---

## 4. Avoiding Unnecessary Rebuilds with `select`
When a widget only depends on a small property of a large state object, use `select`:
```dart
// ✅ Rebuilds ONLY when `title` changes, ignoring other fields
final productTitle = ref.watch(
  productDetailProvider.select((state) => state.valueOrNull?.title ?? ''),
);
```
