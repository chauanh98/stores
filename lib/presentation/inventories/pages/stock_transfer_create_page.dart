import '../../common/widgets/capped_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/inventories/stock_transfer_providers.dart';
import '../../../application/inventories/usecases/stock_transfer_use_cases.dart';
import '../../../application/products/products_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/stock_transfer.dart';
import '../../common/widgets/product_image_thumbnail.dart';
import '../widgets/stock_transfer_widgets.dart';

/// Tạo / sửa phiếu chuyển kho nhiều mặt hàng (CN gửi).
class StockTransferCreatePage extends ConsumerStatefulWidget {
  const StockTransferCreatePage({super.key, this.product, this.draft});

  /// Sản phẩm thêm sẵn (mở từ chi tiết sản phẩm).
  final Product? product;

  /// Phiếu tạm đang sửa.
  final StockTransfer? draft;

  @override
  ConsumerState<StockTransferCreatePage> createState() =>
      _StockTransferCreatePageState();
}

class _Line {
  _Line(this.productId, this.name, this.code, this.imageUrl, this.stock,
      this.price, this.qty);
  final String productId;
  final String name;
  final String code;
  final String? imageUrl;
  final int stock;
  final double price;
  int qty;
}

class _StockTransferCreatePageState
    extends ConsumerState<StockTransferCreatePage> {
  final _noteController = TextEditingController();
  final List<_Line> _lines = [];
  String? _targetStoreId;
  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _addProduct(Product p, String sourceStoreId) {
    final idx = _lines.indexWhere((l) => l.productId == p.id);
    setState(() {
      if (idx >= 0) {
        if (_lines[idx].qty < _lines[idx].stock) _lines[idx].qty++;
      } else {
        _lines.add(_Line(
            p.id,
            p.name,
            p.code,
            transferSafeImageUrl(p.primaryImageUrl),
            p.stockInBranch(sourceStoreId),
            p.costPrice,
            1));
      }
    });
  }

  Future<void> _pickProduct(String sourceStoreId) async {
    final picked = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPicker(storeId: sourceStoreId),
    );
    if (picked != null) _addProduct(picked, sourceStoreId);
  }

  StockTransfer _buildTransfer(String sourceId, Map<String, String> stores) {
    final user = ref.read(authProvider);
    final d = widget.draft;
    return StockTransfer(
      id: d?.id ?? '',
      code: d?.code ?? '',
      status: StockTransferStatus.draft,
      sourceStoreId: sourceId,
      sourceStoreName: stores[sourceId] ?? 'Chi nhánh $sourceId',
      targetStoreId: _targetStoreId ?? '',
      targetStoreName: stores[_targetStoreId] ?? '',
      items: [
        for (final l in _lines)
          StockTransferItem(
            productId: l.productId,
            name: l.name,
            code: l.code,
            imageUrl: transferSafeImageUrl(l.imageUrl),
            unitPrice: l.price,
            quantity: l.qty,
          ),
      ],
      note: _noteController.text.trim(),
      createdAt: d?.createdAt ?? DateTime.now(),
      createdBy: user?.username,
      createdByName: user?.name,
    );
  }

  Future<void> _save(String sourceId, Map<String, String> stores,
      {required bool complete}) async {
    if (_lines.isEmpty) {
      _toast('Chưa có hàng trong phiếu');
      return;
    }
    if (complete && _targetStoreId == null) {
      _toast('Vui lòng chọn chi nhánh nhận');
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final transfer = _buildTransfer(sourceId, stores);
    final user = ref.read(authProvider);
    try {
      if (complete) {
        final created = await ref
            .read(createStockTransferUseCaseProvider)
            .execute(transfer, user: user);
        messenger.showSnackBar(
            SnackBar(content: Text('Đã tạo phiếu ${created.code}')));
      } else {
        await ref.read(saveStockTransferDraftUseCaseProvider).execute(transfer);
        messenger.showSnackBar(const SnackBar(content: Text('Đã lưu tạm')));
      }
      if (!mounted) return;
      navigator.pop();
    } on StockTransferException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final storesAsync = ref.watch(availableStoresProvider);
    final user = ref.watch(authProvider);
    final sourceId = ref.watch(currentStoreIdProvider);
    final showPrice = ref.watch(canViewTransferPriceProvider);
    final stores = storesAsync.valueOrNull ?? const <String, String>{};

    if (!_initialized) {
      _initialized = true;
      final d = widget.draft;
      if (d != null) {
        _targetStoreId = d.targetStoreId.isEmpty ? null : d.targetStoreId;
        _noteController.text = d.note;
        for (final i in d.items) {
          _lines.add(_Line(i.productId, i.name, i.code, i.imageUrl, 1 << 20,
              i.unitPrice, i.quantity));
        }
      } else if (widget.product != null) {
        final p = widget.product!;
        _lines.add(_Line(
            p.id,
            p.name,
            p.code,
            transferSafeImageUrl(p.primaryImageUrl),
            p.stockInBranch(sourceId),
            p.costPrice,
            1));
      }
    }

    final targets = stores.entries.where((e) => e.key != sourceId).toList();
    final sourceName = stores[sourceId] ?? 'Chi nhánh $sourceId';
    final totalQty = _lines.fold<int>(0, (s, l) => s + l.qty);
    final totalValue = _lines.fold<double>(0, (s, l) => s + l.qty * l.price);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Phiếu chuyển hàng mới'),
        backgroundColor: AppColors.white,
        elevation: 0.5,
      ),
      body: TransferMaxWidth(
          child: Column(
        children: [
          Expanded(
            // Toàn bộ phần đầu cuộn cùng danh sách: màn hình nhỏ / bàn phím mở
            // không bị tràn, danh sách dựng lười.
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: _lines.length + 3,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Container(
                    color: AppColors.white,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Row(children: [
                          const Icon(Icons.circle_outlined,
                              color: AppColors.danger, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  'Từ $sourceName${user?.canSwitchStore == true ? '' : ' (Cố định)'}')),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.location_on,
                              color: AppColors.success, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButton<String>(
                              value: targets.any((e) => e.key == _targetStoreId)
                                  ? _targetStoreId
                                  : null,
                              isExpanded: true,
                              underline: const SizedBox.shrink(),
                              hint: const Text('Đến chi nhánh'),
                              items: [
                                for (final e in targets)
                                  DropdownMenuItem(
                                      value: e.key, child: Text(e.value)),
                              ],
                              onChanged: (v) =>
                                  setState(() => _targetStoreId = v),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  );
                }
                if (i == 1) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: OutlinedButton.icon(
                      onPressed: () => _pickProduct(sourceId),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm hàng vào phiếu'),
                    ),
                  );
                }
                final idx = i - 2;
                if (idx < _lines.length) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: _lineTile(_lines[idx], showPrice),
                  );
                }
                if (_lines.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('Chưa có hàng trong phiếu',
                          style: TextStyle(color: AppColors.grey600)),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú chuyển',
                      border: OutlineInputBorder(),
                    ),
                  ),
                );
              },
            ),
          ),
          CappedScroll(child: Container(
            color: AppColors.white,
            padding: const EdgeInsets.all(12),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(
                            '${_lines.length} mặt hàng • Số lượng: $totalQty',
                            style: const TextStyle(color: AppColors.grey600))),
                    if (showPrice)
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(formatTransferMoney(totalValue),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => _save(sourceId, stores, complete: false),
                        child: const Text('Lưu tạm'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving
                            ? null
                            : () => _save(sourceId, stores, complete: true),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Hoàn thành'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          )),
        ],
      )),
    );
  }

  Widget _lineTile(_Line l, bool showPrice) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 2),
                child: TransferItemThumb(
                  productId: l.productId,
                  name: l.name,
                  imageUrl: l.imageUrl,
                  size: 52,
                ),
              ),
              Expanded(
                child: Text(l.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: () => setState(() => _lines.remove(l)),
              ),
            ]),
            Text(l.code, style: const TextStyle(color: AppColors.grey600)),
            Text(
                'Tồn: ${l.stock >= 1 << 20 ? '-' : l.stock}${showPrice ? ' • Giá: ${formatTransferMoney(l.price)}' : ''}',
                style: const TextStyle(color: AppColors.grey600)),
            const SizedBox(height: 8),
            Row(children: [
              QuantityStepper(
                value: l.qty,
                min: 1,
                max: l.stock >= 1 << 20 ? null : l.stock,
                onChanged: (v) => setState(() => l.qty = v),
              ),
              const Spacer(),
              if (showPrice)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(formatTransferMoney(l.qty * l.price),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker({required this.storeId});

  final String storeId;

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    // Theo dõi luồng sản phẩm ngay trong sheet: không bị rỗng khi danh sách
    // chưa tải xong lúc mở, và tự hủy listener khi đóng sheet.
    final productsAsync = ref.watch(productListProvider);
    final products = productsAsync.valueOrNull ?? const <Product>[];
    final q = _q.trim().toLowerCase();
    final list = products
        .where((p) {
          if (widget.storeId.isNotEmpty &&
              p.stockInBranch(widget.storeId) <= 0) {
            return false;
          }
          if (q.isEmpty) return true;
          return p.name.toLowerCase().contains(q) ||
              p.code.toLowerCase().contains(q) ||
              (p.barcode ?? '').toLowerCase().contains(q);
        })
        .take(100)
        .toList();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Tên, mã hàng, mã vạch...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: productsAsync.isLoading && products.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? const Center(child: Text('Không có hàng còn tồn'))
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final p = list[i];
                            return ListTile(
                              leading: ProductImageThumbnail(
                                imageUrl: p.primaryImageUrl,
                                productName: p.name,
                                size: 44,
                              ),
                              title: Text(p.name),
                              subtitle: Text(p.code),
                              trailing: Text(
                                  'Tồn: ${p.stockInBranch(widget.storeId)}'),
                              onTap: () => Navigator.pop(context, p),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
