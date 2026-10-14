import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/inventories/stock_transfer_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/store_resolver_helper.dart';
import '../../../domain/entities/stock_transfer.dart';
import '../../common/widgets/product_image_thumbnail.dart';

final NumberFormat _money = NumberFormat('#,###', 'vi_VN');
final DateFormat _dateTime = DateFormat('dd/MM/yyyy HH:mm');

String formatTransferMoney(num v) => _money.format(v);
String formatTransferDateTime(DateTime d) => _dateTime.format(d);

String transferStatusLabel(StockTransferStatus s) {
  switch (s) {
    case StockTransferStatus.draft:
      return 'Phiếu tạm';
    case StockTransferStatus.inTransit:
      return 'Đang chuyển';
    case StockTransferStatus.received:
      return 'Đã nhận';
    case StockTransferStatus.cancelled:
      return 'Đã hủy';
  }
}

class StockTransferStatusBadge extends StatelessWidget {
  const StockTransferStatusBadge(this.status, {super.key});

  final StockTransferStatus status;

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    switch (status) {
      case StockTransferStatus.received:
        fg = AppColors.success;
        bg = AppColors.successLight;
        break;
      case StockTransferStatus.inTransit:
        fg = AppColors.info;
        bg = AppColors.infoLight;
        break;
      case StockTransferStatus.cancelled:
        fg = AppColors.danger;
        bg = AppColors.dangerLight;
        break;
      case StockTransferStatus.draft:
        fg = AppColors.grey600;
        bg = AppColors.grey100;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        transferStatusLabel(status),
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

/// Khối "Từ chi nhánh → Đến chi nhánh" (có thời gian/người nếu có).
class StockTransferRoute extends StatelessWidget {
  const StockTransferRoute({
    super.key,
    required this.sourceName,
    required this.targetName,
    this.sourceSubtitle,
    this.targetSubtitle,
  });

  final String sourceName;
  final String targetName;
  final String? sourceSubtitle;
  final String? targetSubtitle;

  Widget _row(IconData icon, Color color, String name, String? sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
              if (sub != null && sub.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sub,
                      style: const TextStyle(
                          color: AppColors.grey600, fontSize: 13)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row(Icons.circle_outlined, AppColors.danger, sourceName,
            sourceSubtitle),
        Padding(
          padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(width: 2, height: 16, color: AppColors.grey300),
          ),
        ),
        _row(Icons.location_on, AppColors.success, targetName, targetSubtitle),
      ],
    );
  }
}

/// Bộ chọn số lượng: − [n] +
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.max,
    this.min = 0,
  });

  final int value;
  final int min;
  final int? max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final canDec = value > min;
    final canInc = max == null || value < max!;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.grey300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove, size: 18),
            onPressed: canDec ? () => onChanged(value - 1) : null,
          ),
          InkWell(
            onTap: () async {
              final v = await _askQuantity(context, value, max);
              if (v != null) onChanged(v.clamp(min, max ?? 1 << 30));
            },
            child: SizedBox(
              width: 44,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 18),
            onPressed: canInc ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }

  static Future<int?> _askQuantity(
      BuildContext context, int current, int? max) {
    // The controller lives in the dialog's own State so it is disposed only
    // after the route (and its exit animation) is gone.
    return showDialog<int>(
      context: context,
      builder: (ctx) => _QuantityDialog(current: current, max: max),
    );
  }
}

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.current, required this.max});

  final int current;
  final int? max;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.current}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Nhập số lượng'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
            helperText: widget.max != null ? 'Tối đa ${widget.max}' : null),
        onSubmitted: (v) => Navigator.pop(context, int.tryParse(v)),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(_controller.text.trim())),
            child: const Text('Xong')),
      ],
    );
  }
}

/// Giới hạn bề rộng nội dung trên màn hình lớn (tablet/web) và canh giữa.
class TransferMaxWidth extends StatelessWidget {
  const TransferMaxWidth({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Ảnh mặt hàng trong phiếu chuyển: dùng ảnh lưu trong phiếu, nếu không có thì
/// tra theo productId; không có ảnh nào thì hiện khung placeholder.
class TransferItemThumb extends ConsumerWidget {
  const TransferItemThumb({
    super.key,
    required this.productId,
    required this.name,
    this.imageUrl,
    this.size = 48,
  });

  final String productId;
  final String name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final looked =
        ref.watch(transferProductImageMapProvider.select((m) => m[productId]));
    final url =
        (imageUrl != null && imageUrl!.trim().isNotEmpty) ? imageUrl : looked;
    if (url == null || url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.inventory_2_outlined,
            size: size * 0.5, color: AppColors.grey400),
      );
    }
    return ProductImageThumbnail(
      imageUrl: url,
      productName: name,
      size: size,
    );
  }
}

/// [storeId] có phải chi nhánh nhận của phiếu (tính cả alias store_001/branch_1).
bool transferIsTarget(String storeId, StockTransfer t) {
  final a = StoreResolverHelper.normalizeStoreId(storeId);
  final b = StoreResolverHelper.normalizeStoreId(t.targetStoreId);
  return storeId == t.targetStoreId || (a.isNotEmpty && a == b);
}
