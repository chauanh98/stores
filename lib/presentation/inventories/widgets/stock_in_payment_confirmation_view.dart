import 'package:stores/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/stock_in_receipt.dart';
import '../../../domain/entities/supplier.dart';

/// Step 2 of Stock-In Receipt workflow: Payment & Supplier Confirmation View.
/// Matches KiotViet standard and video DATA_IMPORT/video_2026-09-27_07-41-44.mp4 (frame 036 - 040).
///
/// Features:
/// - Navigation link: "Xem hàng trong phiếu >" to toggle back or inspect items.
/// - Supplier selector dropdown.
/// - Financial summary: "Tổng tiền hàng", "Giảm giá" (input), "Cần trả NCC", "Tiền trả NCC" (input).
/// - Payment method toggle: [Tiền mặt], [Chuyển khoản], [Thẻ].
/// - "Tính vào công nợ" preview and toggle.
/// - Receipt note input ("Thêm ghi chú").
/// - Action buttons: "Lưu tạm" and "Hoàn thành".
class StockInPaymentConfirmationView extends StatefulWidget {
  final StockInReceipt receipt;
  final List<Supplier> suppliers;
  final Function({
    required String? supplierId,
    required double discount,
    required double paidAmount,
    required String paymentMethod,
    required String note,
  }) onComplete;
  final VoidCallback onSaveDraft;
  final VoidCallback onViewItems;
  final void Function({
    String? supplierId,
    double? discount,
    double? paidAmount,
    String? paymentMethod,
    String? note,
  })? onStateChanged;

  const StockInPaymentConfirmationView({
    super.key,
    required this.receipt,
    required this.suppliers,
    required this.onComplete,
    required this.onSaveDraft,
    required this.onViewItems,
    this.onStateChanged,
  });

  @override
  State<StockInPaymentConfirmationView> createState() =>
      _StockInPaymentConfirmationViewState();
}

class _StockInPaymentConfirmationViewState
    extends State<StockInPaymentConfirmationView> {
  final NumberFormat _currencyFormat = NumberFormat('#,###', 'vi_VN');

  String? _selectedSupplierId;
  late double _discount;
  late double _paidAmount;
  String _paymentMethod = 'cash'; // 'cash', 'transfer', 'card'
  bool _recordDebt = true;
  late TextEditingController _discountController;
  late TextEditingController _paidAmountController;
  late TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _selectedSupplierId = widget.receipt.supplierId;
    _discount = widget.receipt.discount;
    _paidAmount = widget.receipt.paidAmount ??
        (widget.receipt.totalAmount - widget.receipt.discount)
            .clamp(0.0, double.infinity);
    _paymentMethod = widget.receipt.paymentMethod;

    _discountController = TextEditingController(
      text: _discount > 0 ? _currencyFormat.format(_discount) : '0',
    );
    _paidAmountController = TextEditingController(
      text: _currencyFormat.format(_paidAmount),
    );
    _noteController = TextEditingController(text: widget.receipt.note);
    _noteController.addListener(_notifyParent);
  }

  @override
  void didUpdateWidget(covariant StockInPaymentConfirmationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receipt.totalAmount != widget.receipt.totalAmount ||
        oldWidget.receipt.discount != widget.receipt.discount ||
        oldWidget.receipt.paidAmount != widget.receipt.paidAmount) {
      final oldNet =
          (oldWidget.receipt.totalAmount - oldWidget.receipt.discount)
              .clamp(0.0, double.infinity);
      final wasFullPayment = (_paidAmount - oldNet).abs() < 1.0;
      setState(() {
        _discount = widget.receipt.discount;
        _discountController.text =
            _discount > 0 ? _currencyFormat.format(_discount) : '0';
        if (wasFullPayment || widget.receipt.paidAmount != null) {
          _paidAmount = widget.receipt.paidAmount ?? netPayable;
          _paidAmountController.text = _currencyFormat.format(_paidAmount);
        }
      });
    }
  }

  void _notifyParent() {
    widget.onStateChanged?.call(
      supplierId: _selectedSupplierId,
      discount: _discount,
      paidAmount: _paidAmount,
      paymentMethod: _paymentMethod,
      note: _noteController.text.trim(),
    );
  }

  @override
  void dispose() {
    _noteController.removeListener(_notifyParent);
    _discountController.dispose();
    _paidAmountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double get netPayable =>
      (widget.receipt.totalAmount - _discount).clamp(0.0, double.infinity);

  double get remainingDebt =>
      (netPayable - _paidAmount).clamp(0.0, double.infinity);

  void _handleComplete() {
    // Invariant: If debt is incurred, supplier is required
    if (remainingDebt > 0 &&
        (_selectedSupplierId == null || _selectedSupplierId!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('snackbar_supplier_required'),
          content: Text('Vui lòng chọn Nhà Cung Cấp để ghi nợ'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    _notifyParent();
    widget.onComplete(
      supplierId: _selectedSupplierId,
      discount: _discount,
      paidAmount: _paidAmount,
      paymentMethod: _paymentMethod,
      note: _noteController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Thanh toán & Nhà cung cấp',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              key: const Key('btn_payment_save_draft'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(48, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                _notifyParent();
                widget.onSaveDraft();
              },
              child: const Text(
                'Lưu tạm',
                style: TextStyle(
                  color: AppColors.primaryAction,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Navigation link: "Xem hàng trong phiếu >"
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppColors.grey200),
              ),
              child: ListTile(
                key: const Key('btn_view_receipt_items'),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: const Icon(Icons.receipt_outlined,
                    color: AppColors.primaryAction),
                title: Text(
                  'Xem hàng trong phiếu (${widget.receipt.itemCount} mặt hàng)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryAction,
                    fontSize: 14,
                  ),
                ),
                trailing:
                    const Icon(Icons.chevron_right, color: AppColors.textMuted),
                onTap: () {
                  _notifyParent();
                  widget.onViewItems();
                },
              ),
            ),
            const SizedBox(height: 14),

            // 2. Supplier Selection
            const Text(
              'Nhà cung cấp',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textTitle,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('dropdown_supplier'),
              value: widget.suppliers.any((s) => s.id == _selectedSupplierId)
                  ? _selectedSupplierId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintText: 'Chọn nhà cung cấp',
                prefixIcon:
                    const Icon(Icons.business, color: AppColors.textMuted),
              ),
              items: widget.suppliers.map((s) {
                return DropdownMenuItem<String>(
                  value: s.id,
                  child: Text(
                    '${s.name} (${s.code})',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                );
              }).toList(),
              selectedItemBuilder: (ctx) {
                return widget.suppliers.map((s) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${s.name} (${s.code})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  );
                }).toList();
              },
              onChanged: (val) {
                setState(() => _selectedSupplierId = val);
                _notifyParent();
              },
            ),
            const SizedBox(height: 16),

            // 3. Financial Summary Card
            Card(
              elevation: 0.8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.grey200),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Column(
                  children: [
                    // Tổng tiền hàng
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Tổng tiền hàng:',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textSlate600, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_currencyFormat.format(widget.receipt.totalAmount)} đ',
                            key: const Key('text_total_goods_amount'),
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.textHeadline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Giảm giá phiếu
                    Row(
                      children: [
                        const Text(
                          'Giảm giá:',
                          style: TextStyle(
                              color: AppColors.textSlate600, fontSize: 14),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            key: const Key('input_receipt_discount'),
                            controller: _discountController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.end,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              suffixText: 'đ',
                              isDense: true,
                            ),
                            onChanged: (val) {
                              final parsed = double.tryParse(val
                                      .replaceAll('.', '')
                                      .replaceAll(',', '')) ??
                                  0.0;
                              setState(() {
                                final oldNet = netPayable;
                                final wasFullPayment =
                                    (_paidAmount - oldNet).abs() < 1.0;
                                _discount = parsed;
                                if (wasFullPayment) {
                                  _paidAmount = netPayable;
                                  _paidAmountController.text =
                                      _currencyFormat.format(_paidAmount);
                                }
                              });
                              _notifyParent();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Cần trả NCC
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Cần trả NCC:',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.textTitle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_currencyFormat.format(netPayable)} đ',
                            key: const Key('text_net_payable'),
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryAction,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // Tiền trả NCC
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            const Text(
                              'Tiền trả NCC:',
                              style: TextStyle(
                                  color: AppColors.textSlate600, fontSize: 14),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Quick Action Button: Trả đủ
                                InkWell(
                                  key: const Key('btn_pay_in_full'),
                                  onTap: () {
                                    setState(() {
                                      _paidAmount = netPayable;
                                      _paidAmountController.text =
                                          _currencyFormat.format(_paidAmount);
                                    });
                                    _notifyParent();
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.infoSubtle,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: AppColors.infoBorder),
                                    ),
                                    child: const Text(
                                      'Trả đủ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryAction,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Quick Action Button: Ghi nợ (0đ)
                                InkWell(
                                  key: const Key('btn_pay_zero'),
                                  onTap: () {
                                    setState(() {
                                      _paidAmount = 0.0;
                                      _paidAmountController.text = '0';
                                    });
                                    _notifyParent();
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.dangerSubtle,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: AppColors.dangerBorder),
                                    ),
                                    child: const Text(
                                      'Ghi nợ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.dangerMedium,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('input_paid_amount'),
                          controller: _paidAmountController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.end,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            suffixText: 'đ',
                            isDense: true,
                          ),
                          onChanged: (val) {
                            final parsed = double.tryParse(val
                                    .replaceAll('.', '')
                                    .replaceAll(',', '')) ??
                                0.0;
                            setState(() {
                              _paidAmount = parsed;
                            });
                            _notifyParent();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Tính vào công nợ
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Tính vào công nợ:',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.dangerMedium,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_currencyFormat.format(remainingDebt)} đ',
                            key: const Key('text_remaining_debt'),
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.dangerMedium,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4. Payment Method
            const Text(
              'Hình thức thanh toán',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textTitle,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('payment_cash'),
                  label: const Text('Tiền mặt'),
                  selected: _paymentMethod == 'cash',
                  onSelected: (sel) {
                    if (sel) {
                      setState(() => _paymentMethod = 'cash');
                      _notifyParent();
                    }
                  },
                ),
                ChoiceChip(
                  key: const Key('payment_transfer'),
                  label: const Text('Chuyển khoản'),
                  selected: _paymentMethod == 'transfer',
                  onSelected: (sel) {
                    if (sel) {
                      setState(() => _paymentMethod = 'transfer');
                      _notifyParent();
                    }
                  },
                ),
                ChoiceChip(
                  key: const Key('payment_card'),
                  label: const Text('Thẻ'),
                  selected: _paymentMethod == 'card',
                  onSelected: (sel) {
                    if (sel) {
                      setState(() => _paymentMethod = 'card');
                      _notifyParent();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 5. Debt Accounting Toggle
            SwitchListTile(
              key: const Key('toggle_debt_accounting'),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Tính vào công nợ',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                _recordDebt
                    ? 'Chênh lệch chưa trả sẽ được cộng vào sổ nợ NCC'
                    : 'Không ghi nhận nợ',
                style: const TextStyle(fontSize: 12, color: AppColors.grey600),
              ),
              value: _recordDebt,
              onChanged: (val) => setState(() => _recordDebt = val),
            ),
            const SizedBox(height: 14),

            // 6. Receipt Note Input
            TextFormField(
              key: const Key('input_receipt_note'),
              controller: _noteController,
              decoration: InputDecoration(
                labelText: 'Ghi chú phiếu nhập',
                hintText: 'Thêm ghi chú',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.note_alt_outlined),
              ),
              maxLines: 2,
              onChanged: (val) {
                _notifyParent();
              },
            ),
            const SizedBox(height: 24),

            // 7. Complete Button
            ElevatedButton(
              key: const Key('btn_payment_complete'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAction,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 1,
              ),
              onPressed: _handleComplete,
              child: const Text(
                'Hoàn thành',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
