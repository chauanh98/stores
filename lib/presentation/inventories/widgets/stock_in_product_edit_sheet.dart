import 'package:stores/core/theme/app_colors.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/inventories/stock_in_receipts_providers.dart';
import '../../../domain/entities/product.dart';
import '../../common/widgets/product_image_thumbnail.dart';
import 'accounting_numpad.dart';

/// Active target field being edited by the embedded [AccountingNumpad].
enum ActiveEditField {
  quantity,
  unitPrice,
  discount,
}

/// Modal bottom sheet (or dialog) for selecting and editing line item details
/// during Stock-in receipt creation. Matches KiotViet standard and video 00:15 - 00:33.
class StockInProductEditSheet extends ConsumerStatefulWidget {
  final Product product;
  final int? branchStock;
  final String? storeId;
  final double? preFilledPrice;
  final StockInReceiptItem? existingItem;
  final Function(int qty, double unitPrice, double discount, String note)?
      onDone;
  final ValueChanged<StockInReceiptItem>? onItemUpdated;

  const StockInProductEditSheet({
    super.key,
    required this.product,
    this.branchStock,
    this.storeId,
    this.preFilledPrice,
    this.existingItem,
    this.onDone,
    this.onItemUpdated,
  });

  /// Static helper to display the sheet as a modal bottom sheet.
  static Future<StockInReceiptItem?> show({
    required BuildContext context,
    required Product product,
    int? branchStock,
    String? storeId,
    double? preFilledPrice,
    StockInReceiptItem? existingItem,
    Function(int qty, double unitPrice, double discount, String note)? onDone,
    ValueChanged<StockInReceiptItem>? onItemUpdated,
  }) {
    return showModalBottomSheet<StockInReceiptItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
      builder: (ctx) => StockInProductEditSheet(
        product: product,
        branchStock: branchStock,
        storeId: storeId,
        preFilledPrice: preFilledPrice,
        existingItem: existingItem,
        onDone: onDone,
        onItemUpdated: onItemUpdated,
      ),
    );
  }

  @override
  ConsumerState<StockInProductEditSheet> createState() =>
      _StockInProductEditSheetState();
}

class _StockInProductEditSheetState
    extends ConsumerState<StockInProductEditSheet> {
  final NumberFormat _currencyFormat = NumberFormat('#,###', 'vi_VN');

  late int _quantity;
  late double _originalPrice;
  late double _discount;
  late TextEditingController _priceController;
  late TextEditingController _discountController;
  late TextEditingController _qtyController;
  late TextEditingController _noteController;

  ActiveEditField _activeField = ActiveEditField.unitPrice;
  bool _isPriceFresh = true;
  bool _isDiscountFresh = true;
  bool _isQtyFresh = true;
  bool _priceHasDecimal = false;
  bool _discountHasDecimal = false;

  @override
  void initState() {
    super.initState();
    _quantity = widget.existingItem?.quantity ?? 1;
    _discount = widget.existingItem?.discount ?? 0.0;

    final initialPrice = widget.preFilledPrice ??
        widget.existingItem?.originalPrice ??
        widget.existingItem?.unitPrice ??
        widget.product.costPrice;
    _originalPrice = initialPrice;

    _priceController =
        TextEditingController(text: _currencyFormat.format(_originalPrice));
    _discountController = TextEditingController(
      text: _discount > 0 ? _currencyFormat.format(_discount) : '0',
    );
    _qtyController = TextEditingController(text: '$_quantity');
    _noteController =
        TextEditingController(text: widget.existingItem?.note ?? '');

    // If preFilledPrice was not provided explicitly, query repository asynchronously
    if (widget.preFilledPrice == null && widget.existingItem == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadLatestPrice();
      });
    }
  }

  Future<void> _loadLatestPrice() async {
    try {
      final String effectiveStore =
          (widget.storeId != null && widget.storeId!.isNotEmpty)
              ? widget.storeId!
              : ref.read(currentStoreIdProvider);
      final repo = ref.read(stockInReceiptRepositoryProvider);
      final latest = await repo.getLatestImportPrice(
        storeId: effectiveStore,
        productId: widget.product.id,
      );
      if (!mounted) return;
      if (latest != null && latest > 0) {
        if (_isPriceFresh) {
          setState(() {
            _originalPrice = latest;
            _priceController.text = _currencyFormat.format(latest);
          });
        }
      }
    } catch (_) {
      // Graceful fallback to initial costPrice
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    _discountController.dispose();
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double get netUnitPrice =>
      (_originalPrice - _discount).clamp(0.0, double.infinity);
  double get lineTotal => netUnitPrice * _quantity;

  int _resolveBranchStock() {
    if (widget.branchStock != null) {
      return widget.branchStock!;
    }
    try {
      final String effectiveStore =
          (widget.storeId != null && widget.storeId!.isNotEmpty)
              ? widget.storeId!
              : ref.watch(currentStoreIdProvider);
      return widget.product.stockInBranch(effectiveStore);
    } catch (_) {
      return widget.product.stock;
    }
  }

  double _parseInputNumber(String val) {
    final trimmed = val.trim();
    if (trimmed.isEmpty) return 0.0;
    if ('.'.allMatches(trimmed).length > 1) {
      return double.tryParse(trimmed.replaceAll('.', '').replaceAll(',', '')) ??
          0.0;
    }
    if (RegExp(r'^\d{1,3}\.\d{3}$').hasMatch(trimmed)) {
      return double.tryParse(trimmed.replaceAll('.', '').replaceAll(',', '')) ??
          0.0;
    }
    return double.tryParse(trimmed.replaceAll(',', '')) ?? 0.0;
  }

  void _handleNumpadDigit(String digit) {
    setState(() {
      switch (_activeField) {
        case ActiveEditField.quantity:
          if (digit == '.') return; // Ignore decimals for integer quantity
          String current = _isQtyFresh ? '' : _qtyController.text;
          _isQtyFresh = false;
          String updated = current + digit;
          if (updated.startsWith('0') && updated.length > 1) {
            updated = updated.replaceFirst(RegExp(r'^0+'), '');
          }
          if (updated.isEmpty) updated = '1';
          _quantity = int.tryParse(updated) ?? 1;
          _qtyController.text = updated;
          break;

        case ActiveEditField.unitPrice:
          if (digit == '.') {
            if (_priceHasDecimal || _priceController.text.contains('.')) return;
            _priceHasDecimal = true;
            String current = _isPriceFresh
                ? '0'
                : _priceController.text.replaceAll('.', '').replaceAll(',', '');
            _isPriceFresh = false;
            String updated = '$current.';
            final parsed = double.tryParse(updated) ?? 0.0;
            _originalPrice = parsed;
            _priceController.text = updated;
            return;
          }
          if (_priceHasDecimal) {
            String current = _priceController.text;
            _isPriceFresh = false;
            String updated = current + digit;
            final parsed = double.tryParse(updated) ?? 0.0;
            _originalPrice = parsed;
            _priceController.text = updated;
          } else {
            String current = _isPriceFresh
                ? ''
                : _priceController.text.replaceAll('.', '').replaceAll(',', '');
            _isPriceFresh = false;
            String updated = current + digit;
            final parsed = double.tryParse(updated) ?? 0.0;
            _originalPrice = parsed;
            _priceController.text = _currencyFormat.format(_originalPrice);
          }
          break;

        case ActiveEditField.discount:
          if (digit == '.') {
            if (_discountHasDecimal || _discountController.text.contains('.'))
              return;
            _discountHasDecimal = true;
            String current = _isDiscountFresh
                ? '0'
                : _discountController.text
                    .replaceAll('.', '')
                    .replaceAll(',', '');
            _isDiscountFresh = false;
            String updated = '$current.';
            final parsed = double.tryParse(updated) ?? 0.0;
            _discount = parsed;
            _discountController.text = updated;
            return;
          }
          if (_discountHasDecimal) {
            String current = _discountController.text;
            _isDiscountFresh = false;
            String updated = current + digit;
            final parsed = double.tryParse(updated) ?? 0.0;
            _discount = parsed;
            _discountController.text = updated;
          } else {
            String current = _isDiscountFresh
                ? ''
                : _discountController.text
                    .replaceAll('.', '')
                    .replaceAll(',', '');
            _isDiscountFresh = false;
            String updated = current + digit;
            final parsed = double.tryParse(updated) ?? 0.0;
            _discount = parsed;
            _discountController.text = _currencyFormat.format(_discount);
          }
          break;
      }
    });
  }

  void _handleNumpadDelete() {
    setState(() {
      switch (_activeField) {
        case ActiveEditField.quantity:
          _isQtyFresh = false;
          String text = _qtyController.text;
          if (text.isNotEmpty) {
            text = text.substring(0, text.length - 1);
          }
          if (text.isEmpty) text = '0';
          _quantity = int.tryParse(text) ?? 1;
          _qtyController.text = text;
          break;

        case ActiveEditField.unitPrice:
          _isPriceFresh = false;
          if (_priceHasDecimal) {
            String text = _priceController.text;
            if (text.isNotEmpty) {
              text = text.substring(0, text.length - 1);
            }
            if (!text.contains('.')) {
              _priceHasDecimal = false;
            }
            final parsed = double.tryParse(text) ?? 0.0;
            _originalPrice = parsed;
            _priceController.text = text.isEmpty ? '0' : text;
          } else {
            String raw =
                _priceController.text.replaceAll('.', '').replaceAll(',', '');
            if (raw.isNotEmpty) {
              raw = raw.substring(0, raw.length - 1);
            }
            final parsed = double.tryParse(raw) ?? 0.0;
            _originalPrice = parsed;
            _priceController.text =
                parsed > 0 ? _currencyFormat.format(parsed) : '0';
          }
          break;

        case ActiveEditField.discount:
          _isDiscountFresh = false;
          if (_discountHasDecimal) {
            String text = _discountController.text;
            if (text.isNotEmpty) {
              text = text.substring(0, text.length - 1);
            }
            if (!text.contains('.')) {
              _discountHasDecimal = false;
            }
            final parsed = double.tryParse(text) ?? 0.0;
            _discount = parsed;
            _discountController.text = text.isEmpty ? '0' : text;
          } else {
            String raw = _discountController.text
                .replaceAll('.', '')
                .replaceAll(',', '');
            if (raw.isNotEmpty) {
              raw = raw.substring(0, raw.length - 1);
            }
            final parsed = double.tryParse(raw) ?? 0.0;
            _discount = parsed;
            _discountController.text =
                parsed > 0 ? _currencyFormat.format(parsed) : '0';
          }
          break;
      }
    });
  }

  void _handleNumpadClear() {
    setState(() {
      switch (_activeField) {
        case ActiveEditField.quantity:
          _isQtyFresh = true;
          _quantity = 1;
          _qtyController.text = '1';
          break;
        case ActiveEditField.unitPrice:
          _isPriceFresh = true;
          _priceHasDecimal = false;
          _originalPrice = 0.0;
          _priceController.text = '0';
          break;
        case ActiveEditField.discount:
          _isDiscountFresh = true;
          _discountHasDecimal = false;
          _discount = 0.0;
          _discountController.text = '0';
          break;
      }
    });
  }

  bool _isSubmitting = false;

  void _commitAndDone() {
    if (_isSubmitting) return;
    _isSubmitting = true;

    final effectiveQty = _quantity < 1 ? 1 : _quantity;
    final effectiveNetPrice =
        (_originalPrice - _discount).clamp(0.0, double.infinity);
    final effectiveDiscount = _discount.clamp(0.0, double.infinity);
    final note = _noteController.text.trim();

    final item = (widget.existingItem ??
            StockInReceiptItem(
              transactionId:
                  'TX_${DateTime.now().millisecondsSinceEpoch}_${widget.product.id}',
              productId: widget.product.id,
              quantity: effectiveQty,
              unitPrice: effectiveNetPrice,
              originalPrice: _originalPrice,
              discount: effectiveDiscount,
              note: note,
              productName: widget.product.name,
              productCode: widget.product.code,
              imageUrl:
                  widget.product.primaryImageUrl ?? widget.product.imageUrl,
              unit: widget.product.unit,
              barcode: widget.product.barcode,
            ))
        .copyWith(
      quantity: effectiveQty,
      unitPrice: effectiveNetPrice,
      originalPrice: _originalPrice,
      discount: effectiveDiscount,
      note: note,
    );

    widget.onDone
        ?.call(effectiveQty, effectiveNetPrice, effectiveDiscount, note);
    widget.onItemUpdated?.call(item);
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    final branchStock = _resolveBranchStock();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      key: const Key('product_edit_sheet'),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(
        bottom: bottomInset + 12,
        top: 12,
        left: 16,
        right: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header: Back Chevron (< SKU) and Stock Badge ("Tồn: X")
            Row(
              children: [
                IconButton(
                  key: const Key('btn_sheet_back'),
                  icon: const Icon(Icons.arrow_back_ios,
                      size: 18, color: AppColors.textTitle),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    '< ${widget.product.code}',
                    key: const Key('sheet_header_sku'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textTitle),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.infoSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.infoBorder),
                  ),
                  child: Text(
                    'Tồn: $branchStock',
                    key: const Key('sheet_stock_badge'),
                    style: const TextStyle(
                      color: AppColors.primaryAction,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 2. Product Information (Thumbnail + Name)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ProductImageThumbnail(
                  imageUrl:
                      widget.product.primaryImageUrl ?? widget.product.imageUrl,
                  productName: widget.product.name,
                  categoryName: widget.product.category,
                  size: 44,
                  borderRadius: 8,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.textHeadline),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (widget.product.unit != null &&
                              widget.product.unit!.isNotEmpty) ...[
                            Text(
                              'ĐVT: ${widget.product.unit}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.grey600),
                            ),
                            const SizedBox(width: 8),
                            const Text('•',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.grey400)),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              'Vốn hiện tại: ${_currencyFormat.format(widget.product.costPrice)} đ',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 3. Stepper for Quantity
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _activeField == ActiveEditField.quantity
                    ? AppColors.successSubtle
                    : AppColors.grey50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _activeField == ActiveEditField.quantity
                      ? AppColors.successMedium
                      : AppColors.grey200,
                  width: _activeField == ActiveEditField.quantity ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: InkWell(
                      onTap: () => setState(() {
                        _activeField = ActiveEditField.quantity;
                        _isQtyFresh = true;
                      }),
                      child: const Text(
                        'Số lượng nhập',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.textBodyDark),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        key: const Key('sheet_stepper_dec'),
                        icon: const Icon(Icons.remove_circle_outline,
                            color: AppColors.primaryAction, size: 24),
                        onPressed: _quantity > 1
                            ? () {
                                if (_quantity <= 1) return;
                                setState(() {
                                  final newQty = math.max(1, _quantity - 1);
                                  _quantity = newQty;
                                  _qtyController.text = '$_quantity';
                                  _isQtyFresh = false;
                                });
                              }
                            : null,
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _activeField = ActiveEditField.quantity;
                          _isQtyFresh = true;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: Text(
                            '$_quantity',
                            key: const Key('sheet_qty_text'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: AppColors.textHeadline),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('sheet_stepper_inc'),
                        icon: const Icon(Icons.add_circle_outline,
                            color: AppColors.primaryAction, size: 24),
                        onPressed: () {
                          setState(() {
                            _quantity++;
                            _qtyController.text = '$_quantity';
                            _isQtyFresh = false;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 4. Unit Price & Discount Inputs
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Đơn giá nhập',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        key: const Key('sheet_input_price'),
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        onTap: () => setState(() {
                          _activeField = ActiveEditField.unitPrice;
                          _isPriceFresh = true;
                          _priceHasDecimal = false;
                        }),
                        onChanged: (val) {
                          final parsed = _parseInputNumber(val);
                          setState(() {
                            _originalPrice = parsed;
                            _isPriceFresh = false;
                            _priceHasDecimal = val.contains('.') &&
                                !RegExp(r'^\d{1,3}\.\d{3}$').hasMatch(val);
                          });
                        },
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: _activeField == ActiveEditField.unitPrice
                                  ? AppColors.primaryAction
                                  : AppColors.grey300,
                              width: _activeField == ActiveEditField.unitPrice
                                  ? 1.8
                                  : 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: AppColors.primaryAction, width: 2),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Giảm giá',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        key: const Key('sheet_input_discount'),
                        controller: _discountController,
                        keyboardType: TextInputType.number,
                        onTap: () => setState(() {
                          _activeField = ActiveEditField.discount;
                          _isDiscountFresh = true;
                          _discountHasDecimal = false;
                        }),
                        onChanged: (val) {
                          final parsed = _parseInputNumber(val);
                          setState(() {
                            _discount = parsed;
                            _isDiscountFresh = false;
                            _discountHasDecimal = val.contains('.') &&
                                !RegExp(r'^\d{1,3}\.\d{3}$').hasMatch(val);
                          });
                        },
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: _activeField == ActiveEditField.discount
                                  ? AppColors.primaryAction
                                  : AppColors.grey300,
                              width: _activeField == ActiveEditField.discount
                                  ? 1.8
                                  : 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: AppColors.primaryAction, width: 2),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 5. Live Calculated Displays: "Giá nhập" & "Thành tiền"
            InkWell(
              onTap: () => setState(() {
                _activeField = ActiveEditField.unitPrice;
                _isPriceFresh = true;
                _priceHasDecimal = false;
              }),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Giá nhập (Đơn giá - Giảm)',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_currencyFormat.format(netUnitPrice)} đ',
                            key: const Key('sheet_calculated_net_price'),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.textHeadline),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Thành tiền',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_currencyFormat.format(lineTotal)} đ',
                            key: const Key('sheet_calculated_total'),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.primaryAction),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // 6. Note Field
            TextFormField(
              key: const Key('sheet_input_note'),
              controller: _noteController,
              keyboardType: TextInputType.multiline,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Thêm ghi chú hàng hóa',
                labelStyle:
                    const TextStyle(fontSize: 13, color: AppColors.textMuted),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
            const SizedBox(height: 12),

            // 7. Full-width "Xong" Action Button
            ElevatedButton(
              key: const Key('btn_sheet_done'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAction,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: _commitAndDone,
              child: const Text(
                'Xong',
                style: TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
            const SizedBox(height: 10),

            // 8. Embedded 4-Column Accounting Numpad
            AccountingNumpad(
              onDigit: _handleNumpadDigit,
              onDelete: _handleNumpadDelete,
              onClear: _handleNumpadClear,
              onDone: _commitAndDone,
            ),
          ],
        ),
      ),
    );
  }
}
