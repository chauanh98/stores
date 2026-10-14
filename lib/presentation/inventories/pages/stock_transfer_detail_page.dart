import '../../common/widgets/capped_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/inventories/stock_transfer_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/store_resolver_helper.dart';
import '../../../domain/entities/stock_transfer.dart';
import '../widgets/stock_transfer_widgets.dart';
import 'stock_transfer_receive_page.dart';

/// Chi tiết phiếu chuyển kho. Mở từ danh sách hoặc từ thông báo.
class StockTransferDetailPage extends ConsumerWidget {
  const StockTransferDetailPage({super.key, required this.transferId});

  final String transferId;

  bool _isTarget(String currentStoreId, StockTransfer t) {
    final a = StoreResolverHelper.normalizeStoreId(currentStoreId);
    final b = StoreResolverHelper.normalizeStoreId(t.targetStoreId);
    return currentStoreId == t.targetStoreId || (a.isNotEmpty && a == b);
  }

  bool _isSource(String currentStoreId, StockTransfer t) {
    final a = StoreResolverHelper.normalizeStoreId(currentStoreId);
    final b = StoreResolverHelper.normalizeStoreId(t.sourceStoreId);
    return currentStoreId == t.sourceStoreId || (a.isNotEmpty && a == b);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(stockTransferByIdProvider(transferId));
    final canViewPrice = ref.watch(canViewTransferPriceProvider);
    final currentStoreId = ref.watch(currentStoreIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Chi tiết phiếu chuyển'),
        backgroundColor: AppColors.white,
        elevation: 0.5,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (t) {
          if (t == null) {
            return const Center(child: Text('Không tìm thấy phiếu chuyển'));
          }
          final showReceived = t.isReceived;
          final canSwitch = ref.watch(authProvider)?.canSwitchStore ?? false;
          final canReceive =
              t.isInTransit && (_isTarget(currentStoreId, t) || canSwitch);
          final canCancel =
              t.isInTransit && (_isSource(currentStoreId, t) || canSwitch);
          return Column(
            children: [
              Expanded(
                child: TransferMaxWidth(
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _card(Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.start,
                              runSpacing: 8,
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.sizeOf(context).width *
                                              0.6),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(t.code,
                                                style: const TextStyle(
                                                    fontSize: 22,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ),
                                        IconButton(
                                          icon:
                                              const Icon(Icons.copy, size: 18),
                                          onPressed: () => Clipboard.setData(
                                              ClipboardData(text: t.code)),
                                        ),
                                      ]),
                                      Text(formatTransferDateTime(t.createdAt),
                                          style: const TextStyle(
                                              color: AppColors.grey600)),
                                    ],
                                  ),
                                ),
                                StockTransferStatusBadge(t.status),
                              ],
                            )),
                            _card(StockTransferRoute(
                              sourceName: t.sourceStoreName,
                              targetName: t.targetStoreName,
                              sourceSubtitle:
                                  '${formatTransferDateTime(t.createdAt)} · ${t.createdByName ?? t.createdBy ?? ''}',
                              targetSubtitle: t.receivedAt == null
                                  ? null
                                  : '${formatTransferDateTime(t.receivedAt!)} · ${t.receivedByName ?? t.receivedBy ?? ''}',
                            )),
                          ]),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        sliver: SliverToBoxAdapter(
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                            decoration: const BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(14)),
                            ),
                            child: Column(children: [
                              _headerRow(context, showReceived),
                              const Divider(),
                            ]),
                          ),
                        ),
                      ),
                      // Danh sách mặt hàng dựng lười: phiếu nhiều dòng vẫn mượt.
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        sliver: SliverList.builder(
                          itemCount: t.items.length,
                          itemBuilder: (_, i) => Container(
                            color: AppColors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: _itemRow(context, t.items[i], showReceived,
                                canViewPrice),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        sliver: SliverToBoxAdapter(
                          child: Container(
                            height: 14,
                            decoration: const BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.vertical(
                                  bottom: Radius.circular(14)),
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _card(Column(
                              children: [
                                _totalRow(
                                    canViewPrice
                                        ? 'Tổng giá trị chuyển'
                                        : 'Tổng số lượng chuyển',
                                    t.totalValue,
                                    '${t.itemCount} mặt hàng • Số lượng: ${t.totalQuantity}',
                                    canViewPrice),
                                if (showReceived) ...[
                                  const Divider(),
                                  _totalRow(
                                      canViewPrice
                                          ? 'Tổng giá trị nhận'
                                          : 'Tổng số lượng nhận',
                                      t.totalReceivedValue,
                                      '${t.receivedItemCount} mặt hàng • Số lượng: ${t.totalReceivedQuantity}',
                                      canViewPrice),
                                ],
                              ],
                            )),
                            if (t.note.isNotEmpty)
                              _card(Text('Ghi chú: ${t.note}')),
                            if (t.receiveNote.isNotEmpty)
                              _card(Text('Ghi chú nhận: ${t.receiveNote}')),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (canReceive || canCancel)
                CappedScroll(child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        if (canCancel)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _cancel(context, ref, t),
                              child: const Text('Hủy phiếu'),
                            ),
                          ),
                        if (canCancel && canReceive) const SizedBox(width: 12),
                        if (canReceive)
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) =>
                                    StockTransferReceivePage(transferId: t.id),
                              )),
                              child: const Text('Nhận hàng'),
                            ),
                          ),
                      ],
                    ),
                  ),
                )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, StockTransfer t) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
 scrollable: true,
        title: const Text('Hủy phiếu chuyển?'),
        content: const Text('Hàng sẽ được hoàn lại kho chi nhánh gửi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Không')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hủy phiếu')),
        ],
      ),
    );
    // The page (and its `ref`) may be gone while the dialog was open.
    if (ok != true || !context.mounted) return;
    final useCase = ref.read(cancelStockTransferUseCaseProvider);
    try {
      await useCase.execute(t.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _card(Widget child) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      );

  /// Bề rộng cột số theo cỡ chữ hệ thống (tối đa 1.4x) để không tràn ngang.
  double _col(BuildContext context, double base) =>
      base * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);

  Widget _numCell(BuildContext context, double base, Widget child) => SizedBox(
        width: _col(context, base),
        child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: child),
      );

  Widget _headerRow(BuildContext context, bool showReceived) {
    const s = TextStyle(
        color: AppColors.grey600, fontWeight: FontWeight.w600, fontSize: 12);
    return Row(
      children: [
        const Expanded(child: Text('MẶT HÀNG', style: s)),
        _numCell(context, 72, const Text('SL CHUYỂN', style: s)),
        if (showReceived)
          _numCell(context, 64, const Text('SL NHẬN', style: s)),
      ],
    );
  }

  Widget _itemRow(BuildContext context, StockTransferItem i, bool showReceived,
      bool showPrice) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: TransferItemThumb(
              productId: i.productId,
              name: i.name,
              imageUrl: i.imageUrl,
              size: 44,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(i.code, style: const TextStyle(color: AppColors.grey600)),
                if (showPrice)
                  Text('Giá: ${formatTransferMoney(i.unitPrice)}',
                      style: const TextStyle(color: AppColors.grey600)),
              ],
            ),
          ),
          _numCell(context, 72, Text('${i.quantity}')),
          if (showReceived)
            _numCell(
              context,
              64,
              Text('${i.receivedQuantity}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: i.receivedQuantity < i.quantity
                          ? AppColors.danger
                          : null)),
            ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, String sub, bool showPrice) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              Text(sub, style: const TextStyle(color: AppColors.grey600)),
            ],
          ),
        ),
        if (showPrice) ...[
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(formatTransferMoney(value),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ],
    );
  }
}
