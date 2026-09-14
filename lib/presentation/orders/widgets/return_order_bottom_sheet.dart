import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/return_order.dart';

class ReturnOrderBottomSheet extends ConsumerStatefulWidget {
  final Order order;
  final Customer? customer;

  const ReturnOrderBottomSheet({
    super.key,
    required this.order,
    this.customer,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Order order,
    Customer? customer,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ReturnOrderBottomSheet(
        order: order,
        customer: customer,
      ),
    );
  }

  @override
  ConsumerState<ReturnOrderBottomSheet> createState() =>
      _ReturnOrderBottomSheetState();
}

class _ReturnOrderBottomSheetState
    extends ConsumerState<ReturnOrderBottomSheet> {
  final Map<String, int> _returnQuantities = {};
  final _reasonController = TextEditingController();
  String _refundPaymentMethod = 'cash'; // 'cash' or 'transfer'
  bool _isLoading = false;

  final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  @override
  void initState() {
    super.initState();
    for (final item in widget.order.items) {
      _returnQuantities[item.productId] = 0;
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _setSelectAll(bool selectAll) {
    setState(() {
      for (final item in widget.order.items) {
        _returnQuantities[item.productId] =
            selectAll ? item.activeQuantity : 0;
      }
    });
  }

  void _updateQuantity(String productId, int newQty, int maxQty) {
    setState(() {
      _returnQuantities[productId] = newQty.clamp(0, maxQty);
    });
  }

  double get _totalReturnAmount {
    double total = 0.0;
    for (final item in widget.order.items) {
      final qty = _returnQuantities[item.productId] ?? 0;
      total += qty * item.price;
    }
    return total;
  }

  int get _totalReturnItemsCount {
    int count = 0;
    for (final qty in _returnQuantities.values) {
      count += qty;
    }
    return count;
  }

  double get _debtDeducted {
    final remainingDebt = widget.order.remainingDebt;
    return min(_totalReturnAmount, remainingDebt);
  }

  double get _cashRefunded {
    return (_totalReturnAmount - _debtDeducted).clamp(0.0, double.infinity);
  }

  Future<void> _submitReturn() async {
    final totalQty = _totalReturnItemsCount;
    if (totalQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn ít nhất 1 sản phẩm để trả hàng.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final currentUser = ref.read(authProvider);
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng đăng nhập để thực hiện trả hàng.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final storeId = widget.order.storeId ??
          (currentUser.storeId.isNotEmpty ? currentUser.storeId : 'store_001');

      final returnItems = <ReturnOrderItem>[];
      for (final item in widget.order.items) {
        final qty = _returnQuantities[item.productId] ?? 0;
        if (qty > 0) {
          returnItems.add(
            ReturnOrderItem(
              productId: item.productId,
              productName: item.productName,
              price: item.price,
              quantity: qty,
            ),
          );
        }
      }

      final useCase = ref.read(processReturnOrderUseCaseProvider);
      final result = await useCase.execute(
        originalOrder: widget.order,
        returnItems: returnItems,
        storeId: storeId,
        currentUser: currentUser,
        reason: _reasonController.text.trim().isNotEmpty
            ? _reasonController.text.trim()
            : null,
        refundPaymentMethod: _refundPaymentMethod,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Trả hàng thành công: Hoàn ${_currencyFormat.format(result.cashRefunded)} đ'
              '${result.debtDeducted > 0 ? ', trừ nợ ${_currencyFormat.format(result.debtDeducted)} đ' : ''}.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi trả hàng: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveReturn = widget.order.items.any((i) => i.activeQuantity > 0);
    final isAllSelected = hasActiveReturn &&
        widget.order.items.every(
            (i) => _returnQuantities[i.productId] == i.activeQuantity);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trả hàng - Hóa đơn ${widget.order.id}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Chọn sản phẩm và số lượng cần trả lại',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _isLoading ? null : () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 16, color: AppColors.divider),

          // Action Toolbar: Select All / Deselect All
          if (hasActiveReturn) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Danh sách sản phẩm (${widget.order.items.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _setSelectAll(!isAllSelected),
                  icon: Icon(
                    isAllSelected
                        ? Icons.remove_done
                        : Icons.done_all,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  label: Text(
                    isAllSelected ? 'Bỏ chọn tất cả' : 'Chọn trả tất cả',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Item list
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ...widget.order.items.map((item) {
                    final activeQty = item.activeQuantity;
                    final currentReturnQty =
                        _returnQuantities[item.productId] ?? 0;
                    final isFullyReturned = item.isFullyReturned;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isFullyReturned
                            ? Colors.grey.shade100
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: currentReturnQty > 0
                              ? AppColors.primary
                              : AppColors.border,
                          width: currentReturnQty > 0 ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: isFullyReturned
                                        ? Colors.black45
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${_currencyFormat.format(item.price)} đ',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Text(
                                      'Đã mua: ${item.quantity}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    if (item.returnedQuantity > 0) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Đã trả: ${item.returnedQuantity}',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (isFullyReturned) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Đã trả hết',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ] else ...[
                            // Stepper
                            Row(
                              children: [
                                IconButton(
                                  key: Key('decrement_return_${item.productId}'),
                                  icon: const Icon(
                                      Icons.remove_circle_outline),
                                  color: currentReturnQty > 0
                                      ? AppColors.primary
                                      : Colors.black26,
                                  onPressed: currentReturnQty > 0
                                      ? () => _updateQuantity(
                                            item.productId,
                                            currentReturnQty - 1,
                                            activeQty,
                                          )
                                      : null,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: currentReturnQty > 0
                                        ? AppColors.primary.withOpacity(0.1)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$currentReturnQty / $activeQty',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: currentReturnQty > 0
                                          ? AppColors.primary
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: Key('increment_return_${item.productId}'),
                                  icon:
                                      const Icon(Icons.add_circle_outline),
                                  color: currentReturnQty < activeQty
                                      ? AppColors.primary
                                      : Colors.black26,
                                  onPressed: currentReturnQty < activeQty
                                      ? () => _updateQuantity(
                                            item.productId,
                                            currentReturnQty + 1,
                                            activeQty,
                                          )
                                      : null,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 12),

                  // Calculation Live Preview Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        _buildSummaryRow(
                          'Tổng tiền trả hàng:',
                          '${_currencyFormat.format(_totalReturnAmount)} đ',
                          isBold: true,
                        ),
                        if (_debtDeducted > 0) ...[
                          const SizedBox(height: 6),
                          _buildSummaryRow(
                            'Trừ vào công nợ HĐ:',
                            '-${_currencyFormat.format(_debtDeducted)} đ',
                            color: Colors.orange.shade800,
                          ),
                        ],
                        const Divider(height: 14, color: AppColors.divider),
                        _buildSummaryRow(
                          'Hoàn tiền thực tế cho khách:',
                          '${_currencyFormat.format(_cashRefunded)} đ',
                          color: Colors.green.shade700,
                          isBold: true,
                          fontSize: 14,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Payment method for refund
                  if (_cashRefunded > 0) ...[
                    Row(
                      children: [
                        const Text(
                          'Hình thức hoàn tiền: ',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Tiền mặt',
                              style: TextStyle(fontSize: 12)),
                          selected: _refundPaymentMethod == 'cash',
                          onSelected: (val) {
                            if (val) {
                              setState(() => _refundPaymentMethod = 'cash');
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Chuyển khoản',
                              style: TextStyle(fontSize: 12)),
                          selected: _refundPaymentMethod == 'transfer',
                          onSelected: (val) {
                            if (val) {
                              setState(() => _refundPaymentMethod = 'transfer');
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Return Reason
                  TextField(
                    key: const Key('return_order_reason_field'),
                    controller: _reasonController,
                    decoration: InputDecoration(
                      hintText: 'Nhập lý do trả hàng (không bắt buộc)...',
                      labelText: 'Lý do trả hàng',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Submit Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              key: const Key('confirm_return_order_button'),
              onPressed:
                  (_totalReturnItemsCount <= 0 || _isLoading) ? null : _submitReturn,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _totalReturnItemsCount > 0
                          ? 'Xác nhận trả hàng ($_totalReturnItemsCount sản phẩm)'
                          : 'Chọn sản phẩm để trả hàng',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    Color? color,
    bool isBold = false,
    double fontSize = 13,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            color: Colors.black54,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}
