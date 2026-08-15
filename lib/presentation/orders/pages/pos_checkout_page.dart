import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/customers/customers_providers.dart';
import '../../../application/inventory/inventory_providers.dart';
import '../../../application/orders/cart_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../core/utils/combo_helper.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../application/settings/store_payment_config_providers.dart';
import '../../../core/utils/code_generator_helper.dart';
import '../../../core/utils/invoice_print_helper.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/customer_debt_transaction.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/order_item.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/purchase.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/entities/warranty.dart';

class POSCheckoutPage extends ConsumerStatefulWidget {
  final Customer? initialCustomer;
  final double initialDiscount;
  final bool isDiscountPercent;

  const POSCheckoutPage({
    super.key,
    this.initialCustomer,
    this.initialDiscount = 0.0,
    this.isDiscountPercent = false,
  });

  @override
  ConsumerState<POSCheckoutPage> createState() => _POSCheckoutPageState();
}

class _POSCheckoutPageState extends ConsumerState<POSCheckoutPage> {
  // Trạng thái khách hàng được chọn (Mặc định null nghĩa là "Khách lẻ")
  Customer? _selectedCustomer;

  final _discountController = TextEditingController(text: '0');
  final _paymentController = TextEditingController();

  double _discount = 0.0;
  bool _isDiscountPercent = false; // Chọn giảm giá theo % hoặc đ
  double _customerPayment = 0.0;
  String _paymentMethod = 'cash'; // 'cash' hoặc 'transfer'

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedCustomer = widget.initialCustomer;
    _discount = widget.initialDiscount;
    _isDiscountPercent = widget.isDiscountPercent;
    _discountController.text = _discount.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _discountController.dispose();
    _paymentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final totalAmount = ref.watch(cartTotalAmountProvider);
    final l10n = AppLocalizations.of(context)!;

    final discountAmount =
        _isDiscountPercent ? (totalAmount * _discount / 100) : _discount;
    final netPay = (totalAmount - discountAmount).clamp(0.0, double.infinity);
    final returnChange =
        (_customerPayment - netPay).clamp(0.0, double.infinity);

    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.checkout,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
      ),
      body: _isSaving
          ? const Center(child: LoadingIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Chọn Khách Hàng
                  _buildCustomerSelectorCard(context),
                  const SizedBox(height: 12),

                  // 2. Danh sách sản phẩm mua
                  _buildOrderItemsCard(context, cart, currencyFormat),
                  const SizedBox(height: 12),

                  // 3. Thông tin thanh toán (Tiền hàng, giảm giá, khách đưa)
                  _buildPaymentDetailsCard(context, totalAmount, netPay,
                      returnChange, currencyFormat),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomActionsBar(context, netPay, cart),
    );
  }

  // 1. Card chọn khách hàng
  Widget _buildCustomerSelectorCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.customers,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87),
              ),
              InkWell(
                onTap: () => _showCustomerListBottomSheet(context),
                child: Row(
                  children: [
                    Text(
                      l10n.change,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.primary, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.06),
                child: const Icon(Icons.person, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _selectedCustomer == null
                    ? Text(
                        l10n.retailCustomer,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedCustomer!.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.black87),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_selectedCustomer!.phone} • ${_selectedCustomer!.address}',
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 12),
                          )
                        ],
                      ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildOrderItemsCard(
      BuildContext context, Map<String, CartItem> cart, NumberFormat format) {
    final user = ref.read(authProvider);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.orderInfo,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cart.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = cart.values.elementAt(index);
              return InkWell(
                onTap: user?.isAdmin == true
                    ? () => _showEditPriceDialog(context, ref, item)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    item.product.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.black87),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (user?.isAdmin == true) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.edit_outlined,
                                      size: 13, color: AppColors.primary),
                                ]
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${l10n.quantity}: ${item.quantity} x ${format.format(item.price)} đ' +
                                  (item.customPrice != null
                                      ? ' (Gốc: ${format.format(item.product.price)}đ)'
                                      : ''),
                              style: const TextStyle(
                                  color: Colors.black54, fontSize: 11),
                            ),
                            if (item.product.isCombo &&
                                item.product.comboComponents.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Gồm: ${item.product.comboComponents.map((c) => "${c.quantity * item.quantity}x ${c.productName}").join(", ")}',
                                style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        '${format.format(item.total)} đ',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.black87),
                      )
                    ],
                  ),
                ),
              );
            },
          )
        ],
      ),
    );
  }

  void _showEditPriceDialog(
      BuildContext context, WidgetRef ref, CartItem item) {
    final controller =
        TextEditingController(text: item.price.toStringAsFixed(0));
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${l10n.changePrice}: ${item.product.name}'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: l10n.newPrice,
              suffixText: 'đ',
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final newPrice = double.tryParse(controller.text.trim());
                if (newPrice != null && newPrice >= 0) {
                  ref
                      .read(cartProvider.notifier)
                      .updatePrice(item.product.id, newPrice);
                }
                Navigator.pop(context);
              },
              child: Text(l10n.update),
            ),
          ],
        );
      },
    );
  }

  // 3. Card thông tin thanh toán chi tiết
  Widget _buildPaymentDetailsCard(
    BuildContext context,
    double totalAmount,
    double netPay,
    double returnChange,
    NumberFormat format,
  ) {
    final user = ref.watch(authProvider);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSummaryDetailRow(l10n.totalProductAmount,
              '${format.format(totalAmount)} đ', false),
          const SizedBox(height: 12),
          // Dòng giảm giá chiết khấu
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(l10n.orderDiscount,
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 13)),
                  if (user?.isAdmin == true) ...[
                    const SizedBox(width: 8),
                    ToggleButtons(
                      isSelected: [!_isDiscountPercent, _isDiscountPercent],
                      onPressed: (index) {
                        setState(() {
                          _isDiscountPercent = index == 1;
                        });
                      },
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 24),
                      borderRadius: BorderRadius.circular(4),
                      children: const [
                        Text('đ',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('%',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ]
                ],
              ),
              SizedBox(
                width: 120,
                height: 36,
                child: TextField(
                  controller: _discountController,
                  enabled: user?.isAdmin == true,
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: const OutlineInputBorder(),
                    suffixText: _isDiscountPercent ? '%' : 'đ',
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  onChanged: (v) {
                    setState(() {
                      _discount = double.tryParse(v) ?? 0.0;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSummaryDetailRow(
              l10n.amountToPay, '${format.format(netPay)} đ', true,
              color: AppColors.primary),
          const SizedBox(height: 12),
          // Dòng nhập tiền khách đưa
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.amountPaid,
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
              Row(
                children: [
                  SizedBox(
                    width: 150,
                    height: 42,
                    child: TextField(
                      controller: _paymentController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        CurrencyInputFormatter(),
                      ],
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        border: const OutlineInputBorder(),
                        hintText: format.format(netPay),
                        suffixIcon: _paymentController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _paymentController.clear();
                                  setState(() {
                                    _customerPayment = 0.0;
                                  });
                                },
                              )
                            : null,
                      ),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                      onTap: () {
                        if (_paymentController.text.isNotEmpty) {
                          _paymentController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _paymentController.text.length,
                          );
                        }
                      },
                      onChanged: (v) {
                        final raw = v.replaceAll('.', '').replaceAll(',', '');
                        setState(() {
                          _customerPayment = double.tryParse(raw) ?? 0.0;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Nút bấm nhanh [Trả đủ] và [Xóa]
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: () {
                  final text = format.format(netPay);
                  _paymentController.text = text;
                  _paymentController.selection =
                      TextSelection.collapsed(offset: text.length);
                  setState(() {
                    _customerPayment = netPay;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: const Text(
                    'Trả đủ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  _paymentController.clear();
                  setState(() {
                    _customerPayment = 0.0;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Text(
                    'Xóa',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSummaryDetailRow(
              l10n.changeDue, '${format.format(returnChange)} đ', false,
              color: Colors.green),
          const SizedBox(height: 12),
          // Phương thức thanh toán
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.paymentMethod,
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _paymentMethod,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      fontSize: 13),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _paymentMethod = v;
                      });
                    }
                  },
                  items: [
                    DropdownMenuItem(value: 'cash', child: Text(l10n.cash)),
                    DropdownMenuItem(
                        value: 'transfer', child: Text(l10n.transfer)),
                  ],
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSummaryDetailRow(String label, String value, bool isBold,
      {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.black54, fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 15 : 13,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  // 4. Thanh hành động dưới cùng
  Widget _buildBottomActionsBar(
      BuildContext context, double netPay, Map<String, CartItem> cart) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Nút Lưu tạm
          Expanded(
            child: OutlinedButton(
              onPressed: () => _confirmSaveDraft(context, netPay, cart),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(l10n.saveDraft,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
          const SizedBox(width: 12),
          // Nút Thanh toán
          Expanded(
            child: ElevatedButton(
              onPressed: () => _processPayment(netPay, cart),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(l10n.checkout,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          )
        ],
      ),
    );
  }

  // Hộp thoại Bottom Sheet tìm kiếm khách hàng
  void _showCustomerListBottomSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final customersAsync = ref.watch(customerListNotifierProvider);
            return Container(
              padding: const EdgeInsets.only(
                  top: 16, bottom: 24, left: 16, right: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.selectCustomer,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline,
                            color: AppColors.primary, size: 28),
                        onPressed: () {
                          Navigator.pop(context);
                          _showAddCustomerDialog(context);
                        },
                      )
                    ],
                  ),
                  const Divider(color: AppColors.divider),
                  customersAsync.when(
                    data: (customers) {
                      return Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: customers.length + 1,
                          itemBuilder: (context, idx) {
                            if (idx == 0) {
                              return ListTile(
                                title: Text(l10n.retailCustomer,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                onTap: () {
                                  setState(() {
                                    _selectedCustomer = null;
                                  });
                                  Navigator.pop(context);
                                },
                              );
                            }
                            final customer = customers[idx - 1];
                            return ListTile(
                              title: Text(customer.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  '${customer.phone} • ${customer.address}'),
                              onTap: () {
                                setState(() {
                                  _selectedCustomer = customer;
                                });
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                      );
                    },
                    loading: () => const Center(child: LoadingIndicator()),
                    error: (e, _) =>
                        Center(child: Text('${l10n.notFound}: $e')),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Hộp thoại Popup thêm mới khách hàng inline trực tiếp
  void _showAddCustomerDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final emailController = TextEditingController();
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.addNewCustomer,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                        labelText: l10n.fullNameRequired,
                        border: const OutlineInputBorder()),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? l10n.pleaseEnterName
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    decoration: InputDecoration(
                        labelText: l10n.phoneNumberRequired,
                        border: const OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? l10n.pleaseEnterName
                        : null, // Vẫn dùng placeholder này tạm thời
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailController,
                    decoration: InputDecoration(
                        labelText: l10n.email,
                        border: const OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: addressController,
                    decoration: InputDecoration(
                        labelText: l10n.address,
                        border: const OutlineInputBorder()),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final currentUser = ref.read(authProvider);
                  final activeBranchName =
                      await ref.read(currentStoreNameProvider.future);

                  final existingCusts =
                      ref.read(customerListNotifierProvider).value ?? [];
                  final custIds = existingCusts.map((c) => c.id).toList();
                  final newCustId =
                      CodeGeneratorHelper.generateNextCustomerCode(custIds);

                  final newCust = Customer(
                    id: newCustId,
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                    email: emailController.text.trim(),
                    address: addressController.text.trim(),
                    purchases: const [],
                    branch: activeBranchName,
                    createdAt: DateTime.now().toIso8601String(),
                    createdBy: currentUser?.username ?? 'admin',
                    status: '1',
                  );

                  Navigator.pop(dialogContext);
                  setState(() => _isSaving = true);

                  try {
                    await ref.read(customerRepositoryProvider).upsert(newCust);
                    ref.invalidate(customerListNotifierProvider);
                    setState(() {
                      _selectedCustomer = newCust;
                      _isSaving = false;
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(l10n.addCustomerSuccess),
                            backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    setState(() => _isSaving = false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Lỗi: $e')),
                      );
                    }
                  }
                }
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(l10n.save),
            )
          ],
        );
      },
    );
  }

  // Popup xác nhận Lưu tạm đơn hàng nháp
  void _confirmSaveDraft(
      BuildContext context, double netPay, Map<String, CartItem> cart) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.saveDraftTitle),
          content: Text(l10n.saveDraftConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.no),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _submitOrder(netPay, cart, isDraft: true);
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(l10n.saveDraft),
            )
          ],
        );
      },
    );
  }

  // Xử lý thực hiện Thanh toán đơn hàng chính thức
  Future<void> _processPayment(
      double netPay, Map<String, CartItem> cart) async {
    await _submitOrder(netPay, cart, isDraft: false);
  }

  // Submit Order lên Firebase và thực hiện logic kho
  Future<void> _submitOrder(double netPay, Map<String, CartItem> cart,
      {required bool isDraft}) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();

      // Sử dụng lại mã đơn tạm cũ nếu đang lên đơn từ một đơn tạm
      final activeOrderId = ref.read(activeOrderIdProvider);
      final String id;
      if (activeOrderId != null && activeOrderId.isNotEmpty) {
        id = activeOrderId;
      } else {
        final existingOrders = ref
                .read(allBranchesOrdersByDateRangeProvider(
                    OverviewTimeRange.thisMonth.getRange()))
                .value ??
            [];
        final orderIds = existingOrders.map((o) => o.id).toList();
        id = CodeGeneratorHelper.generateNextOrderCode(orderIds);
      }

      final List<OrderItem> orderItems = cart.values.map((item) {
        return OrderItem(
          productId: item.product.id,
          productName: item.product.name,
          quantity: item.quantity,
          price: item.price,
          warrantyMonths: 12,
          // Mặc định 12 tháng bảo hành
          purchaseDate: now,
        );
      }).toList();

      final customerId = _selectedCustomer?.id ?? 'khach_le';

      final double paidAmount;
      if (isDraft) {
        paidAmount = 0.0;
      } else if (_paymentController.text.trim().isEmpty) {
        paidAmount = netPay;
      } else {
        paidAmount = _customerPayment.clamp(0.0, netPay);
      }
      final double debtAmount =
          isDraft ? 0.0 : (netPay - paidAmount).clamp(0.0, netPay);

      if (debtAmount > 0 && customerId == 'khach_le' && !isDraft) {
        setState(() => _isSaving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.walkInCustomerDebtNotAllowed),
              backgroundColor: AppColors.warning,
            ),
          );
        }
        return;
      }

      // Tối ưu Firebase: Chỉ fetch đúng các sản phẩm liên quan có trong giỏ hàng
      final Map<String, Product> freshCartProducts = {};

      if (!isDraft) {
        final productRepo = ref.read(productRepositoryProvider);
        final selectedBranch = ref.read(selectedPOSBranchProvider);
        final l10n = AppLocalizations.of(context)!;

        // 1) Gom tất cả Product ID cần fetch (gồm cả linh kiện nếu là Combo)
        final Set<String> neededProductIds = {};
        for (final item in cart.values) {
          neededProductIds.add(item.product.id);
          if (item.product.isCombo && item.product.comboComponents.isNotEmpty) {
            for (final comp in item.product.comboComponents) {
              neededProductIds.add(comp.productId);
            }
          }
        }

        // 2) Fetch song song cực nhanh chỉ đúng các sản phẩm cần kiểm tra
        final fetchedList = await Future.wait(
          neededProductIds.map((pId) => productRepo.fetchById(pId)),
        );

        for (final p in fetchedList) {
          if (p != null) {
            freshCartProducts[p.id] = p;
          }
        }

        final relatedProducts = freshCartProducts.values.toList();

        // 3) Kiểm tra tồn kho khả dụng thời điểm hiện tại
        for (final item in cart.values) {
          final currentProduct =
              freshCartProducts[item.product.id] ?? item.product;

          final availableStock = ComboHelper.getAvailableStock(
            product: currentProduct,
            branchId: selectedBranch,
            allProducts: relatedProducts,
          );

          if (availableStock <= 0) {
            setState(() => _isSaving = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text('${currentProduct.name} - ${l10n.outOfStockMsg}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }

          if (item.quantity > availableStock) {
            setState(() => _isSaving = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '${currentProduct.name} - ${l10n.notEnoughStock} (Còn: $availableStock, Cần: ${item.quantity})'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        }
      }

      final currentUser = ref.read(authProvider);

      // Tạo đối tượng hoá đơn/đơn hàng
      final order = Order(
        id: id,
        customerId: customerId,
        createdAt: now,
        items: orderItems,
        total: netPay,
        status: isDraft ? 'draft' : 'completed',
        amountPaid: paidAmount,
        debtAmount: debtAmount,
        paymentMethod: _paymentMethod,
        createdBy: currentUser?.username,
        createdByName: currentUser?.name,
      );

      // 1) Lưu đơn hàng
      await ref.read(orderRepositoryProvider).create(order);

      // 2) Cập nhật lịch sử mua hàng & công nợ cho Customer (nếu không phải Khách lẻ & không phải đơn nháp)
      if (customerId != 'khach_le' && !isDraft) {
        final customerRepo = ref.read(customerRepositoryProvider);
        final customer = await customerRepo.fetchById(customerId);
        if (customer != null) {
          final newPurchases = List<Purchase>.from(customer.purchases);
          for (final item in orderItems) {
            newPurchases.add(Purchase(
              productId: item.productId,
              quantity: item.quantity,
              purchaseDate: item.purchaseDate,
              warranty: Warranty(
                months: item.warrantyMonths,
                expireDate: DateTime(
                  item.purchaseDate.year,
                  item.purchaseDate.month + item.warrantyMonths,
                  item.purchaseDate.day,
                ),
              ),
            ));
          }
          final double currentTotalSales = customer.totalSales ?? 0.0;
          final double currentNetSales = customer.netSales ?? 0.0;
          final double currentDebt = customer.displayCurrentDebt;
          final double newDebt = currentDebt + debtAmount;

          final updatedCustomer = customer.copyWith(
            purchases: newPurchases,
            totalSales: currentTotalSales + netPay,
            netSales: currentNetSales + netPay,
            currentDebt: newDebt,
            lastTransactionDate: now.toIso8601String(),
          );
          await customerRepo.upsert(updatedCustomer);

          // Nếu có công nợ phát sinh từ đơn này, lưu giao dịch công nợ
          if (debtAmount > 0) {
            final currencyFormat = NumberFormat('#,###', 'vi_VN');
            final debtTx = CustomerDebtTransaction(
              id: 'DEBT_${now.millisecondsSinceEpoch}',
              code: id,
              customerId: customerId,
              date: now,
              amount: debtAmount,
              remainingDebt: newDebt,
              type: DebtTransactionType.invoice,
              note:
                  'Nợ đơn hàng $id (Đã trả: ${currencyFormat.format(paidAmount)}đ, Nợ: ${currencyFormat.format(debtAmount)}đ)',
            );

            await ref
                .read(customerRemoteDataSourceProvider)
                .saveDebtTransaction(customerId, debtTx.toMap());
          }
        }
      }

      // Nếu KHÔNG phải đơn nháp (Đơn chính thức) -> Trừ tồn kho và ghi nhận Xuất kho
      if (!isDraft) {
        final productRepo = ref.read(productRepositoryProvider);
        final inventoryRepo = ref.read(inventoryRepositoryProvider);
        final selectedBranch = ref.read(selectedPOSBranchProvider);

        for (final item in cart.values) {
          if (item.product.isCombo && item.product.comboComponents.isNotEmpty) {
            // Trừ kho từng linh kiện thành phần của Combo
            for (final comp in item.product.comboComponents) {
              final childProduct = freshCartProducts[comp.productId] ??
                  await productRepo.fetchById(comp.productId);
              if (childProduct != null) {
                final childBranchStocks =
                    Map<String, int>.from(childProduct.branchStocks);
                final currentChildStock =
                    childBranchStocks[selectedBranch] ?? 0;
                final qtyToDeduct = item.quantity * comp.quantity;
                childBranchStocks[selectedBranch] =
                    (currentChildStock - qtyToDeduct).clamp(0, 99999);

                final updatedChild =
                    childProduct.copyWith(branchStocks: childBranchStocks);
                await productRepo.upsert(updatedChild);

                // Ghi nhận lịch sử giao dịch kho cho linh kiện
                await inventoryRepo.record(InventoryTransaction(
                  id: 'export_${now.millisecondsSinceEpoch}_${childProduct.id}',
                  productId: childProduct.id,
                  type: TransactionType.export,
                  quantity: qtyToDeduct,
                  date: now,
                  note: '$id (Combo: ${item.product.name})',
                  importPrice: null,
                  createdBy: currentUser?.username,
                  createdByName: currentUser?.name,
                ));
              }
            }
          } else {
            // Trừ stock sản phẩm đơn lẻ thông thường (Tái sử dụng freshCartProducts đã fetch ở bước 1)
            final freshProduct = freshCartProducts[item.product.id] ??
                await productRepo.fetchById(item.product.id) ??
                item.product;
            final branchStocks =
                Map<String, int>.from(freshProduct.branchStocks);
            final currentStock = branchStocks[selectedBranch] ?? 0;
            branchStocks[selectedBranch] =
                (currentStock - item.quantity).clamp(0, 99999);

            final updatedProduct =
                freshProduct.copyWith(branchStocks: branchStocks);
            await productRepo.upsert(updatedProduct);

            // Ghi nhận lịch sử giao dịch kho
            await inventoryRepo.record(InventoryTransaction(
              id: 'export_${now.millisecondsSinceEpoch}_${freshProduct.id}',
              productId: freshProduct.id,
              type: TransactionType.export,
              quantity: item.quantity,
              date: now,
              note: id,
              importPrice: null,
              createdBy: currentUser?.username,
              createdByName: currentUser?.name,
            ));
          }
        }
      }

      // Refresh providers
      ref.invalidate(productListProvider);
      ref.invalidate(orderRepositoryProvider);
      ref.invalidate(customerListNotifierProvider);

      // Reset activeOrderIdProvider nếu là đơn hoàn thành
      if (!isDraft) {
        ref.read(activeOrderIdProvider.notifier).state = null;
      }

      // Clear giỏ hàng Riverpod
      ref.read(cartProvider.notifier).clearCart();

      setState(() => _isSaving = false);

      if (mounted) {
        final config = ref.read(storePaymentConfigProvider);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isDraft ? 'Đã lưu đơn nháp' : 'Thanh toán thành công',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Text(
              'Đơn hàng $id đã được tạo thành công.\nBạn có muốn in hóa đơn ngay bây giờ không?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('Về màn hình chính'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogCtx);
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  await InvoicePrintHelper.printInvoice(
                    context,
                    order,
                    _selectedCustomer,
                    config,
                  );
                },
                icon: const Icon(Icons.print),
                label: const Text('In Hóa Đơn'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }
}
