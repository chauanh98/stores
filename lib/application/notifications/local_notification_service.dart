import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firebase/server_clock.dart';
import 'notifications_providers.dart';

/// Callback invoked when a user taps a local notification.
typedef NotificationTapCallback = void Function(String? payload);

/// Pure interface for local notifications.
/// Allows clean swapping with [FakeLocalNotificationService] in unit/widget tests
/// to prevent hanging on platform channel invocations.
abstract class LocalNotificationService {
  /// Whether the service has been initialized.
  bool get isInitialized;

  /// Broadcast stream of notification tap payloads.
  Stream<String?> get onNotificationTapped;

  /// Initializes the local notification plugin and configures platform channels.
  Future<bool> initialize({NotificationTapCallback? onNotificationTapped});

  /// Requests notification permissions on platforms that support/require it (Android 13+, iOS).
  Future<bool?> requestPermissions();

  /// Displays a local heads-up notification with specified parameters.
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  });

  /// Displays a local heads-up notification derived from a [NotificationItem].
  Future<void> showFromNotificationItem(NotificationItem item);

  /// Cancels a specific notification by [id].
  Future<void> cancel(int id);

  /// Cancels all active notifications.
  Future<void> cancelAll();
}

/// Structured payload model for notification tap events.
/// Encapsulates routing and identification data for seamless deep-linking.
class NotificationPayload {
  final String id;
  final String storeId;
  final String? type;
  final String? targetRoute;
  final String? targetId;

  const NotificationPayload({
    required this.id,
    required this.storeId,
    this.type,
    this.targetRoute,
    this.targetId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        if (type != null) 'type': type,
        if (targetRoute != null) 'targetRoute': targetRoute,
        if (targetId != null) 'targetId': targetId,
      };

  String toJsonString() => jsonEncode(toMap());

  static NotificationPayload? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        String? clean(dynamic v) {
          if (v == null) return null;
          final s = v.toString().trim();
          final l = s.toLowerCase();
          return (s.isEmpty || l == 'null' || l == 'undefined' || l == 'none') ? null : s;
        }

        return NotificationPayload(
          id: clean(decoded['id']) ?? clean(decoded['notificationId']) ?? '',
          storeId: clean(decoded['storeId']) ?? clean(decoded['store_id']) ?? '',
          type: clean(decoded['type']),
          targetRoute: clean(decoded['targetRoute']) ?? clean(decoded['target_route']),
          targetId: clean(decoded['targetId']) ?? clean(decoded['target_id']),
        );
      }
    } catch (_) {}
    return null;
  }
}

/// 100% Free Production Implementation of [LocalNotificationService] using
/// `flutter_local_notifications`. Triggers system status bar pop-up (banner)
/// without any paid third-party dependencies or Firebase cloud messaging charges.
class FlutterLocalNotificationServiceImpl implements LocalNotificationService {
  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String?> _tapController =
      StreamController<String?>.broadcast();

  bool _isInitialized = false;
  NotificationTapCallback? _externalTapCallback;

  FlutterLocalNotificationServiceImpl([
    FlutterLocalNotificationsPlugin? plugin,
  ]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'store_notifications_channel';
  static const String channelName = 'Thông báo cửa hàng';
  static const String channelDescription =
      'Kênh nhận thông báo đơn hàng, nhập kho và công nợ chi nhánh';

  @override
  bool get isInitialized => _isInitialized;

  @override
  Stream<String?> get onNotificationTapped => _tapController.stream;

  @override
  Future<bool> initialize({NotificationTapCallback? onNotificationTapped}) async {
    _externalTapCallback = onNotificationTapped;
    if (_isInitialized) return true;

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      final success = await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          _tapController.add(payload);
          _externalTapCallback?.call(payload);
        },
      );

      // Create Android Notification Channel with MAX importance for heads-up banner
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        const channel = AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        );
        await androidPlugin.createNotificationChannel(channel);
      }

      _isInitialized = success ?? true;
      return _isInitialized;
    } catch (e) {
      debugPrint('LocalNotificationService: init skipped or failed: $e');
      return false;
    }
  }

  @override
  Future<bool?> requestPermissions() async {
    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        return await androidPlugin.requestNotificationsPermission();
      }

      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        return await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      final macosPlugin = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      if (macosPlugin != null) {
        return await macosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      return true;
    } catch (e) {
      debugPrint('LocalNotificationService: requestPermissions failed: $e');
      return false;
    }
  }

  @override
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      const androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        // Cùng 1 sự kiện có thể đến từ cả listener RTDB lẫn FCM (cùng id):
        // cập nhật lại thông báo cũ thay vì rung/kêu lần 2.
        onlyAlertOnce: true,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      final safeId = id <= 0 ? (id == 0 ? 1 : -id) : id;
      await _plugin.show(
        safeId,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('LocalNotificationService: showNotification skipped: $e');
    }
  }

  @override
  Future<void> showFromNotificationItem(NotificationItem item) async {
    // Generate safe positive non-zero 31-bit integer ID compatible with Android Java int
    final int hash = item.id.hashCode & 0x7FFFFFFF;
    final int id = hash == 0 ? 1 : hash;
    final payload = NotificationPayload(
      id: item.id,
      storeId: item.storeId,
      type: item.type.value,
      targetRoute: item.targetRoute,
      targetId: item.targetId,
    ).toJsonString();

    await showNotification(
      id: id,
      title: item.title,
      body: item.body,
      payload: payload,
    );
  }

  /// Payload của local notification đã MỞ app từ trạng thái tắt hẳn (chỉ
  /// trả về 1 lần), để điều hướng tới đúng màn hình sau khi đăng nhập xong.
  bool _launchPayloadConsumed = false;
  Future<String?> takeLaunchPayload() async {
    if (_launchPayloadConsumed) return null;
    _launchPayloadConsumed = true;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        return details?.notificationResponse?.payload;
      }
    } catch (e) {
      debugPrint('LocalNotificationService: launch details failed: $e');
    }
    return null;
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}

/// Recorded call descriptor for [FakeLocalNotificationService].
class ShowNotificationCall {
  final int id;
  final String title;
  final String body;
  final String? payload;

  const ShowNotificationCall({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
  });
}

/// In-memory fake implementation of [LocalNotificationService] for unit, widget,
/// and integration tests. Completely avoids platform channels, eliminating test hangs.
class FakeLocalNotificationService implements LocalNotificationService {
  @override
  bool isInitialized = false;

  bool permissionsRequested = false;
  bool? permissionResult = true;
  NotificationTapCallback? onNotificationTappedCallback;

  final StreamController<String?> _tapController =
      StreamController<String?>.broadcast();

  final List<NotificationItem> displayedItems = [];
  final List<ShowNotificationCall> displayedCalls = [];
  final List<int> cancelledIds = [];
  bool cancelledAll = false;

  @override
  Stream<String?> get onNotificationTapped => _tapController.stream;

  @override
  Future<bool> initialize({NotificationTapCallback? onNotificationTapped}) async {
    onNotificationTappedCallback = onNotificationTapped;
    isInitialized = true;
    return true;
  }

  @override
  Future<bool?> requestPermissions() async {
    permissionsRequested = true;
    return permissionResult;
  }

  @override
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    displayedCalls.add(ShowNotificationCall(
      id: id,
      title: title,
      body: body,
      payload: payload,
    ));
  }

  @override
  Future<void> showFromNotificationItem(NotificationItem item) async {
    displayedItems.add(item);
    final hash = item.id.hashCode & 0x7FFFFFFF;
    final id = hash == 0 ? 1 : hash;
    final payload = NotificationPayload(
      id: item.id,
      storeId: item.storeId,
      type: item.type.value,
      targetRoute: item.targetRoute,
      targetId: item.targetId,
    ).toJsonString();

    await showNotification(
      id: id,
      title: item.title,
      body: item.body,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelledAll = true;
  }

  /// Helper to simulate user tapping a notification in test scenarios.
  void simulateTap(String? payload) {
    _tapController.add(payload);
    onNotificationTappedCallback?.call(payload);
  }

  /// Resets recorded interactions.
  void clear() {
    displayedItems.clear();
    displayedCalls.clear();
    cancelledIds.clear();
    cancelledAll = false;
    permissionsRequested = false;
  }
}

/// Service that watches notification streams and triggers local notifications
/// only for fresh unread items (`createdAt` within [maxAge], default 60s).
/// Implements deduplication to prevent re-triggering upon stream refreshes.
class NotificationListenerService {
  final LocalNotificationService _localNotificationService;
  final Set<String> _shownIds = <String>{};
  final Duration maxAge;
  final DateTime Function()? clock;

  NotificationListenerService({
    required LocalNotificationService localNotificationService,
    this.maxAge = const Duration(seconds: 60),
    this.clock,
  }) : _localNotificationService = localNotificationService;

  /// Unmodifiable view of notification IDs that have already triggered a pop-up.
  Set<String> get shownIds => Set.unmodifiable(_shownIds);

  /// Evaluates incoming notification items and triggers local pop-ups for eligible items.
  /// Returns the number of new notifications triggered.
  Future<int> processNotifications(List<NotificationItem> items) async {
    // Mặc định dùng giờ đã hiệu chỉnh theo máy chủ để không bỏ sót pop-up khi
    // đồng hồ máy nhận và máy tạo sự kiện lệch nhau.
    final now = (clock != null ? clock!() : ServerClock.now()).toUtc();
    int triggeredCount = 0;

    for (final item in items) {
      if (item.isRead) continue;
      if (_shownIds.contains(item.id)) continue;

      final itemTime = item.createdAt.toUtc();
      final age = now.difference(itemTime);

      // Allow small clock skew (-10s to maxAge)
      if (age >= const Duration(seconds: -10) && age <= maxAge) {
        _shownIds.add(item.id);
        await _localNotificationService.showFromNotificationItem(item);
        triggeredCount++;
      }
    }

    // Bound cache memory: keep only current items if set grows beyond 500
    if (_shownIds.length > 500) {
      final currentIds = items.map((e) => e.id).toSet();
      _shownIds.retainAll(currentIds);
    }

    return triggeredCount;
  }

  /// Clears internal cache of shown notification IDs.
  void reset() {
    _shownIds.clear();
  }
}

// ============================================================================
// Riverpod Providers
// ============================================================================

/// Provider supplying the [LocalNotificationService] instance.
/// Overridable in tests via `overrideWithValue(FakeLocalNotificationService())`.
final localNotificationServiceProvider =
    Provider<LocalNotificationService>((ref) {
  final service = FlutterLocalNotificationServiceImpl();
  // Asynchronously initialize without blocking provider creation
  unawaited(service.initialize());
  return service;
});

/// Auto-disposing listener service provider that hooks into [notificationStreamProvider]
/// and automatically dispatches heads-up pop-ups when fresh notifications arrive for Admin/Owner.
final notificationListenerServiceProvider =
    Provider.autoDispose<NotificationListenerService>((ref) {
  final localService = ref.watch(localNotificationServiceProvider);
  final listener = NotificationListenerService(
    localNotificationService: localService,
    maxAge: const Duration(seconds: 60),
  );

  // Nghe mọi chi nhánh của Admin/Owner (không chỉ chi nhánh đang xem).
  ref.listen<AsyncValue<List<NotificationItem>>>(
    popupNotificationStreamProvider,
    (previous, next) {
      next.whenData((items) {
        unawaited(listener.processNotifications(items));
      });
    },
    fireImmediately: true,
  );

  return listener;
});
