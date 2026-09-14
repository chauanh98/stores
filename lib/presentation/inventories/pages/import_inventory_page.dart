import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/inventory/inventory_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/suppliers/suppliers_providers.dart';
import '../../../core/utils/vietnamese_text_helper.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/supplier.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../common/widgets/error_view.dart';
import '../../suppliers/pages/add_edit_supplier_page.dart';

class ImportInventoryPage extends ConsumerStatefulWidget {
  const ImportInventoryPage({super.key});

  @override
  ConsumerState<ImportInventoryPage> createState() =>
      _ImportInventoryPageState();
}

class _ImportInventoryPageState extends ConsumerState<ImportInventoryPage> {
  final List<_ImportItem> _items = [_ImportItem()];
  bool _saving = false;
  Supplier? _selectedSupplier;
  bool _isDebtPayment = false;
  final TextEditingController _paidAmountController =
      TextEditingController(text: '0');

  @override
  void dispose() {
    _paidAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(authProvider);
    final canViewCostPrice = user?.canViewCostPrice ?? false;
    final currentStoreId = ref.watch(currentStoreIdProvider);
    final storesMap = ref.watch(availableStoresProvider).value ?? {};
    final storeName = storesMap[currentStoreId] ??
        (currentStoreId == 'store_002'
            ? 'Chi nhánh Thới Bình'
            : 'Chi nhánh Đông Thắng');
    final isStoreLocked =
        user?.isStaff == true || !(user?.canSwitchStore ?? false);

    final productsList = productsAsync.value ?? [];
    final double totalCalculatedAmount = _items.fold(0.0, (sum, item) {
      if (item.productId == null) return sum;
      if (canViewCostPrice) {
        return sum + (item.importPrice * item.quantity);
      } else {
        final prod = productsList.where((p) => p.id == item.productId).firstOrNull;
        return sum + ((prod?.costPrice ?? 0.0) * item.quantity);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.import),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saving ? null : () => _save(canViewCostPrice: canViewCostPrice),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Header info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.inventory_2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.importProduct,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.importDescription,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isStoreLocked
                            ? Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                            : Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isStoreLocked
                              ? Theme.of(context).colorScheme.outlineVariant
                              : Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isStoreLocked
                                ? Icons.lock_outline
                                : Icons.storefront,
                            size: 16,
                            color: isStoreLocked
                                ? Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Chi nhánh nhập: $storeName${isStoreLocked ? ' (Cố định)' : ''}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isStoreLocked
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                      : Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Supplier Selector Card
            _buildSupplierCard(context),

            const SizedBox(height: 12),

            // Items
            productsAsync.when(
              data: (products) => Column(
                children: [
                  ..._items.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    final Product? product = products
                            .where((p) => p.id == item.productId)
                            .firstOrNull ??
                        (products.isNotEmpty ? products.first : null);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Sản phẩm với Autocomplete
                            _ProductAutocomplete(
                              products: products,
                              selectedProductId: item.productId,
                              onProductSelected: (productId) => setState(() {
                                item.productId = productId;
                                if (productId != null) {
                                  final selectedProd = products
                                      .where((p) => p.id == productId)
                                      .firstOrNull;
                                  if (selectedProd != null) {
                                    item.importPrice = selectedProd.costPrice;
                                  }
                                }
                              }),
                            ),

                            const SizedBox(height: 12),

                            // Số lượng và giá nhập
                            if (canViewCostPrice)
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
                                        item.quantity =
                                            int.tryParse(v) ?? 1;
                                      }),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: item.importPrice.toString(),
                                      decoration: InputDecoration(
                                        labelText: l10n.importPrice,
                                        border: const OutlineInputBorder(),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (v) => setState(() {
                                        item.importPrice =
                                            double.tryParse(v) ?? 0.0;
                                      }),
                                    ),
                                  ),
                                ],
                              )
                            else
                              TextFormField(
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

                            const SizedBox(height: 12),

                            // Thông tin hiển thị
                            if (product != null) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildInfoField(
                                      l10n.currentStock,
                                      '${product.stock}',
                                      Icons.inventory,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildInfoField(
                                      l10n.stockAfterImport,
                                      '${product.stock + item.quantity}',
                                      Icons.add_circle,
                                    ),
                                  ),
                                ],
                              ),
                            ],

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
                    onPressed: () => setState(() => _items.add(_ImportItem())),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.addProduct),
                  ),
                ],
              ),
              loading: () =>
                  const SizedBox(height: 120, child: LoadingIndicator()),
              error: (e, _) => ErrorView(e),
            ),

            const SizedBox(height: 12),

            // Payment Option Card
            _buildPaymentOptionCard(
              context: context,
              canViewCostPrice: canViewCostPrice,
              totalAmount: totalCalculatedAmount,
            ),

            const SizedBox(height: 12),

            // Summary
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.importSummary,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.numberOfProducts),
                        Text('${_items.length}'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.totalQuantity),
                        Text(
                            '${_items.fold(0, (sum, item) => sum + item.quantity)}'),
                      ],
                    ),
                    if (canViewCostPrice) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(l10n.totalValue),
                          Text(
                            NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                                .format(_items.fold(
                                    0.0,
                                    (sum, item) =>
                                        sum +
                                        (item.importPrice * item.quantity))),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildSupplierCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_shipping_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Nhà cung cấp',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                if (_selectedSupplier != null)
                  TextButton.icon(
                    onPressed: () => setState(() => _selectedSupplier = null),
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    label: const Text(
                      'Bỏ chọn',
                      style: TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_selectedSupplier == null)
              InkWell(
                key: const Key('select_supplier_btn'),
                onTap: () => _showSupplierSelectSheet(context),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withOpacity(0.5),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person_search,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Chưa chọn Nhà Cung Cấp (Bấm để chọn)',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              )
            else
              Container(
                key: const Key('selected_supplier_card'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withOpacity(0.12),
                  border: Border.all(
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        _selectedSupplier!.name.isNotEmpty
                            ? _selectedSupplier!.name.substring(0, 1).toUpperCase()
                            : 'S',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedSupplier!.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                _selectedSupplier!.code,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              if (_selectedSupplier!.phone.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '•  ${_selectedSupplier!.phone}',
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
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedSupplier!.currentDebt > 0
                                ? 'Nợ hiện tại: ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(_selectedSupplier!.currentDebt)}'
                                : 'Không có nợ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _selectedSupplier!.currentDebt > 0
                                  ? Colors.red[700]
                                  : Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showSupplierSelectSheet(context),
                      child: const Text('Đổi'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSupplierSelectSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return _SupplierSelectSheet(
          selectedSupplierId: _selectedSupplier?.id,
          onSupplierSelected: (supplier) {
            setState(() => _selectedSupplier = supplier);
          },
        );
      },
    );
  }

  Widget _buildPaymentOptionCard({
    required BuildContext context,
    required bool canViewCostPrice,
    required double totalAmount,
  }) {
    final theme = Theme.of(context);
    final paidAmount = canViewCostPrice
        ? (double.tryParse(_paidAmountController.text
                .replaceAll('.', '')
                .replaceAll(',', '')) ??
            0.0)
        : 0.0;
    final debtIncrease = (totalAmount - paidAmount).clamp(0.0, double.infinity);
    final currentDebt = _selectedSupplier?.currentDebt ?? 0.0;
    final newDebt = currentDebt + debtIncrease;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Hình thức thanh toán',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RadioListTile<bool>(
              value: false,
              groupValue: _isDebtPayment,
              onChanged: (val) {
                if (val != null) {
                  setState(() => _isDebtPayment = val);
                }
              },
              title: const Text('Thanh toán toàn bộ'),
              subtitle: Text(
                'Toàn bộ tiền hàng thanh toán ngay',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            RadioListTile<bool>(
              value: true,
              groupValue: _isDebtPayment,
              onChanged: (val) {
                if (val != null) {
                  setState(() => _isDebtPayment = val);
                }
              },
              title: Text(
                canViewCostPrice ? 'Ghi nợ NCC' : 'Ghi nợ NCC (100%)',
              ),
              subtitle: Text(
                canViewCostPrice
                    ? 'Ghi nhận công nợ (trả trước một phần hoặc nợ toàn bộ)'
                    : 'Ghi nhận công nợ 100% theo định mức giá vốn hệ thống',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            if (!canViewCostPrice) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 16),
                child: Text(
                  'Đơn vị tính giá vốn tự động theo định mức hệ thống',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            if (_isDebtPayment && canViewCostPrice) ...[
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('paid_amount_field'),
                controller: _paidAmountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số tiền thanh toán trước cho NCC',
                  hintText: 'Nhập 0 nếu nợ 100%',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                  suffixText: 'đ',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chi tiết công nợ phát sinh:',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPreviewRow(
                      'Tiền hàng:',
                      NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                          .format(totalAmount),
                    ),
                    _buildPreviewRow(
                      'Đã thanh toán:',
                      NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                          .format(paidAmount.clamp(0.0, totalAmount)),
                    ),
                    const Divider(),
                    _buildPreviewRow(
                      'Ghi nhận nợ NCC:',
                      '+ ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(debtIncrease)}',
                      valueColor: Colors.orange[800],
                      isBold: true,
                    ),
                    if (_selectedSupplier != null) ...[
                      const SizedBox(height: 4),
                      _buildPreviewRow(
                        'Nợ cũ NCC:',
                        NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                            .format(currentDebt),
                      ),
                      _buildPreviewRow(
                        'Dư nợ mới sau nhập:',
                        NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                            .format(newDebt),
                        valueColor: Colors.red[700],
                        isBold: true,
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (_isDebtPayment && _selectedSupplier == null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber[700]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber[800], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chưa chọn Nhà Cung Cấp. Vui lòng chọn NCC để ghi nợ.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoField(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon,
              size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _save({required bool canViewCostPrice}) async {
    final l10n = AppLocalizations.of(context)!;

    // Validate
    if (_isDebtPayment && _selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn Nhà Cung Cấp để ghi nợ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    for (final item in _items) {
      if (item.productId == null ||
          item.quantity <= 0 ||
          (canViewCostPrice && item.importPrice <= 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.checkProductsAndQuantity)),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final products = ref
          .read(productListProvider)
          .maybeWhen(data: (v) => v, orElse: () => <Product>[]);
      final productRepo = ref.read(productRepositoryProvider);
      final inventoryRepo = ref.read(inventoryRepositoryProvider);

      final currentUser = ref.read(authProvider);
      final currentStoreId = ref.read(currentStoreIdProvider);

      final importCode = 'PN_${now.millisecondsSinceEpoch}';
      double calculatedTotalAmount = 0.0;

      for (final item in _items) {
        final product = products.firstWhere((p) => p.id == item.productId);
        final effectiveImportPrice =
            canViewCostPrice ? item.importPrice : product.costPrice;

        calculatedTotalAmount += effectiveImportPrice * item.quantity;

        // 1) Cập nhật stock chi nhánh và tính toán lại giá vốn (Weighted Average)
        final branchStocks = Map<String, int>.from(product.branchStocks);
        String targetKey = currentStoreId;
        if (!branchStocks.containsKey(currentStoreId)) {
          if (currentStoreId == 'store_001' &&
              branchStocks.containsKey('branch_1')) {
            targetKey = 'branch_1';
          } else if (currentStoreId == 'store_002' &&
              branchStocks.containsKey('branch_2')) {
            targetKey = 'branch_2';
          }
        }
        final currentBranchStock = branchStocks[targetKey] ?? 0;
        branchStocks[targetKey] = currentBranchStock + item.quantity;

        final currentTotalStock = product.stock;
        final double newCostPrice = (currentTotalStock + item.quantity) > 0
            ? ((currentTotalStock * product.costPrice) +
                    (item.quantity * effectiveImportPrice)) /
                (currentTotalStock + item.quantity)
            : effectiveImportPrice;

        final updatedProduct = product.copyWith(
          branchStocks: branchStocks,
          costPrice: newCostPrice,
        );
        await productRepo.upsert(updatedProduct);

        // 2) Ghi inventory transaction kèm supplierId, supplierName, importCode
        await inventoryRepo.record(InventoryTransaction(
          id: 'import_${now.millisecondsSinceEpoch}_${item.productId}',
          productId: item.productId!,
          type: TransactionType.import,
          quantity: item.quantity,
          date: now,
          note: 'Import - ${product.name}',
          importPrice: effectiveImportPrice,
          createdBy: currentUser?.username,
          createdByName: currentUser?.name,
          storeId: currentStoreId,
          supplierId: _selectedSupplier?.id,
          supplierName: _selectedSupplier?.name,
          importCode: importCode,
        ));
      }

      // 3) Ghi nhận công nợ và doanh số mua hàng nếu có chọn Nhà Cung Cấp
      if (_selectedSupplier != null) {
        final double effectivePaidAmount;
        if (!_isDebtPayment) {
          effectivePaidAmount = calculatedTotalAmount;
        } else if (canViewCostPrice) {
          final rawPaid = double.tryParse(_paidAmountController.text
                  .replaceAll('.', '')
                  .replaceAll(',', '')) ??
              0.0;
          effectivePaidAmount = rawPaid.clamp(0.0, calculatedTotalAmount);
        } else {
          // Staff chọn Ghi nợ NCC (100%)
          effectivePaidAmount = 0.0;
        }

        await ref.read(supplierListNotifierProvider.notifier).recordImportDebt(
              supplierId: _selectedSupplier!.id,
              totalAmount: calculatedTotalAmount,
              paidAmount: effectivePaidAmount,
              importCode: importCode,
              note: 'Nhập hàng - $importCode',
              createdBy: currentUser?.name ?? currentUser?.username ?? 'Admin',
            );
      }

      // Refresh providers
      ref.invalidate(productListProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.updated),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// Widget Autocomplete cho sản phẩm (tương tự như CreateOrderPage)
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
            code: '',
            brand: '',
            model: '',
            price: 0,
            costPrice: 0,
            branchStocks: {},
            category: ''),
      );
      _lastSelectedText =
          '${product.name} • ${product.brand ?? ''} • ${product.model ?? ''}';
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
          '${product.name} • ${product.brand ?? ''} • ${product.model ?? ''}',
      optionsBuilder: (textEditingValue) {
        final nonComboProducts =
            widget.products.where((p) => !p.isCombo).toList();
        if (textEditingValue.text.isEmpty) {
          return nonComboProducts;
        }
        return nonComboProducts.where((product) {
          final query = textEditingValue.text.toLowerCase();
          return product.name.toLowerCase().contains(query) ||
              (product.brand ?? '').toLowerCase().contains(query) ||
              (product.model ?? '').toLowerCase().contains(query);
        }).toList();
      },
      onSelected: (product) {
        widget.onProductSelected(product.id);
        _lastSelectedText =
            '${product.name} • ${product.brand ?? ''} • ${product.model ?? ''}';
        _controller.text = _lastSelectedText;
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: l10n.searchProducts,
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

class _ImportItem {
  String? productId;
  int quantity = 1;
  double importPrice = 0.0;
}

class _SupplierSelectSheet extends ConsumerStatefulWidget {
  final String? selectedSupplierId;
  final ValueChanged<Supplier> onSupplierSelected;

  const _SupplierSelectSheet({
    required this.selectedSupplierId,
    required this.onSupplierSelected,
  });

  @override
  ConsumerState<_SupplierSelectSheet> createState() =>
      _SupplierSelectSheetState();
}

class _SupplierSelectSheetState extends ConsumerState<_SupplierSelectSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(supplierListNotifierProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Chọn Nhà Cung Cấp',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('quick_add_supplier_btn'),
                    onPressed: () async {
                      final newSupplier =
                          await Navigator.of(context).push<Supplier>(
                        MaterialPageRoute(
                          builder: (_) => const AddEditSupplierPage(),
                        ),
                      );
                      if (newSupplier != null && context.mounted) {
                        widget.onSupplierSelected(newSupplier);
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('+ Thêm nhanh NCC'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Search input
              TextField(
                key: const Key('supplier_search_field'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Tìm theo tên, mã, SĐT nhà cung cấp...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
              const SizedBox(height: 12),
              // Supplier List
              Expanded(
                child: suppliersAsync.when(
                  data: (suppliers) {
                    final queryNorm = VietnameseTextHelper.normalizeUnaccented(
                        _searchQuery.trim());
                    final filtered = suppliers.where((s) {
                      if (queryNorm.isEmpty) return true;
                      final nameNorm =
                          VietnameseTextHelper.normalizeUnaccented(s.name);
                      final codeNorm = s.code.toLowerCase();
                      final phone = s.phone;
                      return nameNorm.contains(queryNorm) ||
                          codeNorm.contains(queryNorm) ||
                          phone.contains(queryNorm);
                    }).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_off_outlined,
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text(
                              'Không tìm thấy nhà cung cấp',
                              style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      controller: scrollController,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final supplier = filtered[index];
                        final isSelected =
                            supplier.id == widget.selectedSupplierId;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primaryContainer,
                            foregroundColor: isSelected
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onPrimaryContainer,
                            child: Text(
                              supplier.name.isNotEmpty
                                  ? supplier.name.substring(0, 1).toUpperCase()
                                  : 'S',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            supplier.name,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${supplier.code} • ${supplier.phone.isNotEmpty ? supplier.phone : 'Không có SĐT'}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                supplier.currentDebt > 0
                                    ? 'Nợ: ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(supplier.currentDebt)}'
                                    : 'Không có nợ',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: supplier.currentDebt > 0
                                      ? Colors.red[700]
                                      : Colors.green[700],
                                ),
                              ),
                            ],
                          ),
                          trailing: isSelected
                              ? Icon(Icons.check_circle,
                                  color: theme.colorScheme.primary)
                              : null,
                          onTap: () {
                            widget.onSupplierSelected(supplier);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: LoadingIndicator()),
                  error: (e, _) => ErrorView(e),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
