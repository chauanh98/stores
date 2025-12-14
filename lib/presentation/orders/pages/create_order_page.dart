import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/presentation/common/widgets/error_view.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../application/inventory/inventory_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/order_item.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/purchase.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/entities/warranty.dart';

class CreateOrderPage extends ConsumerStatefulWidget {
  final String? selectedCustomerId;

  const CreateOrderPage({super.key, this.selectedCustomerId});

  @override
  ConsumerState<CreateOrderPage> createState() => _CreateOrderPageState();
}

class _CreateOrderPageState extends ConsumerState<CreateOrderPage> {
  final List<_LineItem> _items = [_LineItem()];
  bool _saving = false;

  static const warrantyOptions = [6, 12, 18, 24];

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customerListNotifierProvider);
    final productsAsync = ref.watch(productListProvider);
    final l10n = AppLocalizations.of(context)!;

    final total = _calcTotal(productsAsync.asData?.value ?? []);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.createOrder),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saving ? null : () => _save(total),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: customersAsync.when(
                  data: (customers) {
                    final customer = customers.firstWhere(
                      (c) => c.id == widget.selectedCustomerId,
                      orElse: () => Customer(
                        id: '',
                        name: l10n.notFound,
                        phone: '',
                        email: '',
                        address: '',
                        purchases: [],
                      ),
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.customers,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.person,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customer.name,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  Text(
                                    '${customer.phone} • ${customer.email}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                  loading: () => const SizedBox(
                      height: 48,
                      child: LoadingIndicator()),
                  error: (e, _) => ErrorView(e),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Items với Autocomplete
            productsAsync.when(
              data: (products) => Column(
                children: [
                  ..._items.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    final product = products.firstWhere(
                      (p) => p.id == item.productId,
                      orElse: () => products.isNotEmpty
                          ? products.first
                          : null as Product,
                    );

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _ProductAutocomplete(
                              products: products,
                              selectedProductId: item.productId,
                              onProductSelected: (productId) => setState(() {
                                item.productId = productId;
                              }),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: item.quantity.toString(),
                                    decoration: InputDecoration(
                                      labelText: l10n.quantity,
                                      border: const OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) => setState(() {
                                      item.quantity = int.tryParse(v) ?? 1;
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: item.warrantyMonths,
                                    decoration: InputDecoration(
                                      labelText:
                                          '${l10n.warranty} (${l10n.months})',
                                      border: const OutlineInputBorder(),
                                    ),
                                    items: warrantyOptions
                                        .map((m) => DropdownMenuItem(
                                            value: m,
                                            child: Text('$m ${l10n.months}')))
                                        .toList(),
                                    onChanged: (v) => setState(() {
                                      item.warrantyMonths = v ?? 12;
                                    }),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Đơn giá và thành tiền
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    enabled: false,
                                    decoration: InputDecoration(
                                      labelText: l10n.unitPrice,
                                      border: const OutlineInputBorder(),
                                    ),
                                    controller: TextEditingController(
                                      text: product == null
                                          ? ''
                                          : NumberFormat.currency(
                                                  locale: 'vi_VN', symbol: 'đ')
                                              .format(product.price),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    enabled: false,
                                    decoration: InputDecoration(
                                      labelText: l10n.amount,
                                      border: const OutlineInputBorder(),
                                    ),
                                    controller: TextEditingController(
                                      text: product == null
                                          ? '—'
                                          : NumberFormat.currency(
                                                  locale: "vi_VN", symbol: "đ")
                                              .format(product.price *
                                                  item.quantity),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            if (_items.length > 1)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _items.removeAt(idx)),
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  label: Text(l10n.delete,
                                      style:
                                          const TextStyle(color: Colors.red)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _items.add(_LineItem())),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.addProduct),
                  ),
                ],
              ),
              loading: () => const SizedBox(
                  height: 120,
                  child: LoadingIndicator()),
              error: (e, _) => ErrorView(e),
            ),

            const SizedBox(height: 12),

            // Total
            Card(
              child: ListTile(
                title: Text(l10n.totalAmount),
                trailing: Text(
                  NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                      .format(total),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _calcTotal(List<Product> products) {
    double s = 0;
    for (final i in _items) {
      final p = products.firstWhere((e) => e.id == i.productId,
          orElse: () => const Product(
                id: '',
                name: '',
                brand: '',
                model: '',
                price: 0,
                stock: 0,
                category: '',
              ));
      s += (p.price) * i.quantity;
    }
    return s;
  }

  Future<void> _save(double total) async {
    final l10n = AppLocalizations.of(context)!;

    if (widget.selectedCustomerId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.noCustomerSelected)));
      return;
    }

    final products = ref
        .read(productListProvider)
        .maybeWhen(data: (v) => v, orElse: () => <Product>[]);
    if (products.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.noProducts)));
      return;
    }

    for (final i in _items) {
      if (i.productId == null || i.quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.checkProductsAndQuantity)));
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final id = now.millisecondsSinceEpoch.toString();

      // Build Order
      final orderItems = _items.map((i) {
        final p = products.firstWhere((e) => e.id == i.productId);
        return OrderItem(
          productId: p.id,
          productName: p.name,
          quantity: i.quantity,
          price: p.price, // Lưu giá bán thực tế tại thời điểm tạo đơn hàng
          warrantyMonths: i.warrantyMonths,
          purchaseDate: now,
        );
      }).toList();

      final order = Order(
        id: id,
        customerId: widget.selectedCustomerId!,
        createdAt: now,
        items: orderItems,
        total: total,
      );

      // 1) Create order
      await ref.read(orderRepositoryProvider).create(order);

      // 2) Append purchases vào Customer
      final customerRepo = ref.read(customerRepositoryProvider);
      final customer = await customerRepo.fetchById(widget.selectedCustomerId!);
      if (customer != null) {
        final newPurchases = List<Purchase>.from(customer.purchases);
        for (final i in orderItems) {
          newPurchases.add(Purchase(
            productId: i.productId,
            quantity: i.quantity,
            purchaseDate: i.purchaseDate,
            warranty: Warranty(
              months: i.warrantyMonths,
              expireDate: DateTime(i.purchaseDate.year,
                  i.purchaseDate.month + i.warrantyMonths, i.purchaseDate.day),
            ),
          ));
        }
        await customerRepo.upsert(Customer(
          id: customer.id,
          name: customer.name,
          phone: customer.phone,
          email: customer.email,
          address: customer.address,
          purchases: newPurchases,
        ));
      }

      // 3) Trừ tồn kho + ghi inventory export
      final productRepo = ref.read(productRepositoryProvider);
      final inventoryRepo = ref.read(inventoryRepositoryProvider);

      for (final i in orderItems) {
        final p = products.firstWhere((e) => e.id == i.productId);
        final newStock = (p.stock - i.quantity).clamp(0, 1 << 31);
        await productRepo.updateStock(p.id, newStock);
        await inventoryRepo.record(InventoryTransaction(
          id: '${id}_${i.productId}',
          productId: i.productId,
          type: TransactionType.export,
          quantity: i.quantity,
          date: now,
          note: 'Order $id',
          importPrice: null,
        ));
      }

      // 4) Refresh các provider để cập nhật UI
      ref.invalidate(customerListNotifierProvider);
      ref.invalidate(productListProvider);

      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.added)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// Widget Autocomplete cho sản phẩm
class _ProductAutocomplete extends StatefulWidget {
  final List<Product> products;
  final String? selectedProductId;
  final Function(String?) onProductSelected;

  const _ProductAutocomplete({
    required this.products,
    required this.selectedProductId,
    required this.onProductSelected,
  });

  @override
  State<_ProductAutocomplete> createState() => _ProductAutocompleteState();
}

class _ProductAutocompleteState extends State<_ProductAutocomplete> {
  late TextEditingController _controller;
  String _lastSelectedText = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _updateDisplayText();
  }

  @override
  void didUpdateWidget(_ProductAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedProductId != widget.selectedProductId) {
      _updateDisplayText();
    }
  }

  void _updateDisplayText() {
    if (widget.selectedProductId != null) {
      final product = widget.products.firstWhere(
        (p) => p.id == widget.selectedProductId,
        orElse: () => const Product(
            id: '',
            name: '',
            brand: '',
            model: '',
            price: 0,
            stock: 0,
            category: ''),
      );
      _lastSelectedText =
          '${product.name} • ${product.brand} • ${product.model}';
      _controller.text = _lastSelectedText;
    } else {
      _lastSelectedText = '';
      _controller.text = '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Autocomplete<Product>(
      displayStringForOption: (product) =>
          '${product.name} • ${product.brand} • ${product.model}',
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return widget.products;
        }
        return widget.products.where((product) {
          final query = textEditingValue.text.toLowerCase();
          return product.name.toLowerCase().contains(query) ||
              product.brand.toLowerCase().contains(query) ||
              product.model.toLowerCase().contains(query);
        }).toList();
      },
      onSelected: (product) {
        widget.onProductSelected(product.id);
        _lastSelectedText =
            '${product.name} • ${product.brand} • ${product.model}';
        _controller.text = _lastSelectedText;
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller, // Sử dụng controller từ Autocomplete
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: l10n.searchProductsHint,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.search),
            hintText: l10n.searchProductsHint,
          ),
          onChanged: (value) {
            if (value != _lastSelectedText && value.isNotEmpty) {
              widget.onProductSelected(null);
            }
          },
        );
      },
    );
  }
}

class _LineItem {
  String? productId;
  int quantity = 1;
  int warrantyMonths = 12;
}
