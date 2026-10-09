import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Trạng thái lỗi thống nhất cho các màn hình dữ liệu.
///
/// Hiển thị thông điệp dễ hiểu (mất mạng / không có quyền / lỗi chung) thay
/// vì chuỗi exception thô; chi tiết kỹ thuật vẫn có ở dòng nhỏ bên dưới để hỗ
/// trợ báo lỗi. [onRetry] (tuỳ chọn) hiện nút "Thử lại".
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const ErrorView(this.error, {super.key, this.onRetry});

  ({IconData icon, String title, String hint}) _describe() {
    final raw = error.toString().toLowerCase();
    if (raw.contains('permission') || raw.contains('denied')) {
      return (
        icon: Icons.lock_outline_rounded,
        title: 'Không có quyền truy cập dữ liệu',
        hint: 'Liên hệ quản trị viên để được cấp quyền.',
      );
    }
    if (raw.contains('network') ||
        raw.contains('socket') ||
        raw.contains('timeout') ||
        raw.contains('kết nối') ||
        raw.contains('unavailable') ||
        raw.contains('disconnected')) {
      return (
        icon: Icons.wifi_off_rounded,
        title: 'Mất kết nối mạng',
        hint: 'Kiểm tra Wi‑Fi / 4G rồi thử lại. Dữ liệu sẽ tự đồng bộ khi có mạng.',
      );
    }
    return (
      icon: Icons.error_outline_rounded,
      title: 'Không tải được dữ liệu',
      hint: 'Vui lòng thử lại sau ít phút.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _describe();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.dangerLight,
                shape: BoxShape.circle,
              ),
              child: Icon(info.icon, color: AppColors.danger, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              info.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textHeadline,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              info.hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$error',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Thử lại'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
