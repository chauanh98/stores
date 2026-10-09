import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/product_image_ref.dart';
import '../../../core/utils/image_compression_helper.dart';

/// Kho ảnh sản phẩm tách khỏi bản ghi sản phẩm (xem [ProductImageRef]).
///
/// - Ghi: [externalize] chuyển mọi ảnh Base64 trong map sản phẩm sang
///   `product_images/{productId}` và thay bằng chuỗi tham chiếu.
/// - Đọc: [resolve] tải ảnh theo tham chiếu, MỘT lần cho mỗi nội dung:
///   bộ nhớ → file cache trên máy → RTDB `get()` (không giữ listener).
///   Vì tham chiếu chứa hash nội dung, cache trên máy không bao giờ lỗi thời.
class ProductImageStore {
  ProductImageStore._();

  static final ProductImageStore instance = ProductImageStore._();

  FirebaseDatabase? _dbOverride;
  FirebaseDatabase get _db => _dbOverride ?? FirebaseDatabase.instance;

  @visibleForTesting
  void debugSetDatabase(FirebaseDatabase? db) => _dbOverride = db;

  final Map<String, List<String>> _memory = {};
  final Map<String, Future<List<String>>> _inflight = {};
  Directory? _cacheDir;
  bool _cacheDirResolved = false;

  /// Ảnh đã có sẵn trong bộ nhớ (để vẽ ngay không cần chờ), hoặc `null`.
  List<String>? peek(String ref) => _memory[ref.trim()];

  /// Trả về danh sách ảnh (Data URL / http URL) của tham chiếu [ref].
  /// Nhiều widget cùng hỏi một tham chiếu chỉ tạo đúng 1 lượt tải.
  Future<List<String>> resolve(String ref) {
    final key = ref.trim();
    final cached = _memory[key];
    if (cached != null) return SynchronousFuture(cached);
    return _inflight.putIfAbsent(key, () async {
      try {
        final images = await _load(key);
        if (images.isNotEmpty) _memory[key] = images;
        return images;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  Future<List<String>> _load(String ref) async {
    final parsed = ProductImageRef.parse(ref);
    if (parsed == null) return const [];

    final fromDisk = await _readDisk(parsed.productId, parsed.hash);
    if (fromDisk != null && fromDisk.isNotEmpty) return fromDisk;

    final snap =
        await _db.ref('${ProductImageRef.dbNode}/${parsed.productId}').get();
    final images = _parseImages(snap.value);
    if (images.isNotEmpty) {
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

  /// Chuyển ảnh Base64 của [productMap] sang `product_images/{productId}` và
  /// trả về map mới chỉ chứa chuỗi tham chiếu. Không có Base64 ⇒ trả map gốc.
  ///
  /// An toàn dữ liệu: nếu không đọc được ảnh cũ (offline…) để gộp, map được
  /// giữ nguyên (ảnh vẫn nằm trong bản ghi) — lần bảo trì sau sẽ tách tiếp.
  Future<Map<String, dynamic>> externalize(
    String productId,
    Map<String, dynamic> productMap, {
    FirebaseDatabase? database,
  }) async {
    final id = productId.trim();
    if (id.isEmpty) return productMap;

    final images = collectImages(productMap);
    if (!images.any(ImageCompressionHelper.isBase64DataUrl)) {
      return productMap;
    }

    final expanded = <String>[];
    final seen = <String>{};
    for (final image in images) {
      if (ProductImageRef.isRef(image)) {
        final List<String> resolved;
        try {
          resolved = await resolve(image);
        } catch (e) {
          debugPrint('[ProductImageStore] keep inline, cannot resolve $image: $e');
          return productMap;
        }
        if (resolved.isEmpty) {
          debugPrint('[ProductImageStore] keep inline, empty ref $image');
          return productMap;
        }
        for (final r in resolved) {
          if (seen.add(r)) expanded.add(r);
        }
      } else if (seen.add(image)) {
        expanded.add(image);
      }
    }

    final hash = ProductImageRef.contentHash(expanded);
    final ref = ProductImageRef.build(id, hash);
    await (database ?? _db).ref('${ProductImageRef.dbNode}/$id').set({
      'images': expanded,
      'hash': hash,
      'updatedAt': ServerValue.timestamp,
    });
    _memory[ref] = List.unmodifiable(expanded);
    unawaited(_writeDisk(id, hash, expanded));

    return {
      ...productMap,
      'imageUrl': ref,
      'images': const <String>[],
    };
  }

  /// Ghi trực tiếp (dùng cho migration nhiều sản phẩm trong 1 lượt update).
  /// Trả về `(ref, nodeValue)` để caller gộp vào multi-path update.
  ({String ref, Map<String, Object?> node})? buildExternalPayload(
    String productId,
    Map<String, dynamic> productMap,
  ) {
    final id = productId.trim();
    if (id.isEmpty) return null;
    final images = collectImages(productMap);
    if (images.isEmpty ||
        !images.any(ImageCompressionHelper.isBase64DataUrl) ||
        images.any(ProductImageRef.isRef)) {
      // Có tham chiếu lẫn Base64 ⇒ để `externalize` (cần đọc ảnh cũ) xử lý.
      return null;
    }
    final hash = ProductImageRef.contentHash(images);
    final ref = ProductImageRef.build(id, hash);
    _memory[ref] = List.unmodifiable(images);
    return (
      ref: ref,
      node: {
        'images': images,
        'hash': hash,
        'updatedAt': ServerValue.timestamp,
      },
    );
  }

  Future<void> deleteFor(String productId, {FirebaseDatabase? database}) async {
    final id = productId.trim();
    if (id.isEmpty) return;
    try {
      await (database ?? _db).ref('${ProductImageRef.dbNode}/$id').remove();
    } catch (e) {
      debugPrint('[ProductImageStore] delete $id failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Disk cache (mobile/desktop). Web dùng cache HTTP + bộ nhớ.
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

  static String _fileName(String productId, String hash) {
    final safeId = productId.replaceAll(RegExp(r'[^\w\-]'), '_');
    final safeHash = hash.replaceAll(RegExp(r'[^\w\-]'), '_');
    return '${safeId}_$safeHash.json';
  }

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
      // Xoá bản cũ của cùng sản phẩm (hash khác) để cache không phình.
      final prefix = '${productId.replaceAll(RegExp(r'[^\w\-]'), '_')}_';
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith(prefix) && name != _fileName(productId, hash)) {
            unawaited(entity.delete().then((_) {}, onError: (_) {}));
          }
        }
      }
      await File('${dir.path}/${_fileName(productId, hash)}')
          .writeAsString(jsonEncode(images), flush: false);
    } catch (_) {}
  }
}
