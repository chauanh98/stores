import '../../common/utils/number_parsing.dart';
import 'package:flutter/material.dart';
import '../../common/utils/route_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/customers/customers_providers.dart';
import '../../../application/inventory/inventory_providers.dart';
import '../../../application/notifications/notification_dispatcher.dart';
import '../../../application/orders/cart_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/settings/store_payment_config_providers.dart';
import '../../../core/utils/combo_helper.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../core/utils/invoice_print_helper.dart';
import '../../../core/utils/order_code_resolver.dart';
import '../../../core/utils/smart_cash_helper.dart';
import '../../../core/utils/store_resolver_helper.dart';
import '../../../core/utils/vietqr_helper.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/customer_debt_transaction.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/order_item.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/purchase.dart';
import '../../../domain/entities/store_payment_config.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/entities/user_account.dart';
import '../../../domain/entities/warranty.dart';
import 'pos_checkout_page.dart';

class POSPaymentPage extends ConsumerStatefulWidget {
  final Customer? initialCustomer;
  final double initialDiscount;
  final bool isDiscountPercent;
  final String? initialNote;

  const POSPaymentPage({
    super.key,
    this.initialCustomer,
    this.initialDiscount = 0.0,
    this.isDiscountPercent = false,
    this.initialNote,
  });

  @override
  ConsumerState<POSPaymentPage> createState() => _POSPaymentPageState();
}

class _POSPaymentPageState extends ConsumerState<POSPaymentPage> {
  Customer? _selectedCustomer;

  final _discountController = TextEditingController(text: '0');
  final _paymentController = TextEditingController();
  final _cashPaymentController = TextEditingController();
  final _transferPaymentController = TextEditingController();
  final _noteController = TextEditingController();

  double _discount = 0.0;
  bool _isDiscountPercent = false;
  double _customerPayment = 0.0;
  double _splitCashAmount = 0.0;
  double _splitTransferAmount = 0.0;
  String _paymentMethod = 'cash'; // 'cash', 'transfer', hoặc 'split'

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedCustomer = widget.initialCustomer;
    _discount = widget.initialDiscount;
    _isDiscountPercent = widget.isDiscountPercent;
    _discountController.text = _discount.toStringAsFixed(0);
    if (widget.initialNote != null && widget.initialNote!.isNotEmpty) {
      _noteController.text = widget.initialNote!;
    }
  }

  @override
  void dispose() {
    _discountController.dispose();
    _paymentController.dispose();
    _cashPaymentController.dispose();
    _transferPaymentController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cart = ref.watch(cartProvider);
    final totalAmount = ref.watch(cartTotalAmountProvider);
    final paymentConfig = ref.watch(storePaymentConfigProvider);
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    final discountAmount =
        _isDiscountPercent ? (totalAmount * _discount / 100) : _discount;
    final netPay = (totalAmount - discountAmount).clamp(0.0, double.infinity);

    final double actualPaid;
    if (_paymentMethod == 'split') {
      actualPaid = _splitCashAmount + _splitTransferAmount;
    } else {
      actualPaid =
          _paymentController.text.trim().isEmpty ? 0.0 : _customerPayment;
    }

    final remainingAmount = (netPay - actualPaid).clamp(0.0, double.infinity);
    final returnChange = (actualPaid - netPay).clamp(0.0, double.infinity);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context, _selectedCustomer),
        ),
        title: Text(
          l10n?.payment ?? 'Thanh toán',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: false,
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: _isSaving
          ? const Center(child: LoadingIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tóm tắt khách hàng
                  _buildCustomerSummaryCard(context),
                  const SizedBox(height: 8),

                  // Xem hàng trong đơn (2) >
                  _buildOrderItemsCollapsibleCard(cart, currencyFormat),
                  const SizedBox(height: 12),

                  // Thông tin thanh toán chi tiết
                  _buildPaymentDetailsCard(
                    context,
                    totalAmount,
                    netPay,
                    actualPaid,
                    remainingAmount,
                    returnChange,
                    paymentConfig,
                    currencyFormat,
                    cart,
                  ),
                  const SizedBox(height: 12),

                  // Ghi chú đơn hàng
                  _buildOrderNoteCard(context),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomActionsBar(
        context,
        netPay,
        cart,
        totalAmount: totalAmount,
        discountAmount: discountAmount,
      ),
    );
  }

  // Row chọn/thay đổi khách hàng
  Widget _buildCustomerSummaryCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    return InkWell(
      onTap: () async {
        await showCustomerSelectionSheet(
          context: context,
          onCustomerSelected: (cust) {
            setState(() => _selectedCustomer = cust);
          },
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            const Icon(Icons.person_outline,
                size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedCustomer?.name ?? (l10n?.retailCustomer ?? 'Khách lẻ'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (_selectedCustomer != null &&
                _selectedCustomer!.displayCurrentDebt > 0)
              Flexible(
                  child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  l10n?.orderRemainingDebtTag(currencyFormat
                          .format(_selectedCustomer!.displayCurrentDebt)) ??
                      'Nợ: ${currencyFormat.format(_selectedCustomer!.displayCurrentDebt)}đ',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  // Xem hàng trong đơn (collapsible)
  Widget _buildOrderItemsCollapsibleCard(
      Map<String, CartItem> cart, NumberFormat format) {
    final l10n = AppLocalizations.of(context);
    final totalQty = cart.values.fold<int>(0, (s, i) => s + i.quantity);
    Widget buildCartRow(CartItem item) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${item.quantity}x ${item.product.name}',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.45),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${format.format(item.total)} đ',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (item.discount > 0 ||
                (item.note != null && item.note!.trim().isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 14),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    if (item.discount > 0)
                      Text(
                        'Giảm: -${format.format(item.totalDiscount)}đ (${item.isDiscountPercent ? "${NumberFormat.compact().format(item.discount)}%" : "${format.format(item.discount)}đ/sp"})',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (item.discount > 0 &&
                        item.note != null &&
                        item.note!.trim().isNotEmpty)
                      const Text('•',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textMuted)),
                    if (item.note != null && item.note!.trim().isNotEmpty)
                      Text(
                        '📝 ${item.note}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          title: Text(
            l10n?.posViewCartItems(totalQty) ??
                'Xem hàng trong đơn ($totalQty)',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          childrenPadding:
              const EdgeInsets.only(left: 14, right: 14, bottom: 12),
          // Big carts: bounded, lazily-built list instead of building every row.
          children: cart.length <= 12
              ? cart.values.map(buildCartRow).toList()
              : [
                  SizedBox(
                    height: 320,
                    child: ListView.builder(
                      itemCount: cart.length,
                      itemBuilder: (_, i) =>
                          buildCartRow(cart.values.elementAt(i)),
                    ),
                  ),
                ],
        ),
      ),
    );
  }

  // Ghi chú đơn hàng compact
  Widget _buildOrderNoteCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.notes_rounded,
              size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _noteController,
              decoration: InputDecoration(
                hintText: l10n?.posOrderNoteHint ??
                    'Nhập ghi chú cho đơn hàng (nếu có)...',
                hintStyle:
                    const TextStyle(fontSize: 13, color: AppColors.textMuted),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // Card thông tin thanh toán chi tiết
  Widget _buildPaymentDetailsCard(
    BuildContext context,
    double totalAmount,
    double netPay,
    double actualPaid,
    double remainingAmount,
    double returnChange,
    StorePaymentConfig paymentConfig,
    NumberFormat format,
    Map<String, CartItem> cart,
  ) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authProvider);
    final totalItemsCount =
        cart.values.fold<int>(0, (sum, i) => sum + i.quantity);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Tổng tiền hàng
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                  child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    l10n?.totalProductAmount ?? 'Tổng tiền hàng',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$totalItemsCount',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )),
              const SizedBox(width: 8),
              Flexible(
                  child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  format.format(totalAmount),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              )),
            ],
          ),
          const Divider(height: 20, color: AppColors.borderLight),

          // 2. Giảm giá (%)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                  child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    _isDiscountPercent
                        ? (l10n?.posDiscountPercent ?? 'Giảm giá (%)')
                        : (l10n?.posDiscountAmount ?? 'Giảm giá (đ)'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (user?.isAdmin == true) ...[
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isDiscountPercent = !_isDiscountPercent;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: Text(
                          _isDiscountPercent
                              ? (l10n?.posSwitchToVnd ?? 'Đổi sang đ')
                              : (l10n?.posSwitchToPercent ?? 'Đổi sang %'),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              )),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                height: 32,
                child: TextField(
                  key: const Key('pos_payment_discount_textfield'),
                  controller: _discountController,
                  enabled: user?.isAdmin == true,
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    isDense: true,
                    border: const UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    suffixText: _isDiscountPercent ? '%' : 'đ',
                    suffixStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  onChanged: (v) {
                    setState(() {
                      _discount = tryParseFinite(v) ?? 0.0;
                    });
                  },
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: AppColors.borderLight),

          // 3. Thu khác
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  l10n?.posOtherSurcharge ?? 'Thu khác',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Text(
                '0',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: AppColors.borderLight),

          // 4. Khách cần trả
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  l10n?.amountToPay ?? 'Khách cần trả',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    format.format(netPay),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: AppColors.borderLight),

          // 5. Khách thanh toán
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  l10n?.posCustomerPaidAmount ?? 'Khách thanh toán',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                  child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  // Nút Trả đủ
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.25)),
                      ),
                      child: Text(
                        l10n?.posPayExactAmount ?? 'Trả đủ',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  // Nút Xóa
                  InkWell(
                    onTap: () {
                      _paymentController.clear();
                      setState(() {
                        _customerPayment = 0.0;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.grey400.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        l10n?.delete ?? 'Xóa',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    height: 32,
                    child: TextField(
                      key: const Key('pos_payment_customer_payment_textfield'),
                      controller: _paymentController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        CurrencyInputFormatter(),
                      ],
                      decoration: const InputDecoration(
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        isDense: true,
                        hintText: '0',
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primary),
                        ),
                      ),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
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
                          _customerPayment = tryParseFinite(raw) ?? 0.0;
                        });
                      },
                    ),
                  ),
                ],
              )),
            ],
          ),
          const SizedBox(height: 14),

          // 6. Payment Method Tabs & More (•••)
          _buildPaymentMethodsTabBar(netPay, format),
          const SizedBox(height: 10),

          // 7. Chi tiết phương thức thanh toán
          if (_paymentMethod == 'cash') ...[
            _buildQuickCashChips(netPay, format),
          ] else if (_paymentMethod == 'transfer') ...[
            _buildVietQRSection(
              netPay,
              'HD_POS',
              paymentConfig,
              format,
            ),
          ] else if (_paymentMethod == 'split') ...[
            _buildSplitPaymentSummary(netPay, format),
          ] else if (_paymentMethod == 'card') ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n?.posCardPaymentHint ??
                    'Thanh toán qua máy POS quẹt thẻ ngân hàng',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic),
              ),
            ),
          ] else if (_paymentMethod == 'wallet') ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n?.posEWalletPaymentHint ??
                    'Thanh toán qua ví điện tử (MoMo, ZaloPay, ShopeePay)',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // 8. Box "Tính vào công nợ" chuẩn KiotViet
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF6F7F9),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    l10n?.posRecordAsCustomerDebt ?? 'Tính vào công nợ',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                    child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    remainingAmount > 0
                        ? '-${format.format(remainingAmount)}'
                        : (returnChange > 0
                            ? (l10n?.posRemainingChangeDue(
                                    format.format(returnChange)) ??
                                'Tiền còn lại: +${format.format(returnChange)} đ')
                            : '0'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: remainingAmount > 0
                          ? AppColors.textPrimary
                          : (returnChange > 0
                              ? AppColors.success
                              : AppColors.textPrimary),
                    ),
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Payment Methods Tab Bar chuẩn KiotViet
  Widget _buildPaymentMethodsTabBar(double netPay, NumberFormat format) {
    final l10n = AppLocalizations.of(context);
    final methods = [
      {'id': 'cash', 'label': l10n?.cash ?? 'Tiền mặt'},
      {
        'id': 'transfer',
        'label': l10n?.posMethodTransferShort ?? 'Chuyển\nkhoản'
      },
      {'id': 'card', 'label': l10n?.posMethodCard ?? 'Thẻ'},
      {'id': 'wallet', 'label': l10n?.posMethodWallet ?? 'Ví'},
    ];

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: methods.map((m) {
                final isSelected = _paymentMethod == m['id'];
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _paymentMethod = m['id']!;
                        if (_paymentMethod == 'cash') {
                          if (_paymentController.text.trim().isEmpty) {
                            _customerPayment = 0.0;
                          }
                        } else if (_paymentMethod == 'transfer') {
                          _customerPayment = netPay;
                          _paymentController.text = format.format(netPay);
                        }
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            isSelected ? AppColors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                )
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                m['label']!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                  height: 1.1,
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(height: 2),
                                Container(
                                  width: 14,
                                  height: 2.5,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            ],
                          )),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Nút ••• mở Thanh toán kết hợp
        InkWell(
          onTap: () => _showSplitPaymentModal(context, netPay, format),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _paymentMethod == 'split'
                  ? AppColors.primary.withOpacity(0.12)
                  : const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(10),
              border: _paymentMethod == 'split'
                  ? Border.all(color: AppColors.primary)
                  : null,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.more_horiz,
              color: _paymentMethod == 'split'
                  ? AppColors.primary
                  : const Color(0xFF333333),
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  // Tóm tắt split payment khi phương thức là 'split'
  Widget _buildSplitPaymentSummary(double netPay, NumberFormat format) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  l10n?.posSplitPaymentTitle ?? 'Thanh toán kết hợp:',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _showSplitPaymentModal(context, netPay, format),
                child: Text(
                  l10n?.posChangeAction ?? 'Thay đổi',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_splitCashAmount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(l10n?.posSplitCashLabel ?? '• Tiền mặt:',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${format.format(_splitCashAmount)} đ',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          if (_splitTransferAmount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(l10n?.posSplitTransferLabel ?? '• Chuyển khoản:',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${format.format(_splitTransferAmount)} đ',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // Modal Thanh toán kết hợp (Chuẩn frame_comb.png)
  void _showSplitPaymentModal(
    BuildContext context,
    double netPay,
    NumberFormat format,
  ) {
    double tempCash = _splitCashAmount > 0
        ? _splitCashAmount
        : (_paymentMethod == 'cash' ? _customerPayment : 0.0);
    double tempTransfer = _splitTransferAmount > 0
        ? _splitTransferAmount
        : (_paymentMethod == 'transfer' ? _customerPayment : 0.0);
    double tempCard = 0.0;
    double tempWallet = 0.0;

    bool useCash = tempCash > 0 || (_paymentMethod == 'cash');
    bool useTransfer = tempTransfer > 0 || (_paymentMethod == 'transfer');
    bool useCard = _paymentMethod == 'card';
    bool useWallet = _paymentMethod == 'wallet';

    final cashCtrl = TextEditingController(
        text: tempCash > 0 ? format.format(tempCash) : '');
    final transferCtrl = TextEditingController(
        text: tempTransfer > 0 ? format.format(tempTransfer) : '');
    final cardCtrl = TextEditingController(
        text: tempCard > 0 ? format.format(tempCard) : '');
    final walletCtrl = TextEditingController(
        text: tempWallet > 0 ? format.format(tempWallet) : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final l10n =
                AppLocalizations.of(ctx) ?? AppLocalizations.of(context);
            final currentPaid = (useCash ? tempCash : 0.0) +
                (useTransfer ? tempTransfer : 0.0) +
                (useCard ? tempCard : 0.0) +
                (useWallet ? tempWallet : 0.0);

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Color(0xFFF6F7F9),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    decoration: const BoxDecoration(
                      color: AppColors.white,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                          onPressed: () => closeRoute(modalCtx),
                        ),
                        Expanded(
                          child: Text(
                            l10n?.posSplitPaymentHeader ?? 'Thanh toán kết hợp',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Summary Card
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: Text(
                                          l10n?.amountToPay ?? 'Khách cần trả',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 14,
                                              color: AppColors.textSecondary)),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          format.format(netPay),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(
                                    height: 20, color: AppColors.borderLight),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: Text(
                                          l10n?.posCustomerPaidAmount ??
                                              'Khách thanh toán',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 14,
                                              color: AppColors.textSecondary)),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          format.format(currentPaid),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Phương thức: Tiền mặt
                          _buildSplitMethodRow(
                            title: l10n?.cash ?? 'Tiền mặt',
                            isChecked: useCash,
                            controller: cashCtrl,
                            format: format,
                            onChangedCheck: (val) {
                              setModalState(() {
                                useCash = val ?? false;
                                if (!useCash) {
                                  tempCash = 0.0;
                                  cashCtrl.clear();
                                }
                              });
                            },
                            onAmountChanged: (amt) {
                              setModalState(() {
                                tempCash = amt;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          // Phương thức: Chuyển khoản
                          _buildSplitMethodRow(
                            title:
                                l10n?.paymentMethodTransfer ?? 'Chuyển khoản',
                            isChecked: useTransfer,
                            controller: transferCtrl,
                            format: format,
                            onChangedCheck: (val) {
                              setModalState(() {
                                useTransfer = val ?? false;
                                if (!useTransfer) {
                                  tempTransfer = 0.0;
                                  transferCtrl.clear();
                                }
                              });
                            },
                            onAmountChanged: (amt) {
                              setModalState(() {
                                tempTransfer = amt;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          // Phương thức: Thẻ
                          _buildSplitMethodRow(
                            title: l10n?.posMethodCard ?? 'Thẻ',
                            isChecked: useCard,
                            controller: cardCtrl,
                            format: format,
                            onChangedCheck: (val) {
                              setModalState(() {
                                useCard = val ?? false;
                                if (!useCard) {
                                  tempCard = 0.0;
                                  cardCtrl.clear();
                                }
                              });
                            },
                            onAmountChanged: (amt) {
                              setModalState(() {
                                tempCard = amt;
                              });
                            },
                          ),
                          const SizedBox(height: 12),

                          // Phương thức: Ví
                          _buildSplitMethodRow(
                            title: l10n?.posMethodWallet ?? 'Ví',
                            isChecked: useWallet,
                            controller: walletCtrl,
                            format: format,
                            onChangedCheck: (val) {
                              setModalState(() {
                                useWallet = val ?? false;
                                if (!useWallet) {
                                  tempWallet = 0.0;
                                  walletCtrl.clear();
                                }
                              });
                            },
                            onAmountChanged: (amt) {
                              setModalState(() {
                                tempWallet = amt;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Action [ Xong ]
                  Container(
                    color: AppColors.white,
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 12,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _splitCashAmount = useCash ? tempCash : 0.0;
                            _splitTransferAmount =
                                useTransfer ? tempTransfer : 0.0;
                            if (useCash &&
                                !useTransfer &&
                                !useCard &&
                                !useWallet) {
                              _paymentMethod = 'cash';
                              _customerPayment = tempCash;
                              _paymentController.text = format.format(tempCash);
                            } else if (useTransfer &&
                                !useCash &&
                                !useCard &&
                                !useWallet) {
                              _paymentMethod = 'transfer';
                              _customerPayment = tempTransfer;
                              _paymentController.text =
                                  format.format(tempTransfer);
                            } else {
                              _paymentMethod = 'split';
                            }
                          });
                          closeRoute(modalCtx);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          l10n?.doneBtn ?? 'Xong',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Row cho từng method trong split modal
  Widget _buildSplitMethodRow({
    required String title,
    required bool isChecked,
    required TextEditingController controller,
    required NumberFormat format,
    required ValueChanged<bool?> onChangedCheck,
    required ValueChanged<double> onAmountChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: isChecked,
                onChanged: onChangedCheck,
                activeColor: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (isChecked) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.grey400.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text(
                      'VND',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        CurrencyInputFormatter(),
                      ],
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        hintText: '0',
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primary),
                        ),
                      ),
                      onChanged: (v) {
                        final raw = v.replaceAll('.', '').replaceAll(',', '');
                        final amt = tryParseFinite(raw) ?? 0.0;
                        onAmountChanged(amt);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickCashChips(double netPay, NumberFormat format) {
    final l10n = AppLocalizations.of(context);
    // NaN / infinite totals (corrupt data, absurd input) must not reach the
    // helper: `ceil()` on them throws.
    if (!netPay.isFinite) return const SizedBox.shrink();
    final suggestions = SmartCashHelper.generateSmartCashSuggestions(netPay);
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          l10n?.posSmartCashSuggestions ?? 'Gợi ý tiền mặt thông minh:',
          style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: suggestions.map((suggestedAmount) {
              final isExact = (suggestedAmount - netPay).abs() < 1;
              final label = isExact
                  ? (l10n?.posExactCashSuggestion(
                          format.format(suggestedAmount)) ??
                      '${format.format(suggestedAmount)} đ (Trả đủ)')
                  : '${format.format(suggestedAmount)} đ';

              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  backgroundColor: isExact
                      ? AppColors.primary.withOpacity(0.12)
                      : AppColors.grey400.withOpacity(0.08),
                  side: BorderSide(
                    color: isExact ? AppColors.primary : AppColors.border,
                  ),
                  label: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isExact ? FontWeight.bold : FontWeight.w600,
                      color:
                          isExact ? AppColors.primary : AppColors.textPrimary,
                    ),
                  ),
                  onPressed: () {
                    final text = format.format(suggestedAmount);
                    _paymentController.text = text;
                    _paymentController.selection =
                        TextSelection.collapsed(offset: text.length);
                    setState(() {
                      _customerPayment = suggestedAmount;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildVietQRSection(
    double amount,
    String orderCode,
    StorePaymentConfig config,
    NumberFormat format,
  ) {
    if (config.accountNo.isEmpty || config.bankId.isEmpty || amount <= 0) {
      return const SizedBox.shrink();
    }

    final qrUrl = VietQRHelper.buildVietQRImageUrl(
      bankId: config.bankId,
      accountNo: config.accountNo,
      accountName: config.accountName,
      amount: amount,
      addInfo: orderCode,
    );

    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_2,
                        color: AppColors.primary, size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n?.posVietQrTitle(format.format(amount)) ??
                            'Mã VietQR (${format.format(amount)} đ)',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    l10n?.posVietQrAutoMatch ?? 'Tự động khớp',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: InkWell(
              onTap: () => _showEnlargedQRDialog(
                context,
                qrUrl,
                amount,
                config,
                format,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        qrUrl,
                        width: 270,
                        height: 270,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const SizedBox(
                            width: 270,
                            height: 270,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => Container(
                          width: 270,
                          height: 270,
                          padding: const EdgeInsets.all(16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.borderLight),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            l10n?.posVietQrLoadError ??
                                'Không thể nạp ảnh VietQR',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.zoom_in,
                            size: 15, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            l10n?.posTapToEnlargeQr ??
                                'Chạm để phóng to toàn màn hình',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Text(
                  config.bankName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'STK: ${config.accountNo}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: config.accountNo));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n?.posCopiedBankAccount ??
                                'Đã sao chép số tài khoản!'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: const Icon(Icons.copy,
                          size: 16, color: AppColors.primary),
                    ),
                  ],
                ),
                if (config.accountName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    config.accountName.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEnlargedQRDialog(
    BuildContext context,
    String qrUrl,
    double amount,
    StorePaymentConfig config,
    NumberFormat format,
  ) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n?.posTransferQrDialogTitle ?? 'Mã QR Chuyển Khoản',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(dialogCtx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n?.posTransferAmountLabel(format.format(amount)) ??
                    'Số tiền: ${format.format(amount)} đ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    qrUrl,
                    width: 320,
                    height: 320,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => SizedBox(
                      width: 320,
                      height: 320,
                      child: Center(
                        child:
                            Text(l10n?.posQrLoadError ?? 'Không thể tải mã QR'),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${config.bankName} - ${config.accountNo}\n${config.accountName.toUpperCase()}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Thanh hành động dưới cùng: Chỉ 1 nút [Thanh toán] duy nhất chuẩn KiotViet
  Widget _buildBottomActionsBar(
    BuildContext context,
    double netPay,
    Map<String, CartItem> cart, {
    double totalAmount = 0.0,
    double discountAmount = 0.0,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: cart.isEmpty || _isSaving
                ? null
                : () => _processPayment(
                      netPay,
                      cart,
                      totalAmount: totalAmount,
                      discountAmount: discountAmount,
                    ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              l10n.checkout,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Xử lý thực hiện Thanh toán đơn hàng chính thức
  Future<void> _processPayment(
    double netPay,
    Map<String, CartItem> cart, {
    double totalAmount = 0.0,
    double discountAmount = 0.0,
  }) async {
    await _submitOrder(
      netPay,
      cart,
      isDraft: false,
      totalAmount: totalAmount,
      discountAmount: discountAmount,
    );
  }

  // Submit đơn hàng
  Future<void> _submitOrder(
    double netPay,
    Map<String, CartItem> cart, {
    required bool isDraft,
    double totalAmount = 0.0,
    double discountAmount = 0.0,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (cart.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(l10n?.posCartIsEmptyWarning ?? 'Giỏ hàng đang trống!'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }
    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();
      final selectedBranch = ref.read(selectedPOSBranchProvider);

      // Sử dụng lại mã đơn tạm cũ nếu đang lên đơn từ một đơn tạm (không chứa ký tự không hợp lệ)
      final activeOrderId = ref.read(activeOrderIdProvider);
      final String id;
      if (activeOrderId != null &&
          activeOrderId.isNotEmpty &&
          !activeOrderId.contains('.')) {
        id = activeOrderId;
      } else {
        final originalOrder = ref.read(editingOriginalOrderProvider);
        if (originalOrder != null) {
          id = await OrderCodeResolver.resolveVersionedOrderCode(
            ref,
            originalOrderId: originalOrder.id,
            storeId: selectedBranch,
          );
        } else {
          id = await OrderCodeResolver.resolveNextOrderCode(ref,
              storeId: selectedBranch);
        }
      }

      final List<OrderItem> orderItems = cart.values.map((item) {
        return OrderItem(
          productId: item.product.id,
          productName: item.product.name,
          quantity: item.quantity,
          price: item.effectivePrice,
          originalPrice: item.price,
          discount: item.discount,
          isDiscountPercent: item.isDiscountPercent,
          note: item.note,
          warrantyMonths: 12,
          // Mặc định 12 tháng bảo hành
          purchaseDate: now,
        );
      }).toList();

      final customerId = _selectedCustomer?.id ?? 'khach_le';

      final double paidAmount;
      final double? finalCashAmount;
      final double? finalTransferAmount;

      if (isDraft) {
        paidAmount = 0.0;
        finalCashAmount = null;
        finalTransferAmount = null;
      } else if (_paymentMethod == 'split') {
        if (_cashPaymentController.text.trim().isEmpty &&
            _transferPaymentController.text.trim().isEmpty) {
          finalCashAmount = _splitCashAmount;
          finalTransferAmount = _splitTransferAmount > 0
              ? _splitTransferAmount
              : (netPay - _splitCashAmount).clamp(0.0, netPay);
          paidAmount =
              (finalCashAmount + finalTransferAmount).clamp(0.0, netPay);
        } else {
          finalCashAmount = _splitCashAmount;
          finalTransferAmount = _splitTransferAmount;
          paidAmount =
              (finalCashAmount + finalTransferAmount).clamp(0.0, netPay);
        }
      } else if (_paymentMethod == 'transfer') {
        if (_paymentController.text.trim().isEmpty) {
          paidAmount = netPay;
        } else {
          paidAmount = _customerPayment.clamp(0.0, netPay);
        }
        finalCashAmount = 0.0;
        finalTransferAmount = paidAmount;
      } else if (_paymentMethod == 'card' || _paymentMethod == 'wallet') {
        if (_paymentController.text.trim().isEmpty) {
          paidAmount = netPay;
        } else {
          paidAmount = _customerPayment.clamp(0.0, netPay);
        }
        finalCashAmount = 0.0;
        finalTransferAmount = paidAmount;
      } else {
        // 'cash'
        if (_paymentController.text.trim().isEmpty) {
          paidAmount = 0.0;
        } else {
          paidAmount = _customerPayment.clamp(0.0, netPay);
        }
        finalCashAmount = paidAmount;
        finalTransferAmount = 0.0;
      }

      final double debtAmount =
          isDraft ? 0.0 : (netPay - paidAmount).clamp(0.0, netPay);

      if (debtAmount > 0 && customerId == 'khach_le' && !isDraft) {
        setState(() => _isSaving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n?.walkInCustomerDebtNotAllowed ??
                  'Khách lẻ không được phép ghi nợ. Vui lòng chọn khách hàng hoặc thanh toán đủ.'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
        return;
      }

      final currentUser = ref.read(authProvider);
      final originalOrder = ref.read(editingOriginalOrderProvider);
      final originalOrderId = originalOrder?.id;

      // Tối ưu Firebase: Chỉ fetch đúng các sản phẩm liên quan có trong giỏ hàng
      final Map<String, Product> freshCartProducts = {};

      if (!isDraft) {
        final productRepo = ref.read(productRepositoryProvider);

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

        // 3) Kiểm tra tồn kho khả dụng thời điểm hiện tại (tính cả số lượng sẽ hoàn trả nếu đang sửa đơn)
        for (final item in cart.values) {
          final currentProduct =
              freshCartProducts[item.product.id] ?? item.product;

          final availableStock = ComboHelper.getAvailableStock(
            product: currentProduct,
            branchId: selectedBranch,
            allProducts: relatedProducts,
          );

          final int restoredQty =
              originalOrder != null && !originalOrder.isCancelled
                  ? originalOrder.items
                      .where((i) => i.productId == item.product.id)
                      .fold(0, (sum, i) => sum + i.activeQuantity)
                  : 0;

          final effectiveAvailableStock = availableStock + restoredQty;

          if (effectiveAvailableStock <= 0) {
            setState(() => _isSaving = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '${currentProduct.name} - ${l10n?.outOfStockMsg ?? 'Đã hết hàng'}'),
                  backgroundColor: AppColors.danger,
                ),
              );
            }
            return;
          }

          if (item.quantity > effectiveAvailableStock) {
            setState(() => _isSaving = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '${currentProduct.name} - ${l10n?.posNotEnoughStockDetails(effectiveAvailableStock, item.quantity) ?? 'Không đủ hàng (Tồn: $effectiveAvailableStock, Cần: ${item.quantity})'}'),
                  backgroundColor: AppColors.danger,
                ),
              );
            }
            return;
          }
        }
      }

      final grossTotal =
          totalAmount > 0 ? totalAmount : (netPay + discountAmount);
      final String? orderNote = _noteController.text.trim().isNotEmpty
          ? _noteController.text.trim()
          : null;

      final String? resolvedCustomerPhone;
      if (_selectedCustomer?.phone != null &&
          _selectedCustomer!.phone.trim().isNotEmpty) {
        resolvedCustomerPhone = _selectedCustomer!.phone.trim();
      } else if (_selectedCustomer == null ||
          _selectedCustomer!.id == originalOrder?.customerId) {
        resolvedCustomerPhone = originalOrder?.customerPhone;
      } else {
        resolvedCustomerPhone = null;
      }

      // Tạo đối tượng hoá đơn/đơn hàng
      final order = Order(
        id: id,
        customerId: customerId,
        customerName: _selectedCustomer?.name,
        customerPhone: resolvedCustomerPhone,
        createdAt: now,
        items: orderItems,
        total: grossTotal,
        discount: discountAmount,
        status: isDraft ? 'draft' : 'completed',
        amountPaid: paidAmount,
        debtAmount: debtAmount,
        paymentMethod: _paymentMethod,
        createdBy: currentUser?.username,
        createdByName: currentUser?.name,
        storeId: selectedBranch,
        cashAmount: finalCashAmount,
        transferAmount: finalTransferAmount,
        note: orderNote,
      );

      // 1) Lưu đơn hàng mới (nếu lưu lỗi, đơn cũ vẫn an toàn không bị hủy)
      await ref.read(orderRepositoryProvider).create(order);

      // 2) Nếu đang sửa hóa đơn cũ, thực hiện hủy đơn cũ để hoàn kho và công nợ cũ trước khi trừ kho & ghi nợ đơn mới
      if (originalOrder != null && !originalOrder.isCancelled) {
        try {
          final cancelUseCase = ref.read(cancelInvoiceUseCaseProvider);
          await cancelUseCase.execute(
            order: originalOrder,
            cancelReason: 'Đã sửa thành $id',
            currentUser: currentUser ??
                UserAccount(
                  username: 'system',
                  displayName: 'Hệ thống',
                  role: 'admin',
                  storeId: selectedBranch,
                ),
            storeId: originalOrder.storeId ?? selectedBranch,
            isReplacement: true,
          );
        } catch (cancelErr) {
          debugPrint('Warning: Could not cancel replaced order: $cancelErr');
        }
        ref.read(editingOriginalOrderProvider.notifier).state = null;
      }

      // 3) Trigger notification for Order Created or Order Versioned Update
      if (!isDraft) {
        try {
          final dispatcher = ref.read(notificationDispatcherProvider);
          final effectiveStoreId =
              (order.storeId != null && order.storeId!.isNotEmpty)
                  ? order.storeId!
                  : (selectedBranch.isNotEmpty ? selectedBranch : 'store_001');

          if (originalOrderId != null && originalOrderId.isNotEmpty) {
            await dispatcher.notifyOrderUpdated(
              storeId: effectiveStoreId,
              order: order,
              originalOrderId: originalOrderId,
              user: currentUser,
            );
          } else {
            await dispatcher.notifyOrderCreated(
              storeId: effectiveStoreId,
              order: order,
              user: currentUser,
            );
          }
        } catch (notifErr) {
          debugPrint(
              'Warning: Could not dispatch order notification: $notifErr');
        }
      }

      // 4) Cập nhật lịch sử mua hàng & công nợ cho Customer (nếu không phải Khách lẻ & không phải đơn nháp)
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
            totalSales: currentTotalSales + grossTotal,
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

            // Gửi thông báo công nợ phát sinh cho Admin/Owner
            try {
              final effectiveDebtStoreId =
                  selectedBranch.isNotEmpty ? selectedBranch : 'store_001';
              await ref
                  .read(notificationDispatcherProvider)
                  .notifyCustomerDebtAdded(
                    storeId: effectiveDebtStoreId,
                    customerId: customerId,
                    customerName: customer.name,
                    debtAmount: debtAmount,
                    orderId: id,
                    user: currentUser,
                  );
            } catch (debtNotifErr) {
              debugPrint(
                  'Warning: Could not dispatch debt notification: $debtNotifErr');
            }
          }
        }
      }

      // Nếu KHÔNG phải đơn nháp (Đơn chính thức) -> Trừ tồn kho và ghi nhận Xuất kho
      if (!isDraft) {
        final productRepo = ref.read(productRepositoryProvider);
        final inventoryRepo = ref.read(inventoryRepositoryProvider);

        for (final item in cart.values) {
          if (item.product.isCombo && item.product.comboComponents.isNotEmpty) {
            // Trừ kho từng linh kiện thành phần của Combo
            for (final comp in item.product.comboComponents) {
              final childProduct =
                  await productRepo.fetchById(comp.productId) ??
                      freshCartProducts[comp.productId];
              if (childProduct != null) {
                final childBranchStocks =
                    Map<String, int>.from(childProduct.branchStocks);
                String childKey = selectedBranch;
                if (!childBranchStocks.containsKey(selectedBranch)) {
                  if (selectedBranch == 'store_001' &&
                      childBranchStocks.containsKey('branch_1')) {
                    childKey = 'branch_1';
                  } else if (selectedBranch == 'store_002' &&
                      childBranchStocks.containsKey('branch_2')) {
                    childKey = 'branch_2';
                  } else if (selectedBranch == 'branch_1' &&
                      childBranchStocks.containsKey('store_001')) {
                    childKey = 'store_001';
                  } else if (selectedBranch == 'branch_2' &&
                      childBranchStocks.containsKey('store_002')) {
                    childKey = 'store_002';
                  }
                }
                if (!childBranchStocks.containsKey(childKey)) {
                  for (final k in childBranchStocks.keys) {
                    if (StoreResolverHelper.normalizeStoreId(k) ==
                        StoreResolverHelper.normalizeStoreId(selectedBranch)) {
                      childKey = k;
                      break;
                    }
                  }
                }
                final currentChildStock = childBranchStocks[childKey] ?? 0;
                final qtyToDeduct = item.quantity * comp.quantity;
                childBranchStocks[childKey] =
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
                  storeId: selectedBranch,
                ));
              }
            }
          } else {
            // Trừ stock sản phẩm đơn lẻ thông thường
            final freshProduct = await productRepo.fetchById(item.product.id) ??
                freshCartProducts[item.product.id] ??
                item.product;
            final branchStocks =
                Map<String, int>.from(freshProduct.branchStocks);
            String targetKey = selectedBranch;
            if (!branchStocks.containsKey(selectedBranch)) {
              if (selectedBranch == 'store_001' &&
                  branchStocks.containsKey('branch_1')) {
                targetKey = 'branch_1';
              } else if (selectedBranch == 'store_002' &&
                  branchStocks.containsKey('branch_2')) {
                targetKey = 'branch_2';
              } else if (selectedBranch == 'branch_1' &&
                  branchStocks.containsKey('store_001')) {
                targetKey = 'store_001';
              } else if (selectedBranch == 'branch_2' &&
                  branchStocks.containsKey('store_002')) {
                targetKey = 'store_002';
              }
            }
            if (!branchStocks.containsKey(targetKey)) {
              for (final k in branchStocks.keys) {
                if (StoreResolverHelper.normalizeStoreId(k) ==
                    StoreResolverHelper.normalizeStoreId(selectedBranch)) {
                  targetKey = k;
                  break;
                }
              }
            }
            final currentStock = branchStocks[targetKey] ?? 0;
            branchStocks[targetKey] =
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
              storeId: selectedBranch,
            ));
          }
        }
      }

      // Không invalidate các provider realtime (sản phẩm, đơn hàng, khách hàng):
      // listener RTDB đã tự nhận thay đổi vừa ghi; invalidate sẽ huỷ listener và
      // tải lại TOÀN BỘ danh mục sản phẩm + khách hàng sau mỗi đơn bán.

      // Reset activeOrderIdProvider unconditionally to prevent draft ID reuse in subsequent orders
      ref.read(activeOrderIdProvider.notifier).state = null;
      ref.read(editingOriginalOrderProvider.notifier).state = null;

      // Clear giỏ hàng Riverpod
      ref.read(cartProvider.notifier).clearCart();

      setState(() => _isSaving = false);

      if (!mounted) return;

      if (isDraft) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.draftSaved ?? 'Đã lưu đơn tạm'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        final config = ref.read(storePaymentConfigProvider);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => AlertDialog(
            scrollable: true,
            title: Row(
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n?.posPaymentSuccessDialogTitle ??
                        'Thanh toán thành công',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Text(
              l10n?.posPaymentSuccessDialogMsg(id) ??
                  'Đơn hàng $id đã được tạo thành công.\nBạn có muốn in hóa đơn ngay bây giờ không?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: Text(l10n?.posBackToHome ?? 'Về màn hình chính'),
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
                label: Text(l10n?.posPrintInvoice ?? 'In Hóa Đơn'),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
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
