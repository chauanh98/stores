import '../../core/constants/product_image_ref.dart';
import '../../data/datasources/firebase/product_image_store.dart';

/// Cổng ứng dụng để tầng giao diện đọc ảnh sản phẩm lưu tách
/// (`rtdb-img://…`, xem [ProductImageRef]) mà không phụ thuộc trực tiếp Firebase.
class ProductImageResolver {
  const ProductImageResolver._();

  static bool isRef(String? url) => ProductImageRef.isRef(url);

  /// Ảnh đã nằm sẵn trong bộ nhớ cho [ref] (vẽ ngay không cần chờ), hoặc `null`.
  static List<String>? peek(String ref) => ProductImageStore.instance.peek(ref);

  /// Tải ảnh của [ref] (bộ nhớ → file cache → RTDB, chỉ 1 lượt/nội dung).
  static Future<List<String>> resolve(String ref) =>
      ProductImageStore.instance.resolve(ref);

  /// Thay mọi tham chiếu trong [urls] bằng danh sách ảnh thật (giữ thứ tự).
  static Future<List<String>> expandAll(List<String> urls) async {
    if (!urls.any(ProductImageRef.isRef)) return urls;
    final result = <String>[];
    for (final url in urls) {
      if (ProductImageRef.isRef(url)) {
        try {
          result.addAll(await resolve(url));
        } catch (_) {}
      } else {
        result.add(url);
      }
    }
    return result;
  }

  /// Phiên bản đồng bộ của [expandAll] dùng dữ liệu đã có trong bộ nhớ;
  /// tham chiếu chưa tải được giữ nguyên.
  static List<String> expandCached(List<String> urls) {
    if (!urls.any(ProductImageRef.isRef)) return urls;
    final result = <String>[];
    for (final url in urls) {
      final cached = ProductImageRef.isRef(url) ? peek(url) : null;
      if (cached != null && cached.isNotEmpty) {
        result.addAll(cached);
      } else {
        result.add(url);
      }
    }
    return result;
  }
}
