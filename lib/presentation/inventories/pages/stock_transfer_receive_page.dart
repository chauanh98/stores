import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/inventories/stock_transfer_providers.dart';
import '../../../application/inventories/usecases/stock_transfer_use_cases.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/stock_transfer.dart';
import '../widgets/stock_transfer_widgets.dart';

enum _ReceiveFilter { all, notFull, full }

/// Chi nhánh nhận xác nhận số lượng thực nhận của từng mặt hàng.
class StockTransferReceivePage extends ConsumerStatefulWidget {
  const StockTransferReceivePage({super.key, required this.transferId});

  final String transferId;

  @override
  ConsumerState<StockTransferReceivePage> createState() =>
      _StockTransferReceivePageState();
}

class _StockTransferReceivePageState
    extends ConsumerState<StockTransferReceivePage> {
  final _noteController = TextEditingController();
  final Map<String, int> _received = {};
  _ReceiveFilter _filter = _ReceiveFilter.all;
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  int _qty(StockTransferItem i) => _received[i.productId] ?? 0;

  Future<void> _submit(StockTransfer t) async {
    final partial = t.items.any((i) => _qty(i) < i.quantity);
    if (partial) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
 scrollable: true,
          title: const Text('Nhận chưa đủ hàng'),
          content: const Text(
              'Một số mặt hàng nhận ít hơn số lượng chuyển. Xác nhận hoàn thành?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Kiểm tra lại')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Hoàn thành')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final useCase = ref.read(receiveStockTransferUseCaseProvider);
    final user = ref.read(authProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await useCase.execute(
        t.id,
        receivedByProduct: {for (final i in t.items) i.productId: _qty(i)},
        receiveNote: _noteController.text,
        user: user,
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
          const SnackBar(content: Text('Đã nhận hàng chuyển kho')));
    } on StockTransferException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(stockTransferByIdProvider(widget.transferId));
    final showPrice = ref.watch(canViewTransferPriceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(async.valueOrNull?.code ?? 'Nhận hàng'),
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
          final fullCount = t.items.where((i) => _qty(i) >= i.quantity).length;
          final notFullCount = t.items.length - fullCount;
          final allFull = fullCount == t.items.length;
          final visible = t.items.where((i) {
            final full = _qty(i) >= i.quantity;
            switch (_filter) {
              case _ReceiveFilter.all:
                return true;
              case _ReceiveFilter.notFull:
                return !full;
              case _ReceiveFilter.full:
                return full;
            }
          }).toList();

          return TransferMaxWidth(
            child: Column(
              children: [
                Expanded(
                  // Phần đầu cuộn cùng danh sách (màn nhỏ không tràn); danh sách
                  // dựng lười nên phiếu nhiều mặt hàng vẫn mượt.
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: visible.length + 3,
                    itemBuilder: (_, index) {
                      if (index == 0) {
                        return Container(
                          color: AppColors.white,
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StockTransferRoute(
                                sourceName: 'Từ ${t.sourceStoreName}',
                                targetName: 'Đến ${t.targetStoreName}',
                              ),
                              const SizedBox(height: 10),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(children: [
                                  _chip('Tất cả ${t.items.length}',
                                      _ReceiveFilter.all),
                                  _chip('Chưa nhận đủ $notFullCount',
                                      _ReceiveFilter.notFull),
                                  _chip('Đã nhận đủ $fullCount',
                                      _ReceiveFilter.full),
                                ]),
                              ),
                            ],
                          ),
                        );
                      }
                      if (index == 1) {
                        return Container(
                          color: AppColors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('${t.items.length} MẶT HÀNG',
                                  style: const TextStyle(
                                      color: AppColors.grey600,
                                      fontWeight: FontWeight.w600)),
                              TextButton(
                                onPressed: () => setState(() {
                                  for (final i in t.items) {
                                    _received[i.productId] =
                                        allFull ? 0 : i.quantity;
                                  }
                                }),
                                child: Text(
                                    allFull ? 'Bỏ nhận tất cả' : 'Nhận tất cả'),
                              ),
                            ],
                          ),
                        );
                      }
                      final idx = index - 2;
                      if (idx < visible.length) {
                        return _itemTile(visible[idx], showPrice);
                      }
                      return Padding(
                        padding: const EdgeInsets.all(14),
                        child: TextField(
                          controller: _noteController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Ghi chú nhận',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : () => _submit(t),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Hoàn thành'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String label, _ReceiveFilter f) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == f,
          onSelected: (_) => setState(() => _filter = f),
        ),
      );

  Widget _itemTile(StockTransferItem i, bool showPrice) {
    final q = _qty(i);
    final full = q >= i.quantity;
    return Container(
      color: AppColors.white,
      margin: const EdgeInsets.only(top: 1),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TransferItemThumb(
                  productId: i.productId,
                  name: i.name,
                  imageUrl: i.imageUrl,
                  size: 56,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(i.code,
                        style: const TextStyle(color: AppColors.grey600)),
                    if (showPrice)
                      Text('Giá: ${formatTransferMoney(i.unitPrice)}',
                          style: const TextStyle(color: AppColors.grey600)),
                    const SizedBox(height: 4),
                    Text('SL Chuyển: ${i.quantity}',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              QuantityStepper(
                value: q,
                max: i.quantity,
                onChanged: (v) => setState(() => _received[i.productId] = v),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(
                    () => _received[i.productId] = full ? 0 : i.quantity),
                icon: Icon(
                    full ? Icons.check_circle : Icons.check_circle_outline,
                    size: 18),
                label: const Text('Nhận đủ'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
