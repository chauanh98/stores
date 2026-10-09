import 'vietnamese_text_helper.dart';

/// Tìm kiếm thân thiện cho tiếng Việt: không phân biệt hoa/thường, KHÔNG cần
/// gõ dấu ("nuoc ngot" khớp "Nước ngọt"), nhiều từ khoá theo thứ tự bất kỳ.
///
/// Chuỗi đã chuẩn hoá của mỗi đối tượng được cache bằng [Expando] (gắn theo
/// identity của object) nên mỗi phím gõ không phải bỏ dấu lại toàn bộ danh sách.
class SearchTextHelper {
  const SearchTextHelper._();

  static final Expando<String> _cache = Expando<String>('searchText');

  /// Chuỗi tìm kiếm đã chuẩn hoá (thường, không dấu) của [owner], tạo 1 lần
  /// từ [fields] và cache theo identity của [owner].
  static String haystackOf(Object owner, Iterable<String?> Function() fields) {
    final cached = _cache[owner];
    if (cached != null) return cached;
    final joined = fields()
        .whereType<String>()
        .where((f) => f.trim().isNotEmpty)
        .join(' ');
    final normalized = VietnameseTextHelper.normalizeUnaccented(joined);
    _cache[owner] = normalized;
    return normalized;
  }

  /// Chuẩn hoá truy vấn thành các từ khoá (không dấu).
  static List<String> queryTokens(String query) {
    final normalized = VietnameseTextHelper.normalizeUnaccented(query);
    if (normalized.isEmpty) return const [];
    return normalized
        .split(' ')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
  }

  /// `true` nếu MỌI từ khoá đều xuất hiện trong [haystack] (đã chuẩn hoá).
  static bool matchesTokens(String haystack, List<String> tokens) {
    if (tokens.isEmpty) return true;
    for (final token in tokens) {
      if (!haystack.contains(token)) return false;
    }
    return true;
  }
}
