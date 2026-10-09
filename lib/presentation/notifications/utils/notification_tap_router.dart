import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/notifications/local_notification_service.dart';
import '../../../application/notifications/notifications_providers.dart';
import 'notification_navigation_handler.dart';

/// Nối sự kiện "người dùng bấm vào thông báo hệ thống" (local notification
/// hoặc FCM, kể cả khi app được mở từ trạng thái tắt hẳn) với
/// [NotificationNavigationHandler] để mở đúng hoá đơn / phiếu nhập / khách hàng.
class NotificationTapRouter {
  NotificationTapRouter({
    required this.ref,
    required this.navigatorKey,
  });

  final WidgetRef ref;
  final GlobalKey<NavigatorState> navigatorKey;

  final List<StreamSubscription> _subs = [];
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;

    final local = ref.read(localNotificationServiceProvider);
    _subs.add(local.onNotificationTapped.listen(_handlePayload));
    if (local is FlutterLocalNotificationServiceImpl) {
      unawaited(local.takeLaunchPayload().then((payload) {
        if (payload != null) _handlePayload(payload);
      }));
    }

    final push = ref.read(pushNotificationServiceProvider);
    if (push is FirebasePushNotificationServiceImpl) {
      _subs.add(push.onMessageOpened.listen(_handleRemoteMessage));
      final pending = push.takePendingOpenedMessage();
      if (pending != null) _handleRemoteMessage(pending);
    }
  }

  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }

  void _handlePayload(String? raw) {
    final payload = NotificationPayload.tryParse(raw);
    if (payload == null) {
      _openNotificationCenter();
      return;
    }
    _open(
      id: payload.id,
      storeId: payload.storeId,
      type: payload.type,
      targetRoute: payload.targetRoute,
      targetId: payload.targetId,
      // id lấy từ chính bản ghi RTDB nên có thể đánh dấu đã đọc.
      canMarkRead: payload.id.isNotEmpty,
    );
  }

  void _handleRemoteMessage(RemoteMessage message) {
    String? clean(Object? v) {
      final s = v?.toString().trim();
      if (s == null || s.isEmpty || s == 'null' || s == 'undefined') {
        return null;
      }
      return s;
    }

    final data = message.data;
    final notificationId = clean(data['notificationId']) ?? clean(data['id']);
    _open(
      id: notificationId ?? '',
      storeId: clean(data['storeId']) ?? clean(data['store_id']) ?? '',
      type: clean(data['type']),
      targetRoute: clean(data['targetRoute']) ?? clean(data['target_route']),
      targetId: clean(data['targetId']) ?? clean(data['target_id']),
      // Không có id bản ghi => không ghi isRead (tránh tạo node rác).
      canMarkRead: notificationId != null,
    );
  }

  void _open({
    required String id,
    required String storeId,
    required String? type,
    required String? targetRoute,
    required String? targetId,
    required bool canMarkRead,
  }) {
    // Chờ khung hình kế tiếp để Navigator đã sẵn sàng (trường hợp mở app lạnh).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      if ((targetId ?? '').isEmpty) {
        _openNotificationCenter();
        return;
      }
      final item = NotificationItem(
        id: id,
        storeId: storeId,
        title: '',
        body: '',
        type: NotificationType.fromString(type),
        isRead: !canMarkRead,
        createdAt: DateTime.now(),
        targetRoute: targetRoute,
        targetId: targetId,
      );
      await NotificationNavigationHandler.handleTap(
        context: context,
        ref: ref,
        notification: item,
      );
    });
  }

  void _openNotificationCenter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = navigatorKey.currentState;
      if (navigator == null) return;
      navigator.pushNamed('/notifications');
    });
  }
}
