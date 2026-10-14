import '../../domain/entities/notification_item.dart';
import '../../domain/entities/notification_type.dart';
import '../../domain/entities/user_account.dart';

final RegExp _amountPattern =
    RegExp(r'\d[\d.,]*\s?(?:đ|₫|vnđ|vnd)', caseSensitive: false);

/// Bỏ mọi số tiền khỏi nội dung thông báo (dành cho vai trò không có quyền xem giá).
String stripNotificationAmounts(String body) {
  var out = body.replaceAll(_amountPattern, '');
  out = out.replaceAll(RegExp(r'\b(Hoàn|Ghi nợ|Thu)\s+(?=từ|-|$)'), '');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  out = out.replaceFirst(RegExp(r'^[-–:,\s]+'), '');
  out = out.replaceAll(RegExp(r'\s+[-–]\s+[-–]\s+'), ' - ');
  out = out.replaceAll(RegExp(r':\s*[-–]\s+'), ': ');
  // Nhãn tiền còn treo sau khi bỏ số ("Tổng tiền:", "Nợ:"...).
  out = out.replaceAll(
      RegExp(r'(?:^|\s)(?:Tổng tiền|Tổng cộng|Tổng|Nợ|Giá)\s*:\s*(?=$|[-–(])'), ' ');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  return out.trim();
}

/// Áp dụng phân quyền xem thông báo:
/// - Chưa đăng nhập: không thấy gì.
/// - Có quyền xem giá (admin/giám sát): thấy toàn bộ.
/// - Nhân viên: thấy thông báo kho & đơn hàng nhưng KHÔNG có số tiền; không
///   thấy thông báo công nợ/khách hàng.
List<NotificationItem> notificationsForViewer(
  List<NotificationItem> items,
  UserAccount? user,
) {
  if (user == null) return const [];
  if (user.canViewCostPrice) return items;
  return [
    for (final n in items)
      if (n.category != NotificationCategory.customers)
        n.copyWith(body: stripNotificationAmounts(n.body)),
  ];
}

/// Gộp thông báo trùng của cùng một sự kiện được ghi vào nhiều chi nhánh
/// (vd. phiếu chuyển kho ghi cho cả chi nhánh gửi và nhận).
List<NotificationItem> dedupeCrossStoreNotifications(
    List<NotificationItem> items) {
  final seen = <String>{};
  final out = <NotificationItem>[];
  for (final n in items) {
    final target = n.targetId ?? '';
    if (target.isEmpty) {
      out.add(n);
      continue;
    }
    final key = '${n.type.value}|$target|${n.title}|${n.body}';
    if (seen.add(key)) out.add(n);
  }
  return out;
}
