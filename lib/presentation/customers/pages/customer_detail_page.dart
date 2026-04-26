import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/constants/product_categories.dart';
import 'package:stores/presentation/common/widgets/error_view.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/purchase.dart';
import '../../orders/pages/create_order_page.dart';

class CustomerDetailPage extends ConsumerStatefulWidget {
  final Customer customer;

  const CustomerDetailPage({super.key, required this.customer});

  @override
  ConsumerState<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends ConsumerState<CustomerDetailPage> {
  bool _isEditing = false;
  bool _isLoading = false;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.customer.name);
    _phone = TextEditingController(text: widget.customer.phone);
    _email = TextEditingController(text: widget.customer.email);
    _address = TextEditingController(text: widget.customer.address);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final customersAsync = ref.watch(customerListNotifierProvider);
    final c = customersAsync.maybeWhen(
      data: (list) => list.firstWhere(
        (x) => x.id == widget.customer.id,
        orElse: () => widget.customer,
      ),
      orElse: () => widget.customer,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l10n.edit : l10n.customerDetail),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: l10n.createOrder,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      CreateOrderPage(selectedCustomerId: widget.customer.id),
                ),
              );
            },
          ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: l10n.save,
              onPressed: _isLoading ? null : _saveCustomer,
            )
          else
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: l10n.edit,
              onPressed: () => setState(() => _isEditing = true),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _isEditing
                    ? Form(
                        key: _formKey,
                        child: Column(
                        children: [
                          _field(_name, l10n.name, Icons.person),
                          const SizedBox(height: 12),
                          _field(_phone, l10n.phone, Icons.phone,
                              keyboard: TextInputType.phone),
                          const SizedBox(height: 12),
                          _field(_email, l10n.email, Icons.email,
                              keyboard: TextInputType.emailAddress,
                              required: false),
                          const SizedBox(height: 12),
                          _field(_address, l10n.address, Icons.location_on,
                              maxLines: 2, required: false),
                        ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _infoRow(context, Icons.person, l10n.name, c.name),
                          _infoRow(context, Icons.phone, l10n.phone, c.phone),
                          _infoRow(context, Icons.email, l10n.email, c.email),
                          _infoRow(context, Icons.location_on, l10n.address,
                              c.address),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            _PurchasesSection(purchases: c.purchases),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    bool required = true,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isNumber = keyboard == TextInputType.phone;

    return TextFormField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final text = value?.trim() ?? '';

        if (required && text.isEmpty) {
          return '${l10n.pleaseEnter} $label';
        }

        if (isNumber && text.isNotEmpty) {
          // Enforce Vietnam mobile format: 10 digits starting with 03/05/07/08/09
          final vnPhoneRegex = RegExp(r'^(03|05|07|08|09)\d{8}$');
          if (!vnPhoneRegex.hasMatch(text)) {
            return l10n.pleaseEnterValidNumber;
          }
        }

        if (keyboard == TextInputType.emailAddress && text.isNotEmpty) {
          final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
          if (!emailRegex.hasMatch(text)) {
            return l10n.pleaseEnterValidEmail;
          }
        }

        return null;
      },
    );
  }

  Widget _infoRow(
      BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCustomer() async {
    final l10n = AppLocalizations.of(context)!;
    // Validate form
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseFillAllField)),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final updated = Customer(
        id: widget.customer.id,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
        purchases: widget.customer.purchases,
      );
      await ref.read(customerRepositoryProvider).upsert(updated);
      // Refresh customers list and navigate back to the list page
      await ref.read(customerListNotifierProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.updated)),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _PurchasesSection extends ConsumerWidget {
  final List<Purchase> purchases;

  const _PurchasesSection({required this.purchases});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final productsAsync = ref.watch(productListProvider);
    final l10n = AppLocalizations.of(context)!;

    if (purchases.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Icon(Icons.shopping_cart_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(l10n.noPurchases, style: theme.textTheme.titleMedium),
          ]),
        ),
      );
    }

    return productsAsync.when(
      data: (products) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: purchases.map((purchase) {
            final product = products.firstWhere(
              (p) => p.id == purchase.productId,
              orElse: () => _unknownProduct(purchase.productId),
            );

            final now = DateTime.now();
            final isWarrantyActive = purchase.warranty.expireDate.isAfter(now);
            final daysUntilExpiry =
                purchase.warranty.expireDate.difference(now).inDays;
            final monthsUntilExpiry = (daysUntilExpiry / 30).floor();

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with product + status
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            ProductCategories.getCategoryIcon(product.category),
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(product.name,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              Text(
                                '${product.brand} • ${product.model}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isWarrantyActive
                                ? Colors.green.withOpacity(0.1)
                                : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: isWarrantyActive
                                    ? Colors.green
                                    : Colors.red),
                          ),
                          child: Text(
                            isWarrantyActive
                                ? l10n.warrantyActive
                                : l10n.warrantyExpired,
                            style: TextStyle(
                              color: isWarrantyActive
                                  ? Colors.green[700]
                                  : Colors.red[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Details rows
                    Row(
                      children: [
                        Expanded(
                            child: _detailItem(
                                context,
                                l10n.purchasedOn,
                                _fmt(purchase.purchaseDate),
                                Icons.calendar_today)),
                        Expanded(
                            child: _detailItem(context, l10n.quantity,
                                '${purchase.quantity}', Icons.shopping_cart)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: _detailItem(
                                context,
                                l10n.warranty,
                                '${purchase.warranty.months} ${l10n.months}',
                                Icons.verified_user)),
                        Expanded(
                            child: _detailItem(
                                context,
                                l10n.warrantyExpiresIn,
                                _fmt(purchase.warranty.expireDate),
                                Icons.schedule)),
                      ],
                    ),

                    // Warranty status message
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (isWarrantyActive ? Colors.green : Colors.red)
                            .withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                (isWarrantyActive ? Colors.green : Colors.red)
                                    .withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                              isWarrantyActive
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              size: 18,
                              color: isWarrantyActive
                                  ? Colors.green[700]
                                  : Colors.red[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isWarrantyActive
                                  ? (daysUntilExpiry > 30
                                      ? '${l10n.warrantyActive} $monthsUntilExpiry ${l10n.months}'
                                      : '${l10n.warrantyActive} $daysUntilExpiry ${l10n.days}')
                                  : '${l10n.expiresOn} ${_fmt(purchase.warranty.expireDate)}',
                              style: TextStyle(
                                color: isWarrantyActive
                                    ? Colors.green[700]
                                    : Colors.red[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
      loading: () => const LoadingIndicator(),
      error: (e, _) => ErrorView(e),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Product _unknownProduct(String id) => Product(
        id: id,
        name: 'Unknown Product',
        brand: 'Unknown',
        model: 'Unknown',
        price: 0,
        stock: 0,
        category: 'Other',
      );

  Widget _detailItem(
      BuildContext context, String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
