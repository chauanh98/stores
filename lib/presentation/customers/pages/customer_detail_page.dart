import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/customer_debt_transaction.dart';
import '../../../domain/entities/order.dart';
import '../../orders/pages/create_order_page.dart';
import 'customer_debt_page.dart';
import 'customer_transactions_page.dart';

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
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final customersAsync = ref.watch(customerListNotifierProvider);

    final c = customersAsync.maybeWhen(
      data: (list) => list.firstWhere(
        (x) => x.id == widget.customer.id,
        orElse: () => widget.customer,
      ),
      orElse: () => widget.customer,
    );

    final ordersAsync = ref.watch(customerOrdersProvider(c.id));
    final debtTxsAsync = ref.watch(customerDebtTransactionsProvider(c.id));

    final orders = ordersAsync.value ?? <Order>[];
    final debtTxs = debtTxsAsync.value ?? <CustomerDebtTransaction>[];

    final displayTotalSales = c.effectiveTotalSales(orders);
    final displayCurrentDebt = c.effectiveCurrentDebt(orders, debtTxs);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditing ? l10n.edit : l10n.customerDetail),
        backgroundColor: Colors.white,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: l10n.save,
              onPressed: _isLoading ? null : _saveCustomer,
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'edit') {
                  setState(() => _isEditing = true);
                } else if (value == 'create_order') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreateOrderPage(selectedCustomerId: c.id),
                    ),
                  );
                } else if (value == 'delete') {
                  _showDeleteConfirmDialog(context, c);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(l10n.edit),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'create_order',
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long,
                          color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Text(l10n.createOrder),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(l10n.delete),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isEditing
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _field(_name, l10n.name, Icons.person),
                    const SizedBox(height: 12),
                    _field(_phone, l10n.phone, Icons.phone,
                        keyboard: TextInputType.phone),
                    const SizedBox(height: 12),
                    _field(_email, l10n.email, Icons.email,
                        keyboard: TextInputType.emailAddress, required: false),
                    const SizedBox(height: 12),
                    _field(_address, l10n.address, Icons.location_on,
                        maxLines: 2, required: false),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                children: [
                  // 1. THÔNG TIN CƠ BẢN
                  _buildSectionContainer(
                    headerTitle: l10n.basicInfo,
                    onEditTap: () => setState(() => _isEditing = true),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar + Name
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor:
                                  AppColors.primary.withOpacity(0.12),
                              child: Text(
                                c.name.isNotEmpty
                                    ? c.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                c.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Số điện thoại + Gọi/SMS/Copy
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.phone,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      c.phone.isNotEmpty
                                          ? c.phone
                                          : l10n.noPhoneAvailable,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    if (c.phone.isNotEmpty) ...[
                                      const SizedBox(width: 4),
                                      InkWell(
                                        onTap: () {
                                          Clipboard.setData(
                                              ClipboardData(text: c.phone));
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    l10n.copyPhoneSuccess(
                                                        c.phone))),
                                          );
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.all(4.0),
                                          child: Icon(Icons.copy_rounded,
                                              size: 15, color: Colors.black45),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.chat_bubble_outline,
                                      color: AppColors.primary, size: 20),
                                  onPressed: () async {
                                    if (c.phone.isEmpty) return;
                                    final cleanPhone =
                                        c.phone.replaceAll(RegExp(r'\s+'), '');
                                    final uri = Uri.parse('sms:$cleanPhone');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    } else {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  l10n.cannotSms(cleanPhone))),
                                        );
                                      }
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.phone_outlined,
                                      color: AppColors.primary, size: 20),
                                  onPressed: () async {
                                    if (c.phone.isEmpty) return;
                                    final cleanPhone =
                                        c.phone.replaceAll(RegExp(r'\s+'), '');
                                    final uri = Uri.parse('tel:$cleanPhone');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    } else {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  l10n.cannotCall(cleanPhone))),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            )
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Mã KH + Chi nhánh
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.customerCode,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.black54),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        c.id,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black87),
                                      ),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        onTap: () {
                                          Clipboard.setData(
                                              ClipboardData(text: c.id));
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(l10n
                                                    .copyCustomerCodeSuccess(
                                                        c.id))),
                                          );
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.all(4.0),
                                          child: Icon(Icons.copy_rounded,
                                              size: 15, color: Colors.black45),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.branch,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.black54),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    c.branch ?? 'Chi nhánh Thới Bình',
                                    style: const TextStyle(
                                        fontSize: 14, color: Colors.black87),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: AppColors.divider, height: 1),

                        // Row 1: Lịch sử giao dịch
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    CustomerTransactionsPage(customer: c),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  l10n.transactionHistory,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      currencyFormat.format(displayTotalSales),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right,
                                        color: Colors.black38, size: 20),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(color: AppColors.divider, height: 1),

                        // Row 2: Công nợ
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CustomerDebtPage(customer: c),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  l10n.customerDebt,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      currencyFormat.format(displayCurrentDebt),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: displayCurrentDebt > 0
                                            ? Colors.red
                                            : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right,
                                        color: Colors.black38, size: 20),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. ĐỊA CHỈ
                  _buildSectionContainer(
                    headerTitle: l10n.addressSection,
                    onEditTap: () => setState(() => _isEditing = true),
                    child: Text(
                      c.address.isNotEmpty ? c.address : l10n.notUpdated,
                      style: TextStyle(
                        fontSize: 14,
                        color: c.address.isNotEmpty
                            ? Colors.black87
                            : Colors.black45,
                      ),
                    ),
                  ),

                  // 3. LIÊN HỆ
                  _buildSectionContainer(
                    headerTitle: l10n.contactSection,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailText(l10n.email, c.email),
                        _buildDetailText('Facebook', c.facebook),
                      ],
                    ),
                  ),

                  // 4. NHÓM KHÁCH HÀNG
                  _buildSectionContainer(
                    headerTitle: l10n.customerGroupSection,
                    child: Text(
                      c.group?.isNotEmpty == true
                          ? c.group!
                          : l10n.notCategorized,
                      style:
                          const TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ),

                  // 5. THÔNG TIN XUẤT HOÁ ĐƠN
                  _buildSectionContainer(
                    headerTitle: l10n.invoiceInfoSection,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailText(
                            l10n.customerType, c.type ?? l10n.individual),
                        _buildDetailText(l10n.buyerName, c.name),
                        _buildDetailText(l10n.phone, c.phone),
                        _buildDetailText(l10n.taxCode, c.taxCode),
                        _buildDetailText(l10n.companyName, c.company),
                        _buildDetailText(l10n.note, c.notes),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionContainer({
    required String headerTitle,
    VoidCallback? onEditTap,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                headerTitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                  letterSpacing: 0.5,
                ),
              ),
              if (onEditTap != null)
                InkWell(
                  onTap: onEditTap,
                  child: Text(
                    AppLocalizations.of(context)!.edit,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildDetailText(String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    bool required = true,
  }) {
    final l10n = AppLocalizations.of(context)!;

    return TextFormField(
      controller: controller,
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
        return null;
      },
    );
  }

  Future<void> _saveCustomer() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseFillAllField)),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final updated = widget.customer.copyWith(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
      );
      await ref.read(customerRepositoryProvider).upsert(updated);
      await ref.read(customerListNotifierProvider.notifier).refresh();
      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.updated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${AppLocalizations.of(context)!.importError}: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDeleteConfirmDialog(BuildContext context, Customer c) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.deleteCustomerTitle),
        content: Text(l10n.deleteCustomerConfirm(c.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(customerRepositoryProvider).delete(c.id);
              if (context.mounted) {
                Navigator.pop(context); // back to list
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.customerDeleted)),
                );
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
