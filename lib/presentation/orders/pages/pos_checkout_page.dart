import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../application/orders/cart_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/inventory/inventory_providers.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/order_item.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/transaction_type.dart';

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
    final user = ref.watch(authProvider);

    final discountAmount = _isDiscountPercent ? (totalAmount * _discount / 100) : _discount;
    final netPay = (totalAmount - discountAmount).clamp(0.0, double.infinity);
    final returnChange = (_customerPayment - netPay).clamp(0.0, double.infinity);

    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Thanh toán', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  _buildOrderItemsCard(cart, currencyFormat),
                  const SizedBox(height: 12),

                  // 3. Thông tin thanh toán (Tiền hàng, giảm giá, khách đưa)
                  _buildPaymentDetailsCard(totalAmount, netPay, returnChange, currencyFormat),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomActionsBar(context, netPay, cart),
    );
  }

  // 1. Card chọn khách hàng
  Widget _buildCustomerSelectorCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE1E2E4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Khách hàng',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
              ),
              InkWell(
                onTap: () => _showCustomerListBottomSheet(context),
                child: Row(
                  children: const [
                    Text(
                      'Thay đổi',
                      style: TextStyle(color: Color(0xFF0067AC), fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Icon(Icons.chevron_right, color: Color(0xFF0067AC), size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF0067AC).withOpacity(0.06),
                child: const Icon(Icons.person, color: Color(0xFF0067AC)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _selectedCustomer == null
                    ? const Text(
                        'Khách lẻ',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedCustomer!.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_selectedCustomer!.phone} • ${_selectedCustomer!.address}',
                            style: const TextStyle(color: Colors.black54, fontSize: 12),
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

  Widget _buildOrderItemsCard(Map<String, CartItem> cart, NumberFormat format) {
    final user = ref.read(authProvider);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E2E4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Thông tin đơn hàng',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
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
                onTap: user?.isAdmin == true ? () => _showEditPriceDialog(context, ref, item) : null,
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
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (user?.isAdmin == true) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.edit_outlined, size: 13, color: Color(0xFF0067AC)),
                                ]
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Số lượng: ${item.quantity} x ${format.format(item.price)} đ' +
                                  (item.customPrice != null ? ' (Gốc: ${format.format(item.product.price)}đ)' : ''),
                              style: const TextStyle(color: Colors.black54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${format.format(item.total)} đ',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
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

  void _showEditPriceDialog(BuildContext context, WidgetRef ref, CartItem item) {
    final controller = TextEditingController(text: item.price.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Thay đổi giá: ${item.product.name}'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Giá bán mới',
              suffixText: 'đ',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final newPrice = double.tryParse(controller.text.trim());
                if (newPrice != null && newPrice >= 0) {
                  ref.read(cartProvider.notifier).updatePrice(item.product.id, newPrice);
                }
                Navigator.pop(context);
              },
              child: const Text('Cập nhật'),
            ),
          ],
        );
      },
    );
  }

  // 3. Card thông tin thanh toán chi tiết
  Widget _buildPaymentDetailsCard(
    double totalAmount,
    double netPay,
    double returnChange,
    NumberFormat format,
  ) {
    final user = ref.watch(authProvider);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE1E2E4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSummaryDetailRow('Tổng tiền hàng', '${format.format(totalAmount)} đ', false),
          const SizedBox(height: 12),
          // Dòng giảm giá chiết khấu
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('Giảm giá đơn hàng', style: TextStyle(color: Colors.black54, fontSize: 13)),
                  if (user?.isAdmin == true) ...[
                    const SizedBox(width: 8),
                    ToggleButtons(
                      isSelected: [!_isDiscountPercent, _isDiscountPercent],
                      onPressed: (index) {
                        setState(() {
                          _isDiscountPercent = index == 1;
                        });
                      },
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 24),
                      borderRadius: BorderRadius.circular(4),
                      children: const [
                        Text('đ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: const OutlineInputBorder(),
                    suffixText: _isDiscountPercent ? '%' : 'đ',
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
          _buildSummaryDetailRow('Khách cần trả', '${format.format(netPay)} đ', true, color: const Color(0xFF0067AC)),
          const SizedBox(height: 12),
          // Dòng nhập tiền khách đưa
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Khách đưa', style: TextStyle(color: Colors.black54, fontSize: 13)),
              SizedBox(
                width: 120,
                height: 36,
                child: TextField(
                  controller: _paymentController,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: const OutlineInputBorder(),
                    hintText: format.format(netPay),
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  onChanged: (v) {
                    setState(() {
                      _customerPayment = double.tryParse(v) ?? 0.0;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSummaryDetailRow('Tiền thừa trả khách', '${format.format(returnChange)} đ', false, color: Colors.green),
          const SizedBox(height: 12),
          // Phương thức thanh toán
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Phương thức', style: TextStyle(color: Colors.black54, fontSize: 13)),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _paymentMethod,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 13),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _paymentMethod = v;
                      });
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Tiền mặt')),
                    DropdownMenuItem(value: 'transfer', child: Text('Chuyển khoản')),
                  ],
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSummaryDetailRow(String label, String value, bool isBold, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
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
  Widget _buildBottomActionsBar(BuildContext context, double netPay, Map<String, CartItem> cart) {
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
                side: const BorderSide(color: Color(0xFF0067AC)),
                foregroundColor: const Color(0xFF0067AC),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Lưu tạm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
          const SizedBox(width: 12),
          // Nút Thanh toán
          Expanded(
            child: ElevatedButton(
              onPressed: () => _processPayment(netPay, cart),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0067AC),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Thanh toán', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          )
        ],
      ),
    );
  }

  // Hộp thoại Bottom Sheet tìm kiếm khách hàng
  void _showCustomerListBottomSheet(BuildContext context) {
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
              padding: const EdgeInsets.only(top: 16, bottom: 24, left: 16, right: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Chọn khách hàng',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Color(0xFF0067AC), size: 28),
                        onPressed: () {
                          Navigator.pop(context);
                          _showAddCustomerDialog(context);
                        },
                      )
                    ],
                  ),
                  const Divider(color: Color(0xFFEEEEEE)),
                  customersAsync.when(
                    data: (customers) {
                      return Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: customers.length + 1,
                          itemBuilder: (context, idx) {
                            if (idx == 0) {
                              return ListTile(
                                title: const Text('Khách lẻ', style: TextStyle(fontWeight: FontWeight.bold)),
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
                              title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${customer.phone} • ${customer.address}'),
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
                    error: (e, _) => Center(child: Text('Lỗi tải khách hàng: $e')),
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

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Thêm khách hàng', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Họ và tên *', border: OutlineInputBorder()),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập tên' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(labelText: 'Số điện thoại *', border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập số điện thoại' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: 'Địa chỉ', border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final newCust = Customer(
                    id: 'customer_${DateTime.now().millisecondsSinceEpoch}',
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                    email: emailController.text.trim(),
                    address: addressController.text.trim(),
                    purchases: const [],
                  );

                  Navigator.pop(context);
                  setState(() => _isSaving = true);

                  try {
                    await ref.read(customerRepositoryProvider).upsert(newCust);
                    ref.invalidate(customerListNotifierProvider);
                    setState(() {
                      _selectedCustomer = newCust;
                      _isSaving = false;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Thêm khách hàng thành công!'), backgroundColor: Colors.green),
                    );
                  } catch (e) {
                    setState(() => _isSaving = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Lỗi: $e')),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0067AC)),
              child: const Text('Lưu'),
            )
          ],
        );
      },
    );
  }

  // Popup xác nhận Lưu tạm đơn hàng nháp
  void _confirmSaveDraft(BuildContext context, double netPay, Map<String, CartItem> cart) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Lưu đơn nháp'),
          content: const Text('Bạn có muốn lưu đơn hàng này vào danh sách lưu tạm không?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Không'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _submitOrder(netPay, cart, isDraft: true);
              },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0067AC)),
              child: const Text('Lưu tạm'),
            )
          ],
        );
      },
    );
  }

  // Xử lý thực hiện Thanh toán đơn hàng chính thức
  Future<void> _processPayment(double netPay, Map<String, CartItem> cart) async {
    await _submitOrder(netPay, cart, isDraft: false);
  }

  // Submit Order lên Firebase và thực hiện logic kho
  Future<void> _submitOrder(double netPay, Map<String, CartItem> cart, {required bool isDraft}) async {
    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();
      
      // Sử dụng lại mã đơn tạm cũ nếu đang lên đơn từ một đơn tạm
      final activeOrderId = ref.read(activeOrderIdProvider);
      final id = activeOrderId ?? 'HD_${now.millisecondsSinceEpoch}';

      final List<OrderItem> orderItems = cart.values.map((item) {
        return OrderItem(
          productId: item.product.id,
          productName: item.product.name,
          quantity: item.quantity,
          price: item.price,
          warrantyMonths: 12, // Mặc định 12 tháng bảo hành
          purchaseDate: now,
        );
      }).toList();

      final customerId = _selectedCustomer?.id ?? 'khach_le';
      final customerName = _selectedCustomer?.name ?? 'Khách lẻ';

      // Tạo đối tượng hoá đơn/đơn hàng
      // Lưu ý: Ta có thể tuỳ biến hoặc mở rộng thuộc tính hoặc lưu dạng Map phù hợp
      final order = Order(
        id: id,
        customerId: customerId,
        createdAt: now,
        items: orderItems,
        total: netPay,
        status: isDraft ? 'draft' : 'completed',
      );

      // 1) Lưu đơn hàng
      await ref.read(orderRepositoryProvider).create(order);

      // Nếu KHÔNG phải đơn nháp (Đơn chính thức) -> Trừ tồn kho và ghi nhận Xuất kho
      if (!isDraft) {
        final productRepo = ref.read(productRepositoryProvider);
        final inventoryRepo = ref.read(inventoryRepositoryProvider);
        final selectedBranch = ref.read(selectedPOSBranchProvider);

        for (final item in cart.values) {
          // Trừ stock chi nhánh xuất kho được chọn
          final branchStocks = Map<String, int>.from(item.product.branchStocks);
          final currentStock = branchStocks[selectedBranch] ?? 0;
          branchStocks[selectedBranch] = (currentStock - item.quantity).clamp(0, 99999);

          final updatedProduct = item.product.copyWith(branchStocks: branchStocks);
          await productRepo.upsert(updatedProduct);

          // Ghi nhận lịch sử giao dịch kho
          await inventoryRepo.record(InventoryTransaction(
            id: 'export_${now.millisecondsSinceEpoch}_${item.product.id}',
            productId: item.product.id,
            type: TransactionType.export,
            quantity: item.quantity,
            date: now,
            note: id, // Mã hoá đơn
            importPrice: null,
          ));
        }
      }

      // Refresh providers
      ref.invalidate(productListProvider);
      ref.invalidate(orderRepositoryProvider);

      // Reset activeOrderIdProvider nếu là đơn hoàn thành
      if (!isDraft) {
        ref.read(activeOrderIdProvider.notifier).state = null;
      }

      // Clear giỏ hàng Riverpod
      ref.read(cartProvider.notifier).clearCart();

      setState(() => _isSaving = false);

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isDraft ? 'Đơn hàng nháp đã được lưu!' : 'Thanh toán đơn hàng thành công!'),
            backgroundColor: Colors.green,
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
