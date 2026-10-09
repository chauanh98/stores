import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Dải thông báo nhỏ khi mất kết nối tới máy chủ Firebase.
///
/// Dựa trên `.info/connected` (node cục bộ của SDK, không tốn băng thông).
/// Chỉ hiện khi mất kết nối liên tục > [grace] để không nháy lúc mở app,
/// và tự ẩn khi có mạng trở lại — người dùng biết số liệu đang hiển thị có
/// thể chưa mới nhất và các thao tác lưu có thể bị treo cho tới khi có mạng.
class ConnectionStatusBanner extends StatefulWidget {
  const ConnectionStatusBanner({
    super.key,
    this.grace = const Duration(seconds: 4),
  });

  final Duration grace;

  @override
  State<ConnectionStatusBanner> createState() => _ConnectionStatusBannerState();
}

class _ConnectionStatusBannerState extends State<ConnectionStatusBanner> {
  StreamSubscription<DatabaseEvent>? _sub;
  Timer? _graceTimer;
  bool _offline = false;
  bool _everConnected = false;

  @override
  void initState() {
    super.initState();
    try {
      _sub = FirebaseDatabase.instance
          .ref('.info/connected')
          .onValue
          .listen(_onStatus, onError: (_) {});
    } catch (_) {
      // Firebase chưa khởi tạo (test) → không hiển thị gì.
    }
  }

  void _onStatus(DatabaseEvent event) {
    final connected = event.snapshot.value == true;
    if (connected) {
      _everConnected = true;
      _graceTimer?.cancel();
      _graceTimer = null;
      if (_offline && mounted) setState(() => _offline = false);
      return;
    }
    // Lúc mới mở app SDK báo false trước khi bắt tay xong: cho thêm thời gian.
    final delay = _everConnected ? widget.grace : widget.grace * 2;
    _graceTimer ??= Timer(delay, () {
      _graceTimer = null;
      if (mounted) setState(() => _offline = true);
    });
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: !_offline
          ? const SizedBox(width: double.infinity)
          : Material(
              color: AppColors.warningLight,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 18, color: AppColors.warningDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Mất kết nối máy chủ — số liệu có thể chưa mới nhất. '
                        'Kiểm tra mạng trước khi thanh toán / lưu dữ liệu.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.warningDark,
                                  fontWeight: FontWeight.w600,
                                ) ??
                            const TextStyle(
                              fontSize: 12,
                              color: AppColors.warningDark,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
