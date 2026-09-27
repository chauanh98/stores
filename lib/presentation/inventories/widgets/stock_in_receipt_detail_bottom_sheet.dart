import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/supplier.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../application/inventories/stock_in_receipts_providers.dart';
import '../../../application/suppliers/suppliers_providers.dart';
import '../../common/widgets/product_image_thumbnail.dart';
import 'cancel_stock_in_receipt_dialog.dart';
import 'stock_in_receipt_card.dart';

/// Modal bottom sheet displaying complete details of a Stock-in Receipt (Phiếu nhập kho).
/// Follows KiotViet design standards with RBAC cost-price protection.
class StockInReceiptDetailBottomSheet extends ConsumerWidget {
  final StockInReceipt? receipt;
  final String? importCode;
  final InventoryTransaction? transaction;

  const StockInReceiptDetailBottomSheet({
    super.key,
    this.receipt,
    this.importCode,
    this.transaction,
  });

  /// Static helper to open the detail bottom sheet.
  static Future<void> show(
    BuildContext context, {
    StockInReceipt? receipt,
    String? importCode,
    InventoryTransaction? transaction,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StockInReceiptDetailBottomSheet(
        receipt: receipt,
        importCode: importCode,
        transaction: transaction,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canViewCostPrice = ref.watch(canViewCostPriceProvider);
    final user = ref.watch(authProvider);
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    // 1. Resolve receipt instance
    StockInReceipt? effectiveReceipt = receipt;
    if (effectiveReceipt == null &&
        (importCode != null || transaction?.importCode != null)) {
      final targetCode = importCode ?? transaction?.importCode;
      if (targetCode != null && targetCode.isNotEmpty) {
        try {
          effectiveReceipt = ref.watch(stockInReceiptByIdProvider(targetCode));
        } catch (_) {}
      }
    }

    // Fallback: If not found in loaded receipts, and transaction is present, synthesize receipt
    if (effectiveReceipt == null && transaction != null) {
      final synthesized =
          groupTransactionsToReceipts(transactions: [transaction!]);
      if (synthesized.isNotEmpty) {
        effectiveReceipt = synthesized.first;
      }
    }

    if (effectiveReceipt == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 48, color: AppColors.grey400),
            const SizedBox(height: 12),
            const Text(
              'Không tìm thấy thông tin phiếu nhập kho',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Mã phiếu: ${importCode ?? transaction?.importCode ?? '—'}',
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    }

    // Lookup supplier details if supplierId is present
    Supplier? matchedSupplier;
    if (effectiveReceipt.supplierId != null &&
        effectiveReceipt.supplierId!.isNotEmpty) {
      final suppliers = ref.watch(supplierListNotifierProvider).value ?? [];
      for (final s in suppliers) {
        if (s.id == effectiveReceipt.supplierId) {
          matchedSupplier = s;
          break;
        }
      }
    }

    final maxHeight = MediaQuery.of(context).size.height * 0.90;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // ── Top Bar: Drag Handle & Header ──
            Padding(
              padding:
                  const EdgeInsets.only(top: 8, left: 16, right: 8, bottom: 4),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.grey300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Chi tiết phiếu nhập kho',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 22),
                        color: AppColors.textSecondary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.dividerLight),

            // ── Scrollable Body ──
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // 1. General Info Card
                  _buildGeneralInfoCard(
                      effectiveReceipt, matchedSupplier, dateFormat),

                  const SizedBox(height: 16),

                  // 2. Items Breakdown Table/List
                  _buildItemsSection(
                      effectiveReceipt, canViewCostPrice, currencyFormat),

                  const SizedBox(height: 16),

                  // 3. Financial Summary Card
                  _buildFinancialSummaryCard(
                      effectiveReceipt, canViewCostPrice, currencyFormat),

                  const SizedBox(height: 16),

                  // 4. Note Card (if note exists)
                  if (effectiveReceipt.note.isNotEmpty) ...[
                    _buildNoteCard(effectiveReceipt.note),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),

            // ── Bottom Action Buttons ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.white,
                border: Border(top: BorderSide(color: AppColors.dividerLight)),
              ),
              child: Row(
                children: [
                  // Cancel receipt button for Admin/Supervisor on completed receipts
                  if (effectiveReceipt.isCompleted &&
                      (user?.isAdmin == true ||
                          user?.isSupervisor == true)) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('btn_cancel_receipt'),
                        icon: const Icon(Icons.cancel_outlined,
                            color: AppColors.danger, size: 18),
                        label: const Text(
                          'Hủy phiếu nhập',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppColors.danger, width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          final cancelled =
                              await CancelStockInReceiptDialog.show(
                            context,
                            receipt: effectiveReceipt!,
                            storeId: effectiveReceipt.storeId,
                          );
                          if (cancelled == true && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // Delete button for Admin on draft/cancelled receipts
                  if ((effectiveReceipt.isDraft ||
                          effectiveReceipt.isCancelled) &&
                      user?.isAdmin == true) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('btn_delete_receipt'),
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.danger, size: 18),
                        label: const Text(
                          'Xóa phiếu',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppColors.danger, width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Xác nhận xóa'),
                              content: Text(
                                effectiveReceipt!.isDraft
                                    ? 'Xóa phiếu tạm này?'
                                    : 'Xóa vĩnh viễn phiếu nhập này?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Hủy'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.danger),
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: const Text('Xóa',
                                      style: TextStyle(color: AppColors.white)),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true &&
                              context.mounted &&
                              effectiveReceipt != null) {
                            try {
                              final targetReceipt = effectiveReceipt;
                              final sId = targetReceipt.storeId ??
                                  ref.read(currentStoreIdProvider) ??
                                  'store_001';
                              await ref
                                  .read(deleteStockInReceiptUseCaseProvider)
                                  .execute(
                                    storeId: sId,
                                    receipt: targetReceipt,
                                  );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Đã xóa phiếu thành công')),
                              );
                              Navigator.of(context).pop();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Lỗi khi xóa: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // Close button
                  Expanded(
                    child: ElevatedButton(
                      key: const Key('btn_close_detail'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Đóng',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
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
  }

  // ── General Info Card ──
  Widget _buildGeneralInfoCard(
    StockInReceipt receipt,
    Supplier? supplier,
    DateFormat dateFormat,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Receipt Code + Status Badge + Branch Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.receipt_outlined,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        receipt.importCode.startsWith('#')
                            ? receipt.importCode
                            : '#${receipt.importCode}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              StockInReceiptStatusBadge(status: receipt.status),
              const SizedBox(width: 6),
              Flexible(
                child: StoreBadge(storeId: receipt.storeId),
              ),
            ],
          ),

          if (receipt.isCancelled) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.dividerLight),
            const SizedBox(height: 10),
            _buildInfoRow(
              icon: Icons.cancel_outlined,
              label: 'Lý do hủy:',
              value: receipt.cancelReason ?? 'Không có lý do',
              isBold: true,
            ),
            if (receipt.cancelledBy != null &&
                receipt.cancelledBy!.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildInfoRow(
                icon: Icons.person_off_outlined,
                label: 'Người hủy:',
                value: receipt.cancelledBy!,
              ),
            ],
            if (receipt.cancelledAt != null) ...[
              const SizedBox(height: 6),
              _buildInfoRow(
                icon: Icons.access_time,
                label: 'Thời gian hủy:',
                value: dateFormat.format(receipt.cancelledAt!),
              ),
            ],
          ],

          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.dividerLight),
          const SizedBox(height: 10),

          // Row 2: Date & Creator
          _buildInfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Ngày nhập:',
            value: dateFormat.format(receipt.date),
          ),
          const SizedBox(height: 6),
          _buildInfoRow(
            icon: Icons.person_outline,
            label: 'Người nhập:',
            value: receipt.createdByName ?? receipt.createdBy ?? '—',
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.dividerLight),
          const SizedBox(height: 10),

          // Row 3: Supplier Info
          _buildInfoRow(
            icon: Icons.storefront_outlined,
            label: 'Nhà cung cấp:',
            value: receipt.supplierName ?? supplier?.name ?? 'Nhà cung cấp lẻ',
            isBold: true,
          ),
          if (supplier?.phone != null && supplier!.phone.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildInfoRow(
              icon: Icons.phone_outlined,
              label: 'Số điện thoại:',
              value: supplier.phone,
            ),
          ],
          if (supplier?.code != null && supplier!.code.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildInfoRow(
              icon: Icons.tag_outlined,
              label: 'Mã NCC:',
              value: supplier.code,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isBold = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // ── Items Breakdown Section ──
  Widget _buildItemsSection(
    StockInReceipt receipt,
    bool canViewCostPrice,
    NumberFormat currencyFormat,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Danh sách sản phẩm (${receipt.itemCount})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Tổng ${receipt.totalQuantity} sp',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: receipt.items.length,
            separatorBuilder: (_, __) => const Divider(
                height: 1, indent: 64, color: AppColors.dividerLight),
            itemBuilder: (context, index) {
              final item = receipt.items[index];
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Product Thumbnail
                    ProductImageThumbnail(
                      imageUrl: item.imageUrl,
                      productName: item.productName,
                      size: 46,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 10),

                    // Product Details
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName ?? 'Sản phẩm ${item.productId}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (item.productCode != null &&
                                  item.productCode!.isNotEmpty) ...[
                                Flexible(
                                  child: Text(
                                    item.productCode!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text('•',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textSecondary)),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  'ĐVT: ${item.unit != null && item.unit!.isNotEmpty ? item.unit! : 'Cái'}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (canViewCostPrice) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Đơn giá: ${currencyFormat.format(item.importPrice)} đ',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Quantity and Total Price
                    Flexible(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'SL: ${item.quantity}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (canViewCostPrice)
                            Text(
                              '${currencyFormat.format(item.totalPrice)} đ',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          else
                            const Text(
                              '••••••',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                                letterSpacing: 2,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Financial Summary Card ──
  Widget _buildFinancialSummaryCard(
    StockInReceipt receipt,
    bool canViewCostPrice,
    NumberFormat currencyFormat,
  ) {
    final bool hasDebt =
        (receipt.debtAmount != null && receipt.debtAmount! > 0);
    final double debt = receipt.debtAmount ?? 0.0;
    final double paid = receipt.paidAmount ?? (receipt.totalAmount - debt);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tổng kết tài chính',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),

          // Total Amount
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tổng tiền hàng:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              if (canViewCostPrice)
                Flexible(
                  child: Text(
                    '${currencyFormat.format(receipt.totalAmount)} đ',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                )
              else
                const Text(
                  '••••••',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    letterSpacing: 2,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Paid Amount
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Đã thanh toán:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              if (canViewCostPrice)
                Flexible(
                  child: Text(
                    '${currencyFormat.format(paid)} đ',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                )
              else
                const Text(
                  '••••••',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    letterSpacing: 2,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Debt Amount
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Nợ NCC:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              if (hasDebt) ...[
                if (canViewCostPrice)
                  Flexible(
                    child: Text(
                      '${currencyFormat.format(debt)} đ',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.warning,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  )
                else
                  const Text(
                    'Ghi nợ NCC',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
              ] else ...[
                const Text(
                  '0 đ (Đã trả đủ)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.success,
                  ),
                ),
              ],
            ],
          ),

          if (!canViewCostPrice) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.grey200,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline,
                      size: 12, color: AppColors.textSecondary),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Giá trị tiền hàng được bảo mật cho tài khoản nhân viên',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
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

  // ── Note Card ──
  Widget _buildNoteCard(String note) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningSubtle, // Soft warm yellow
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warningBorder, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.edit_note_outlined,
              size: 18, color: AppColors.warningMedium),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ghi chú lô hàng:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.warningDeep,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.warningDeep),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
