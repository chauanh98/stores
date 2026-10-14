import 'package:firebase_database/firebase_database.dart';

import '../../../core/utils/store_resolver_helper.dart';
import '../../../data/models/product_model.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/stock_transfer.dart';
import '../../../domain/entities/user_account.dart';
import '../../../domain/repositories/stock_transfer_repository.dart';
import '../../notifications/notification_dispatcher.dart';

class StockTransferException implements Exception {
  StockTransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cập nhật tồn của [storeId] trong map branchStocks dùng chung giữa 2 chi
/// nhánh (đồng bộ các khoá alias store_001/branch_1, store_002/branch_2).
Map<String, int> applyStoreStock(
  Map<String, int> stocks,
  String storeId,
  int value,
) {
  final out = Map<String, int>.from(stocks);
  final v = value < 0 ? 0 : value;
  out[storeId] = v;
  final norm = StoreResolverHelper.normalizeStoreId(storeId);
  if (norm.isNotEmpty) out[norm] = v;
  if (norm == 'store_001' || storeId == 'store_001') {
    out['store_001'] = v;
    out['branch_1'] = v;
  }
  if (norm == 'store_002' || storeId == 'store_002') {
    out['store_002'] = v;
    out['branch_2'] = v;
  }
  return out;
}

/// Logic chung của các use case chuyển kho (đọc tồn mới nhất từ RTDB).
abstract class _TransferBase {
  _TransferBase(this._db, this._repo, this._dispatcher);

  final FirebaseDatabase _db;
  final StockTransferRepository _repo;
  final NotificationDispatcher? _dispatcher;

  /// Số mặt hàng xử lý song song mỗi lượt (giới hạn để không mở quá nhiều
  /// truy vấn cùng lúc).
  static const int _chunk = 20;

  Future<dynamic> _child(String storeId, String productId, String child) async {
    final snap =
        await _db.ref('stores/$storeId/products/$productId/$child').get();
    return snap.exists ? snap.value : null;
  }

  /// Đọc TỐI THIỂU: chỉ `branchStocks` (+ `costPrice` khi [needCost]); các
  /// trường cũ (`stocks`, `stock`, `price`, `name`) chỉ đọc khi thiếu để giữ
  /// nguyên ngữ nghĩa. Tuyệt đối không tải cả bản ghi (có thể chứa ảnh Base64).
  /// Mã chi nhánh chuẩn (store_001/store_002/...): phiếu, chỉ mục chờ nhận và
  /// đường dẫn sản phẩm luôn dùng mã chuẩn, không dùng alias branch_1/branch_2.
  static String canon(String id) {
    final n = StoreResolverHelper.normalizeStoreId(id);
    return n.isNotEmpty ? n : id.trim();
  }

  Future<Product?> _readProduct(String storeId, String productId,
      {bool needCost = true}) async {
    final first = await Future.wait<dynamic>([
      _child(storeId, productId, 'branchStocks'),
      if (needCost) _child(storeId, productId, 'costPrice'),
    ]);
    final bs = first[0];
    final cost = needCost ? first[1] : null;
    final map = <String, dynamic>{'id': productId, 'name': '', 'price': 0};
    var exists = bs != null || cost != null;
    if (bs != null) {
      map['branchStocks'] = bs;
    } else {
      final legacy = await Future.wait<dynamic>([
        _child(storeId, productId, 'stocks'),
        _child(storeId, productId, 'stock'),
      ]);
      if (legacy[0] != null) map['stocks'] = legacy[0];
      if (legacy[1] != null) map['stock'] = legacy[1];
      exists = exists || legacy[0] != null || legacy[1] != null;
    }
    if (cost != null) map['costPrice'] = cost;
    if (needCost && cost == null) {
      final price = await _child(storeId, productId, 'price');
      if (price != null) {
        map['price'] = price;
        exists = true;
      }
    }
    if (!exists && await _child(storeId, productId, 'name') == null) {
      return null;
    }
    return ProductModel.fromMap(map, storeId).toEntity();
  }

  /// Đọc đầy đủ bản ghi sản phẩm (chỉ khi cần tạo mới sản phẩm ở CN nhận).
  Future<Product?> _readFullProduct(String storeId, String productId) async {
    final snap = await _db.ref('stores/$storeId/products/$productId').get();
    if (!snap.exists || snap.value is! Map) return null;
    return ProductModel.fromMap(
      Map<dynamic, dynamic>.from(snap.value as Map),
      storeId,
    ).toEntity();
  }

  /// Chạy [task] cho từng phần tử theo từng lượt song song tối đa [_chunk],
  /// trả kết quả THEO THỨ TỰ gốc; lỗi đầu tiên (theo thứ tự) được ném lại.
  Future<List<R>> _mapChunked<T, R>(
      List<T> list, Future<R> Function(T) task) async {
    final out = <R>[];
    for (var i = 0; i < list.length; i += _chunk) {
      final part =
          list.sublist(i, i + _chunk > list.length ? list.length : i + _chunk);
      final results = await Future.wait(part.map((e) async {
        try {
          return (await task(e), null as Object?);
        } catch (err) {
          return (null as R?, err);
        }
      }));
      for (final r in results) {
        if (r.$2 != null) throw r.$2!;
        out.add(r.$1 as R);
      }
    }
    return out;
  }

  /// Chuyển trạng thái phiếu nguyên tử (transaction) từ [from] sang [to].
  /// Chặn 2 thiết bị cùng nhận/hủy một phiếu => cộng/hoàn kho 2 lần.
  Future<bool> _claim(
    String id,
    StockTransferStatus from,
    StockTransferStatus to,
  ) async {
    final result =
        await _db.ref('stock_transfers/$id/status').runTransaction((current) {
      // Lần gọi đầu có thể là null (chưa có cache) => trả lại null để Firebase
      // chạy lại với giá trị thật từ máy chủ thay vì hủy nhầm.
      if (current == null) return Transaction.success(null);
      if (current == from.value) return Transaction.success(to.value);
      return Transaction.abort();
    });
    return result.committed && result.snapshot.value == to.value;
  }

  Future<void> _release(String id, StockTransferStatus back) async {
    try {
      await _db.ref('stock_transfers/$id/status').set(back.value);
    } catch (_) {}
  }

  Future<void> _notify(
      StockTransfer t, bool received, UserAccount? user) async {
    final d = _dispatcher;
    if (d == null) return;
    try {
      await d.notifyStockTransfer(
        transfer: t,
        received: received,
        actorName: user?.name,
      );
    } catch (_) {
      // Lỗi thông báo không được làm hỏng nghiệp vụ kho.
    }
  }
}

/// Lưu tạm phiếu chuyển (không đổi tồn kho).
class SaveStockTransferDraftUseCase extends _TransferBase {
  SaveStockTransferDraftUseCase(super.db, super.repo, super.dispatcher);

  Future<StockTransfer> execute(StockTransfer draft) async {
    if (draft.items.isEmpty) {
      throw StockTransferException('Chưa có hàng trong phiếu');
    }
    final id =
        draft.id.isNotEmpty ? draft.id : _db.ref('stock_transfers').push().key!;
    final code = draft.code.isNotEmpty ? draft.code : 'Phiếu tạm';
    final saved = draft.copyWith(
      id: id,
      code: code,
      status: StockTransferStatus.draft,
    );
    await _db.ref('stock_transfers/$id').set(saved.toMap());
    return saved;
  }

  Future<void> delete(String id) => _db.ref('stock_transfers/$id').remove();
}

/// CN gửi hoàn thành phiếu: trừ kho CN gửi, phiếu chuyển sang "Đang chuyển".
class CreateStockTransferUseCase extends _TransferBase {
  CreateStockTransferUseCase(super.db, super.repo, super.dispatcher);

  Future<StockTransfer> execute(
    StockTransfer draft, {
    UserAccount? user,
  }) async {
    if (draft.sourceStoreId.trim().isEmpty ||
        draft.targetStoreId.trim().isEmpty) {
      throw StockTransferException('Chi nhánh không hợp lệ');
    }
    // Luôn dùng mã chuẩn: alias (branch_1/branch_2) làm lệch đường dẫn sản phẩm,
    // chỉ mục chờ nhận và nơi gửi thông báo.
    final source = _TransferBase.canon(draft.sourceStoreId);
    final target = _TransferBase.canon(draft.targetStoreId);
    if (source == target) {
      throw StockTransferException('Không thể chuyển cùng kho');
    }
    if (draft.items.isEmpty) {
      throw StockTransferException('Chưa có hàng trong phiếu');
    }
    for (final item in draft.items) {
      if (item.quantity <= 0) {
        throw StockTransferException('Số lượng phải lớn hơn 0');
      }
    }
    // Gộp dòng trùng sản phẩm: kiểm tra tồn và trừ kho theo TỔNG số lượng
    // (mỗi dòng đọc cùng một tồn nên trước đây chỉ dòng cuối được trừ).
    final merged = <String, StockTransferItem>{};
    for (final item in draft.items) {
      final prev = merged[item.productId];
      merged[item.productId] = prev == null
          ? item
          : prev.copyWith(quantity: prev.quantity + item.quantity);
    }

    final id =
        draft.id.isNotEmpty ? draft.id : _db.ref('stock_transfers').push().key!;
    var draftExists = false;
    if (draft.id.isNotEmpty) {
      final existing = await _repo.getById(draft.id);
      if (existing != null) {
        if (!existing.isDraft) {
          throw StockTransferException('Phiếu đã được gửi đi trước đó');
        }
        draftExists = true;
      }
    }
    final code = (draft.code.isNotEmpty && draft.code.startsWith('TRF'))
        ? draft.code
        : await _repo.nextCode();
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch;
    final updates = <String, dynamic>{};
    final items = <StockTransferItem>[];

    // Mỗi mặt hàng chỉ đọc vài trường nhỏ (không tải cả bản ghi chứa ảnh);
    // lỗi đầu tiên theo thứ tự dòng được ném lại.
    final lines = merged.values.toList();
    final parts = await _mapChunked<StockTransferItem, Map<String, dynamic>>(
        lines, (item) async {
      final product = await _readProduct(source, item.productId);
      if (product == null) {
        throw StockTransferException('Không tìm thấy sản phẩm ${item.name}');
      }
      final stock = product.stockInBranch(source);
      if (stock < item.quantity) {
        throw StockTransferException('Không đủ tồn kho: ${item.name}');
      }
      final out = <String, dynamic>{};
      out['stores/$source/products/${item.productId}/branchStocks'] =
          applyStoreStock(product.branchStocks, source, stock - item.quantity);
      // Đồng bộ bản ghi sản phẩm ở CN nhận (nếu đã có) để tồn CN gửi không lệch.
      final tProduct =
          await _readProduct(target, item.productId, needCost: false);
      if (tProduct != null) {
        out['stores/$target/products/${item.productId}/branchStocks'] =
            applyStoreStock(
                tProduct.branchStocks, source, stock - item.quantity);
      }
      final txId = 'tx_${ts}_${code}_${item.productId}_export';
      out['stores/$source/inventory_transactions/$txId'] = {
        'id': txId,
        'productId': item.productId,
        'type': 'export',
        'quantity': item.quantity,
        'date': now.toIso8601String(),
        'note': 'Chuyển hàng sang ${draft.targetStoreName} ($code)',
        'importPrice': product.costPrice,
        'storeId': source,
        'transferCode': code,
        if (user?.username != null) 'createdBy': user!.username,
        if (user != null) 'createdByName': user.name,
      };
      // Chỉ đọc ảnh sản phẩm khi dòng phiếu chưa có ảnh.
      String? fallbackImage;
      if (item.imageUrl == null || item.imageUrl!.trim().isEmpty) {
        final v = await _child(source, item.productId, 'imageUrl');
        fallbackImage = Product.parseImageUrls(v?.toString()).firstOrNull;
      }
      out['__item'] = item.copyWith(
        imageUrl: transferSafeImageUrl(item.imageUrl ?? fallbackImage),
        unitPrice: product.costPrice,
        receivedQuantity: 0,
      );
      return out;
    });
    for (final part in parts) {
      items.add(part.remove('__item') as StockTransferItem);
      updates.addAll(part);
    }

    final created = StockTransfer(
      id: id,
      code: code,
      status: StockTransferStatus.inTransit,
      sourceStoreId: source,
      sourceStoreName: draft.sourceStoreName,
      targetStoreId: target,
      targetStoreName: draft.targetStoreName,
      items: items,
      note: draft.note,
      createdAt: now,
      createdBy: draft.createdBy,
      createdByName: draft.createdByName,
    );
    updates[StockTransferRepository.pendingIndexPath(target, id)] = true;
    updates['stock_transfers/$id'] = StockTransfer(
      id: id,
      code: code,
      status: StockTransferStatus.inTransit,
      sourceStoreId: source,
      sourceStoreName: draft.sourceStoreName,
      targetStoreId: target,
      targetStoreName: draft.targetStoreName,
      items: items,
      note: draft.note,
      createdAt: now,
      createdBy: user?.username ?? draft.createdBy,
      createdByName: user?.name ?? draft.createdByName,
    ).toMap();

    // Giữ chỗ phiếu tạm ngay trước khi ghi để thiết bị khác không gửi trùng
    // (trừ kho 2 lần).
    if (draftExists &&
        !await _claim(
            id, StockTransferStatus.draft, StockTransferStatus.inTransit)) {
      throw StockTransferException('Phiếu đã được gửi đi trước đó');
    }
    try {
      await _db.ref().update(updates);
    } catch (_) {
      if (draftExists) await _release(id, StockTransferStatus.draft);
      rethrow;
    }
    await _notify(created, false, user);
    return created;
  }
}

/// CN nhận xác nhận số lượng thực nhận: cộng kho CN nhận, phiếu "Đã nhận".
class ReceiveStockTransferUseCase extends _TransferBase {
  ReceiveStockTransferUseCase(super.db, super.repo, super.dispatcher);

  /// [receivedByProduct]: productId -> số lượng thực nhận.
  Future<StockTransfer> execute(
    String transferId, {
    required Map<String, int> receivedByProduct,
    String receiveNote = '',
    UserAccount? user,
  }) async {
    final transfer = await _repo.getById(transferId);
    if (transfer == null) {
      throw StockTransferException('Không tìm thấy phiếu chuyển');
    }
    if (!transfer.isInTransit) {
      throw StockTransferException('Phiếu không ở trạng thái Đang chuyển');
    }

    // Phiếu cũ có thể lưu alias (branch_2): đường dẫn sản phẩm dùng mã chuẩn.
    final source = _TransferBase.canon(transfer.sourceStoreId);
    final target = _TransferBase.canon(transfer.targetStoreId);
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch;
    final updates = <String, dynamic>{};
    final items = <StockTransferItem>[];

    // Giữ chỗ phiếu trước khi cộng kho: chặn nhận trùng từ 2 thiết bị.
    if (!await _claim(transferId, StockTransferStatus.inTransit,
        StockTransferStatus.received)) {
      throw StockTransferException('Phiếu không ở trạng thái Đang chuyển');
    }
    try {
      // Số nhận theo sản phẩm, chia lần lượt cho các dòng trùng sản phẩm (phiếu
      // cũ) để tổng nhận không vượt số khai báo; cộng kho đúng 1 lần/sản phẩm.
      final remaining = <String, int>{
        for (final e in receivedByProduct.entries) e.key: e.value,
      };
      final creditByProduct = <String, int>{};
      final firstLine = <String, StockTransferItem>{};
      for (final item in transfer.items) {
        final avail = (remaining[item.productId] ?? 0).clamp(0, item.quantity);
        remaining[item.productId] = (remaining[item.productId] ?? 0) - avail;
        items.add(item.copyWith(receivedQuantity: avail));
        if (avail > 0) {
          creditByProduct[item.productId] =
              (creditByProduct[item.productId] ?? 0) + avail;
          firstLine.putIfAbsent(item.productId, () => item);
        }
      }

      final credits = creditByProduct.entries.toList();
      final parts =
          await _mapChunked<MapEntry<String, int>, Map<String, dynamic>>(
              credits, (entry) async {
        final item = firstLine[entry.key]!;
        final received = entry.value;
        final targetProduct =
            await _readProduct(target, item.productId, needCost: false);
        final sourceProduct =
            await _readProduct(source, item.productId, needCost: false);
        final base = targetProduct ?? sourceProduct;
        if (base == null) {
          throw StockTransferException('Không tìm thấy sản phẩm ${item.name}');
        }
        final currentTarget = targetProduct?.stockInBranch(target) ?? 0;
        var stocks = applyStoreStock(
            base.branchStocks, target, currentTarget + received);
        if (sourceProduct != null) {
          stocks = applyStoreStock(
              stocks, source, sourceProduct.stockInBranch(source));
        }

        final out = <String, dynamic>{};
        out['stores/$target/products/${item.productId}/branchStocks'] = stocks;
        if (sourceProduct != null) {
          out['stores/$source/products/${item.productId}/branchStocks'] =
              stocks;
        }
        if (targetProduct == null) {
          // CN nhận chưa có sản phẩm: tạo bản ghi từ bản ghi đầy đủ của CN gửi.
          final full = await _readFullProduct(source, item.productId);
          if (full == null) {
            throw StockTransferException(
                'Không tìm thấy sản phẩm ${item.name}');
          }
          out['stores/$target/products/${item.productId}'] =
              ProductModel.fromEntity(full.copyWith(branchStocks: stocks))
                  .toMap();
        }

        final txId = 'tx_${ts}_${transfer.code}_${item.productId}_import';
        out['stores/$target/inventory_transactions/$txId'] = {
          'id': txId,
          'productId': item.productId,
          'type': 'import',
          'quantity': received,
          'date': now.toIso8601String(),
          'note':
              'Nhận chuyển kho từ ${transfer.sourceStoreName} (${transfer.code})',
          'importPrice': item.unitPrice,
          'storeId': target,
          'transferCode': transfer.code,
          if (user?.username != null) 'createdBy': user!.username,
          if (user != null) 'createdByName': user.name,
        };
        return out;
      });
      for (final part in parts) {
        updates.addAll(part);
      }

      final done = transfer.copyWith(
        status: StockTransferStatus.received,
        targetStoreId: target,
        items: items,
        receiveNote: receiveNote.trim(),
        receivedAt: now,
        receivedBy: user?.username,
        receivedByName: user?.name,
      );
      updates['stock_transfers/$transferId'] = done.toMap();
      _clearPending(updates, transfer, transferId);

      await _db.ref().update(updates);
      await _notify(done, true, user);
      return done;
    } catch (_) {
      await _release(transferId, StockTransferStatus.inTransit);
      rethrow;
    }
  }
}

/// Xoá phiếu khỏi chỉ mục chờ nhận (cả khoá chuẩn lẫn khoá alias của phiếu cũ).
void _clearPending(
    Map<String, dynamic> updates, StockTransfer t, String transferId) {
  for (final k in {t.targetStoreId, _TransferBase.canon(t.targetStoreId)}) {
    if (k.trim().isEmpty) continue;
    updates[StockTransferRepository.pendingIndexPath(k, transferId)] = null;
  }
}

/// CN gửi huỷ phiếu đang chuyển (chưa nhận): hoàn lại tồn kho CN gửi.
class CancelStockTransferUseCase extends _TransferBase {
  CancelStockTransferUseCase(super.db, super.repo, super.dispatcher);

  Future<void> execute(String transferId, {UserAccount? user}) async {
    final transfer = await _repo.getById(transferId);
    if (transfer == null || !transfer.isInTransit) {
      throw StockTransferException('Chỉ huỷ được phiếu đang chuyển');
    }
    final source = _TransferBase.canon(transfer.sourceStoreId);
    final target = _TransferBase.canon(transfer.targetStoreId);
    final updates = <String, dynamic>{};
    if (!await _claim(transferId, StockTransferStatus.inTransit,
        StockTransferStatus.cancelled)) {
      throw StockTransferException('Chỉ huỷ được phiếu đang chuyển');
    }
    try {
      // Hoàn kho theo TỔNG số lượng mỗi sản phẩm (phiếu cũ có thể có dòng trùng).
      final qtyByProduct = <String, int>{};
      for (final item in transfer.items) {
        qtyByProduct[item.productId] =
            (qtyByProduct[item.productId] ?? 0) + item.quantity;
      }
      final parts =
          await _mapChunked<MapEntry<String, int>, Map<String, dynamic>>(
              qtyByProduct.entries.toList(), (entry) async {
        final out = <String, dynamic>{};
        final product =
            await _readProduct(source, entry.key, needCost: false);
        if (product == null) return out;
        final restored = product.stockInBranch(source) + entry.value;
        out['stores/$source/products/${entry.key}/branchStocks'] =
            applyStoreStock(product.branchStocks, source, restored);
        // Bản ghi ở CN nhận (nếu có) cũng giữ tồn CN gửi: đồng bộ lại.
        // (1 lần đọc nhỏ: chỉ khi bản ghi đã có branchStocks mới đồng bộ.)
        final tRaw = await _child(target, entry.key, 'branchStocks');
        if (tRaw is Map) {
          final tProduct = ProductModel.fromMap(
              {'id': entry.key, 'branchStocks': tRaw}, target).toEntity();
          out['stores/$target/products/${entry.key}/branchStocks'] =
              applyStoreStock(tProduct.branchStocks, source, restored);
        }
        return out;
      });
      for (final part in parts) {
        updates.addAll(part);
      }
      updates['stock_transfers/$transferId/status'] =
          StockTransferStatus.cancelled.value;
      _clearPending(updates, transfer, transferId);
      await _db.ref().update(updates);
    } catch (_) {
      await _release(transferId, StockTransferStatus.inTransit);
      rethrow;
    }
  }
}
