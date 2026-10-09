/// Tham chiếu tới ảnh sản phẩm được lưu tách khỏi bản ghi sản phẩm.
///
/// Trước đây ảnh Base64 (~20–40 KB/ảnh) nằm ngay trong
/// `stores/{storeId}/products/{id}/imageUrl|images`, nên mỗi lần một thiết bị
/// mở listener danh sách sản phẩm là tải về TOÀN BỘ ảnh của mọi sản phẩm
/// (hàng chục MB/lần mở app). Ảnh Base64 nay được chuyển sang node riêng
/// `product_images/{productId}/{contentHash}` (bất biến) và bản ghi sản phẩm
/// chỉ giữ một chuỗi tham chiếu:
///
/// ```
/// rtdb-img://{productId}#{contentHash}
/// ```
///
/// - `contentHash` thay đổi khi nội dung ảnh đổi ⇒ dùng làm khoá cache.
/// - Chuỗi tham chiếu không chứa dấu phẩy nên đi qua mọi chỗ code đang copy
///   `imageUrl` (giỏ hàng, phiếu nhập, import/export) mà không vỡ.
///
/// File này là pure Dart để dùng được ở cả domain, data và presentation.
class ProductImageRef {
  const ProductImageRef._();

  /// Tiền tố nhận diện tham chiếu ảnh.
  static const String scheme = 'rtdb-img://';

  /// Node RTDB gốc chứa ảnh: `product_images/{productId}/{contentHash}`.
  static const String dbNode = 'product_images';

  static bool isRef(String? value) =>
      value != null && value.trim().startsWith(scheme);

  static String build(String productId, String hash) =>
      '$scheme${productId.trim()}#$hash';

  /// Trả về `(productId, hash)` hoặc `null` nếu chuỗi không hợp lệ.
  static ({String productId, String hash})? parse(String? value) {
    if (!isRef(value)) return null;
    final body = value!.trim().substring(scheme.length);
    final sep = body.lastIndexOf('#');
    final productId = (sep >= 0 ? body.substring(0, sep) : body).trim();
    final hash = sep >= 0 ? body.substring(sep + 1).trim() : '';
    if (productId.isEmpty) return null;
    return (productId: productId, hash: hash);
  }

  /// Hash nội dung ổn định (FNV-1a 32-bit, an toàn trên cả web) của danh sách ảnh.
  /// Cùng nội dung ⇒ cùng hash ⇒ cùng chuỗi tham chiếu, nên lưu lại sản phẩm
  /// không đổi ảnh sẽ không tạo thay đổi nào trên bản ghi sản phẩm.
  static String contentHash(List<String> images) {
    var hash = 0x811c9dc5;
    // hash * 0x01000193 (mod 2^32) = (hash << 24) + hash * 0x193, tách ra để
    // không vượt 2^53 trên web (JS number) => cùng kết quả trên mọi nền tảng.
    int mul(int h) => (((h & 0xff) << 24) + h * 0x193) & 0xffffffff;
    void add(int unit) {
      hash = mul(hash ^ (unit & 0xff));
      hash = mul(hash ^ ((unit >> 8) & 0xff));
    }

    for (final image in images) {
      for (final unit in image.codeUnits) {
        add(unit);
      }
      add(0x2c); // ',' separator
    }
    return '${images.length}-${hash.toRadixString(16).padLeft(8, '0')}';
  }
}
