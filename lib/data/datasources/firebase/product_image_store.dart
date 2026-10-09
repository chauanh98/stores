import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/product_image_ref.dart';
import '../../../core/utils/image_compression_helper.dart';

/// Payload ghi ảnh: đặt [path] = [node] trong CÙNG multi-path update với bản ghi
/// sản phẩm (ảnh và tham chiếu luôn được ghi nguyên tử cùng nhau).
typedef ProductImagePayload = ({String ref, String path, Map<String, Object?> node});

/// Kho ảnh sản phẩm tách khỏi bản ghi sản phẩm (xem [ProductImageRef]).
///
/// Lưu theo NỘI DUNG: `product_images/{productId}/{hash}`. Mỗi node là bất
/// biến (cùng hash ⇒ cùng nội dung), nên:
/// - hai chi nhánh lệch nhau không bao giờ ghi đè ảnh của nhau;
/// - bản ghi cũ / form sửa cũ vẫn trỏ đúng ảnh của nó;
/// - cache trên máy (khoá theo hash) không bao giờ lỗi thời.
///
/// Đọc: [resolve] tải MỘT lần cho mỗi nội dung: bộ nhớ (LRU) → file cache trên
/// máy → RTDB `get()` (không giữ listener).
class ProductImageStore {
  ProductImageStore._();

  static final ProductImageStore instance = ProductImageStore._();

  /// Số tham chiếu giữ trong bộ nhớ (mỗi tham chiếu ~20–40 KB Base64).
  static const int _memoryLimit = 150;

  FirebaseDatabase? _dbOverride;
  FirebaseDatabase get _db => _dbOverride ?? FirebaseDatabase.instance;

  @visibleForTesting
  void debugSetDatabase(FirebaseDatabase? db) => _dbOverride = db;

  // LinkedHashMap giữ thứ tự chèn => xoá phần tử cũ nhất khi vượt giới hạn.
  final LinkedHashMap<String, List<String>> _memory =
      LinkedHashMap<String, List<String>>();
  final Set<String> _missing = <String>{};
  final Map<String, Future<List<String>>> _inflight = {};
  Directory? _cacheDir;
  bool _cacheDirResolved = false;

  static String nodePath(String productId, String hash) =>
      '${ProductImageRef.dbNode}/${productId.trim()}/$hash';

  void _remember(String ref, List<String> images) {
    _memory.remove(ref);
    _memory[ref] = List.unmodifiable(images);
    while (_memory.length > _memoryLimit) {
      _memory.remove(_memory.keys.first);
    }
  }

  /// Ảnh đã có sẵn trong bộ nhớ (để vẽ ngay không cần chờ), hoặc `null`.
  List<String>? peek(String ref) {
    final key = ref.trim();
    final hit = _memory.remove(key);
    if (hit != null) _memory[key] = hit; // làm mới thứ tự LRU
    if (hit == null && _missing.contains(key)) return const [];
    return hit;
  }

  /// Trả về danh sách ảnh (Data URL / http URL) của tham chiếu [ref].
  /// Nhiều widget cùng hỏi một tham chiếu chỉ tạo đúng 1 lượt tải.
  Future<List<String>> resolve(String ref) {
    final key = ref.trim();
    final cached = peek(key);
    if (cached != null) return SynchronousFuture(cached);
    return _inflight.putIfAbsent(key, () async {
      try {
        final images = await _load(key);
        if (images.isNotEmpty) {
          _remember(key, images);
        } else {
          // Không có node: nhớ trong phiên để không `get()` lại mỗi lần rebuild.
          _missing.add(key);
        }
        return images;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  Future<List<String>> _load(String ref) async {
    final parsed = ProductImageRef.parse(ref);
    if (parsed == null || parsed.hash.isEmpty) return const [];

    final fromDisk = await _readDisk(parsed.productId, parsed.hash);
    if (fromDisk != null && fromDisk.isNotEmpty) return fromDisk;

    final snap = await _db.ref(nodePath(parsed.productId, parsed.hash)).get();
    final images = _parseImages(snap.value);
    // Chỉ cache khi nội dung khớp đúng hash của tham chiếu.
    if (images.isNotEmpty &&
        ProductImageRef.contentHash(images) == parsed.hash) {
      unawaited(_writeDisk(parsed.productId, parsed.hash, images));
    }
    return images;
  }

  static List<String> _parseImages(Object? value) {
    Object? raw = value;
    if (raw is Map) raw = raw['images'];
    final Iterable<Object?> items = raw is List
        ? raw
        : raw is Map
            ? raw.values
            : const [];
    return items
        .whereType<Object>()
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  /// Gom tất cả ảnh khai báo trong map sản phẩm (`images` + `imageUrl`).
  static List<String> collectImages(Map<String, dynamic> productMap) {
    final result = <String>[];
    final seen = <String>{};
    void addAll(Iterable<String> urls) {
      for (final url in urls) {
        final t = url.trim();
        if (t.isNotEmpty && seen.add(t)) result.add(t);
      }
    }

    final images = productMap['images'];
    if (images is List) {
      addAll(images.whereType<Object>().map((e) => e.toString()));
    }
    addAll(ImageCompressionHelper.parseImageUrls(
        productMap['imageUrl']?.toString()));
    return result;
  }

  static ProductImagePayload _payloadFor(String productId, List<String> images) {
    final hash = ProductImageRef.contentHash(images);
    return (
      ref: ProductImageRef.build(productId, hash),
      path: nodePath(productId, hash),
      node: {
        'images': images,
        'updatedAt': ServerValue.timestamp,
      },
    );
  }

  /// Chuẩn bị tách ảnh Base64 của [productMap]: trả về map sản phẩm mới (chỉ
  /// còn tham chiếu) và payload node ảnh để caller ghi trong CÙNG một update.
  /// Không có Base64 ⇒ `payload == null` và map giữ nguyên.
  ///
  /// An toàn dữ liệu: nếu cần gộp với ảnh cũ (tham chiếu) mà không đọc được
  /// (offline…), map được giữ nguyên — ảnh vẫn nằm trong bản ghi, lần bảo trì
  /// sau sẽ tách tiếp.
  Future<({Map<String, dynamic> map, ProductImagePayload? payload})> prepare(
    String productId,
    Map<String, dynamic> productMap,
  ) async {
    final id = productId.trim();
    final images = collectImages(productMap);
    if (id.isEmpty || !images.any(ImageCompressionHelper.isBase64DataUrl)) {
      return (map: productMap, payload: null);
    }

    final expanded = <String>[];
    final seen = <String>{};
    for (final image in images) {
      if (ProductImageRef.isRef(image)) {
        List<String> resolved;
        try {
          resolved = await resolve(image);
        } catch (e) {
          debugPrint('[ProductImageStore] keep inline, cannot resolve $image: $e');
          return (map: productMap, payload: null);
        }
        if (resolved.isEmpty) {
          debugPrint('[ProductImageStore] keep inline, empty ref $image');
          return (map: productMap, payload: null);
        }
        for (final r in resolved) {
          if (seen.add(r)) expanded.add(r);
        }
      } else if (seen.add(image)) {
        expanded.add(image);
      }
    }

    final payload = _payloadFor(id, expanded);
    _remember(payload.ref, expanded);
    unawaited(_writeDisk(
        id, ProductImageRef.parse(payload.ref)!.hash, List.of(expanded)));
    return (
      map: {
        ...productMap,
        'imageUrl': payload.ref,
        'images': const <String>[],
      },
      payload: payload,
    );
  }

  /// Bản đồng bộ (không đọc mạng) dùng cho migration hàng loạt: chỉ xử lý bản
  /// ghi có Base64 và CHƯA có tham chiếu nào. Trả về `null` nếu không cần tách.
  ProductImagePayload? buildMigrationPayload(
    String productId,
    Map<String, dynamic> productMap,
  ) {
    final id = productId.trim();
    if (id.isEmpty) return null;
    final images = collectImages(productMap);
    if (images.isEmpty ||
        !images.any(ImageCompressionHelper.isBase64DataUrl) ||
        images.any(ProductImageRef.isRef)) {
      // Có tham chiếu lẫn Base64 ⇒ để `prepare` (cần đọc ảnh cũ) xử lý khi sửa SP.
      return null;
    }
    final payload = _payloadFor(id, images);
    _remember(payload.ref, images);
    return payload;
  }

  // ---------------------------------------------------------------------------
  // Disk cache (mobile/desktop). Web dùng cache bộ nhớ.
  // ---------------------------------------------------------------------------

  Future<Directory?> _dir() async {
    if (_cacheDirResolved) return _cacheDir;
    _cacheDirResolved = true;
    if (kIsWeb) return null;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/product_images_cache');
      if (!await dir.exists()) await dir.create(recursive: true);
      _cacheDir = dir;
    } catch (e) {
      debugPrint('[ProductImageStore] disk cache disabled: $e');
      _cacheDir = null;
    }
    return _cacheDir;
  }

  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^\w\-]'), '_');

  static String _fileName(String productId, String hash) =>
      '${_safe(productId)}__${_safe(hash)}.json';

  Future<List<String>?> _readDisk(String productId, String hash) async {
    if (hash.isEmpty) return null;
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final file = File('${dir.path}/${_fileName(productId, hash)}');
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList(growable: false);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeDisk(
      String productId, String hash, List<String> images) async {
    if (hash.isEmpty) return;
    final dir = await _dir();
    if (dir == null) return;
    try {
      // Xoá bản cũ của ĐÚNG sản phẩm này (tên file "{id}__{hash}.json").
      final keep = _fileName(productId, hash);
      final prefix = '${_safe(productId)}__';
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name != keep &&
            name.startsWith(prefix) &&
            !name.substring(prefix.length).contains('__')) {
          unawaited(entity.delete().then((_) {}, onError: (_) {}));
        }
      }
      await File('${dir.path}/$keep').writeAsString(jsonEncode(images));
    } catch (_) {}
  }
}
