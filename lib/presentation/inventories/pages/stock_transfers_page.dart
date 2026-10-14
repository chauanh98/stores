import '../../common/widgets/capped_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/inventories/stock_transfer_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/stock_transfer.dart';
import '../widgets/stock_transfer_widgets.dart';
import 'stock_transfer_create_page.dart';
import 'stock_transfer_detail_page.dart';
import 'stock_transfer_receive_page.dart';

/// Danh sách phiếu chuyển kho (gửi + nhận) của chi nhánh đang chọn.
class StockTransfersPage extends ConsumerStatefulWidget {
  const StockTransfersPage({super.key});

  @override
  ConsumerState<StockTransfersPage> createState() => _StockTransfersPageState();
}

class _StockTransfersPageState extends ConsumerState<StockTransfersPage> {
  final _searchController = TextEditingController();
  StockTransferStatus? _status;
  bool _pendingOnly = false; // chỉ phiếu đang chờ chi nhánh này nhận
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StockTransfer> _filter(List<StockTransfer> all, String storeId) {
    final q = _query.trim().toLowerCase();
    final filtered = all.where((t) {
      if (_pendingOnly && !(t.isInTransit && transferIsTarget(storeId, t))) {
        return false;
      }
      if (_status != null && t.status != _status) return false;
      if (q.isEmpty) return true;
      return t.code.toLowerCase().contains(q) ||
          t.sourceStoreName.toLowerCase().contains(q) ||
          t.targetStoreName.toLowerCase().contains(q) ||
          t.items.any((i) =>
              i.name.toLowerCase().contains(q) ||
              i.code.toLowerCase().contains(q));
    }).toList();
    // Phiếu chờ nhận của chi nhánh này lên đầu (giữ nguyên thứ tự còn lại).
    if (!_pendingOnly && _status == null) {
      bool pending(StockTransfer t) =>
          t.isInTransit && transferIsTarget(storeId, t);
      return [
        ...filtered.where(pending),
        ...filtered.where((t) => !pending(t)),
      ];
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(stockTransfersProvider);
    final canViewPrice = ref.watch(canViewTransferPriceProvider);
    final storeId = ref.watch(currentStoreIdProvider);
    final fetchLimit = ref.watch(stockTransfersLimitProvider);
    final canSwitch = ref.watch(authProvider)?.canSwitchStore ?? false;
    final pendingCount = (async.valueOrNull ?? const <StockTransfer>[])
        .where((t) => t.isInTransit && transferIsTarget(storeId, t))
        .length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Chuyển hàng',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.white,
        elevation: 0.5,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StockTransferCreatePage())),
        child: const Icon(Icons.add),
      ),
      body: TransferMaxWidth(
          child: Column(
        children: [
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Mã phiếu, chi nhánh, sản phẩm...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip('Tất cả', null),
                      _pendingChip(pendingCount),
                      for (final s in StockTransferStatus.values)
                        _chip(transferStatusLabel(s), s),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Lỗi: $e')),
              data: (all) {
                final list = _filter(all, storeId);
                if (list.isEmpty) {
                  return const Center(
                      child: Text('Chưa có phiếu chuyển hàng',
                          style: TextStyle(color: AppColors.grey600)));
                }
                return Column(
                  children: [
                    CappedScroll(maxFraction: 0.3, child: _Summary(
                      count: list.length,
                      totalValue: list
                          .where((t) => !t.isCancelled && !t.isDraft)
                          .fold<double>(0, (a, t) => a + t.totalValue),
                      showPrice: canViewPrice,
                    )),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        // Có thể còn phiếu cũ hơn chưa tải (tiết kiệm băng thông).
                        itemCount:
                            list.length + (all.length >= fetchLimit ? 1 : 0),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          if (i >= list.length) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: TextButton(
                                key: const Key('transfer_load_more'),
                                onPressed: () => ref
                                    .read(stockTransfersLimitProvider.notifier)
                                    .state += 30,
                                child: const Text('Xem thêm phiếu cũ'),
                              ),
                            );
                          }
                          return _TransferCard(
                            transfer: list[i],
                            showPrice: canViewPrice,
                            canReceive: list[i].isInTransit &&
                                (canSwitch ||
                                    transferIsTarget(storeId, list[i])),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      )),
    );
  }

  Widget _chip(String label, StockTransferStatus? s) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: !_pendingOnly && _status == s,
        onSelected: (_) => setState(() {
          _status = s;
          _pendingOnly = false;
        }),
      ),
    );
  }

  Widget _pendingChip(int count) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: const Key('transfer_pending_chip'),
        label: Text('Chờ nhận $count'),
        selected: _pendingOnly,
        onSelected: (_) => setState(() {
          _pendingOnly = true;
          _status = null;
        }),
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.transfer,
    required this.showPrice,
    required this.canReceive,
  });

  final StockTransfer transfer;
  final bool showPrice;
  final bool canReceive;

  @override
  Widget build(BuildContext context) {
    final t = transfer;
    const sub = TextStyle(color: AppColors.grey600, fontSize: 13);
    final names = t.items.map((i) => '${i.name} x${i.quantity}').join(', ');
    return InkWell(
      onTap: () {
        if (t.isDraft) {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => StockTransferCreatePage(draft: t)));
        } else {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => StockTransferDetailPage(transferId: t.id)));
        }
      },
      child: Container(
        color: AppColors.white,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${t.itemCount} mặt hàng - Số lượng: ${t.totalQuantity}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                if (showPrice) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(formatTransferMoney(t.totalValue),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Từ ${t.sourceStoreName}',
                          style: const TextStyle(
                              color: AppColors.primary, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                          t.targetStoreName.isEmpty
                              ? 'Chưa chọn chi nhánh nhận'
                              : 'Đến ${t.targetStoreName}',
                          style: const TextStyle(
                              color: AppColors.primary, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Số lượng nhận hiển thị ngoài label phiếu (vd "4/4 sản phẩm").
                      if (!t.isDraft)
                        Text('${t.receivedSummary} sản phẩm',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sub),
                      const SizedBox(height: 4),
                      StockTransferStatusBadge(t.status),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${formatTransferDateTime(t.createdAt)} • ${t.code}',
                style: sub),
            if (t.items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    for (final i in t.items.take(4))
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: TransferItemThumb(
                          productId: i.productId,
                          name: i.name,
                          imageUrl: i.imageUrl,
                          size: 36,
                        ),
                      ),
                    if (t.items.length > 4)
                      Text('+${t.items.length - 4}', style: sub),
                  ],
                ),
              ),
            if (canReceive)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    key: Key('transfer_receive_${t.id}'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            StockTransferReceivePage(transferId: t.id),
                      ),
                    ),
                    child: const Text('Nhận hàng'),
                  ),
                ),
              ),
            if (names.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(names,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: sub),
              ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.count,
    required this.totalValue,
    required this.showPrice,
  });

  final int count;
  final double totalValue;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Text('$count phiếu',
                style: const TextStyle(color: AppColors.grey600)),
          ),
          if (showPrice)
            Flexible(
              child: Text(
                'Giá trị chuyển: ${formatTransferMoney(totalValue)}',
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
        ],
      ),
    );
  }
}
