import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/fcm_token_repository.dart';
import 'local_notification_service.dart';

/// Top-level background FCM message handler required by `firebase_messaging`.
/// Must be an entry point and must not depend on UI context or active Flutter views.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('[FCM Background] Firebase.initializeApp: $e');
  }
  await handleFcmBackgroundMessage(message);
}

/// Core parser and local notification dispatcher for background/terminated FCM messages.
/// Accepts an optional [localNotificationService] parameter for deterministic unit testing.
Future<void> handleFcmBackgroundMessage(
  RemoteMessage message, {
  LocalNotificationService? localNotificationService,
}) async {
  try {
    final data = message.data;
    final notification = message.notification;

    String? cleanString(dynamic val) {
      if (val == null) return null;
      final str = val.toString().trim();
      final lower = str.toLowerCase();
      if (str.isEmpty || lower == 'null' || lower == 'undefined' || lower == 'none') return null;
      return str;
    }

    // Extract explicit title and body from data payload or notification payload
    final String? explicitTitle = cleanString(data['title']) ??
        cleanString(notification?.title);

    final String? explicitBody = cleanString(data['body']) ??
        cleanString(notification?.body);

    // If neither explicit title nor body was provided, cleanly skip displaying empty popup
    if (explicitTitle == null && explicitBody == null) {
      return;
    }

    final String title = explicitTitle ?? 'Thông báo cửa hàng';
    final String body = explicitBody ?? '';

    final String idStr = cleanString(data['notificationId']) ??
        cleanString(data['id']) ??
        cleanString(message.messageId) ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final int hash = idStr.hashCode & 0x7FFFFFFF;
    final int notifId = hash == 0 ? 1 : hash;

    final payload = NotificationPayload(
      id: idStr,
      storeId: cleanString(data['storeId']) ?? cleanString(data['store_id']) ?? '',
      type: cleanString(data['type']),
      targetRoute: cleanString(data['targetRoute']) ?? cleanString(data['target_route']),
      targetId: cleanString(data['targetId']) ?? cleanString(data['target_id']),
    ).toJsonString();

    final service = localNotificationService ?? FlutterLocalNotificationServiceImpl();
    await service.showNotification(
      id: notifId,
      title: title,
      body: body,
      payload: payload,
    );
  } catch (e, stackTrace) {
    debugPrint('[FCM Background Handler] Error displaying background notification: $e\n$stackTrace');
  }
}

/// Pure interface for Push Notification (FCM) operations.
/// Allows clean swapping with [FakePushNotificationService] in unit/widget tests.
abstract class PushNotificationService {
  /// Whether the service has been initialized.
  bool get isInitialized;

  /// Current cached FCM device token, if available.
  String? get currentToken;

  /// Stream of incoming foreground FCM messages.
  Stream<RemoteMessage> get onMessage;

  /// Stream of FCM token refresh events.
  Stream<String> get onTokenRefresh;

  /// Initializes the Firebase Messaging handlers and listeners.
  Future<bool> initialize();

  /// Requests push notification permissions on supported platforms.
  Future<bool?> requestPermissions();

  /// Retrieves the current device registration token from FCM.
  Future<String?> getToken();

  /// Registers or refreshes the Admin FCM token in RTDB under:
  /// `stores/$storeId/fcm_tokens/$userId/$tokenId`
  Future<void> registerAdminToken({
    required String storeId,
    required String userId,
  });

  /// Unregisters the current device's FCM token upon Admin logout:
  /// `stores/$storeId/fcm_tokens/$userId/$tokenId`
  Future<void> unregisterAdminToken({
    required String storeId,
    required String userId,
  });

  /// Broadcasts/syncs push notification triggers to all registered Admin devices.
  Future<void> syncPushNotification({
    required String storeId,
    required NotificationItem notification,
  });
}

/// Production implementation of [PushNotificationService] utilizing `firebase_messaging`.
class FirebasePushNotificationServiceImpl implements PushNotificationService {
  final FcmTokenRepository _repository;
  final LocalNotificationService _localNotificationService;
  final FirebaseMessaging? _messaging;

  bool _isInitialized = false;
  String? _currentToken;
  final Set<String> _registeredStoreIds = {};
  String? _registeredUserId;

  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  final StreamController<RemoteMessage> _messageController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<String> _tokenRefreshController =
      StreamController<String>.broadcast();

  FirebasePushNotificationServiceImpl({
    required FcmTokenRepository repository,
    required LocalNotificationService localNotificationService,
    FirebaseMessaging? messaging,
  })  : _repository = repository,
        _localNotificationService = localNotificationService,
        _messaging = messaging;

  FirebaseMessaging get _effectiveMessaging {
    final m = _messaging;
    if (m != null) return m;
    return FirebaseMessaging.instance;
  }

  @override
  bool get isInitialized => _isInitialized;

  @override
  String? get currentToken => _currentToken;

  @override
  Stream<RemoteMessage> get onMessage => _messageController.stream;

  @override
  Stream<String> get onTokenRefresh => _tokenRefreshController.stream;

  @override
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      if (Firebase.apps.isEmpty) {
        debugPrint('[FCM] Firebase not initialized, skipping FCM setup');
        return false;
      }

      // Configure background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Listen for incoming foreground messages and display heads-up banner
      _messageSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _messageController.add(message);
        unawaited(handleFcmBackgroundMessage(
          message,
          localNotificationService: _localNotificationService,
        ).catchError((e) {
          debugPrint('[FCM] Error displaying foreground notification: $e');
        }));
      });

      // Listen for incoming background message opened app events
      _openedAppSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _messageController.add(message);
        unawaited(handleFcmBackgroundMessage(
          message,
          localNotificationService: _localNotificationService,
        ).catchError((e) {
          debugPrint('[FCM] Error handling onMessageOpenedApp: $e');
        }));
      });

      // Listen for token refresh and automatically sync to RTDB
      _tokenRefreshSubscription = _effectiveMessaging.onTokenRefresh.listen((String newToken) {
        _tokenRefreshController.add(newToken);
        final oldToken = _currentToken;
        _currentToken = newToken;

        final uId = _registeredUserId;
        if (uId != null && _registeredStoreIds.isNotEmpty) {
          for (final sId in _registeredStoreIds) {
            if (oldToken != null && oldToken != newToken) {
              unawaited(_repository.deleteToken(
                storeId: sId,
                userId: uId,
                token: oldToken,
              ).catchError((e) {
                debugPrint('[FCM] deleteToken on refresh error: $e');
              }));
            }
            unawaited(_repository.saveToken(
              storeId: sId,
              userId: uId,
              token: newToken,
            ).catchError((e) {
              debugPrint('[FCM] saveToken on refresh error: $e');
            }));
          }
        }
      });

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('[FCM] Initialize skipped or failed: $e');
      return false;
    }
  }

  @override
  Future<bool?> requestPermissions() async {
    try {
      if (Firebase.apps.isEmpty) return false;
      final settings = await _effectiveMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('[FCM] requestPermissions failed: $e');
      return false;
    }
  }

  @override
  Future<String?> getToken() async {
    try {
      if (Firebase.apps.isEmpty) return null;
      _currentToken = await _effectiveMessaging.getToken();
      return _currentToken;
    } catch (e) {
      debugPrint('[FCM] getToken failed: $e');
      return null;
    }
  }

  static List<String> _resolveTargetStores(String storeId) {
    final trimmed = storeId.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed == 'all') {
      return const ['store_001', 'store_002'];
    }
    return [trimmed];
  }

  @override
  Future<void> registerAdminToken({
    required String storeId,
    required String userId,
  }) async {
    try {
      final uId = userId.trim();
      if (uId.isEmpty) return;

      final targetStores = _resolveTargetStores(storeId);
      if (targetStores.isEmpty) return;

      final token = await getToken();
      if (token == null || token.trim().isEmpty) return;
      final cleanToken = token.trim();

      for (final sId in targetStores) {
        _registeredStoreIds.add(sId);
        await _repository.saveToken(
          storeId: sId,
          userId: uId,
          token: cleanToken,
        );
      }
      _registeredUserId = uId;
    } catch (e) {
      debugPrint('[FCM] registerAdminToken failed: $e');
    }
  }

  @override
  Future<void> unregisterAdminToken({
    required String storeId,
    required String userId,
  }) async {
    try {
      final uId = userId.trim();
      final targetStores = _resolveTargetStores(storeId);
      if (targetStores.isEmpty) return;

      final token = _currentToken ?? await getToken();
      for (final sId in targetStores) {
        if (token != null && token.trim().isNotEmpty) {
          await _repository.deleteToken(
            storeId: sId,
            userId: uId,
            token: token.trim(),
          );
        }
        _registeredStoreIds.remove(sId);
      }
      if (_registeredStoreIds.isEmpty) {
        _registeredUserId = null;
      }
    } catch (e) {
      debugPrint('[FCM] unregisterAdminToken failed: $e');
    }
  }

  @override
  Future<void> syncPushNotification({
    required String storeId,
    required NotificationItem notification,
  }) async {
    try {
      final targetStores = _resolveTargetStores(storeId);
      if (targetStores.isEmpty) return;

      final Set<String> adminTokens = {};
      for (final sId in targetStores) {
        final tokens = await _repository.getAdminTokens(storeId: sId);
        adminTokens.addAll(tokens);
      }

      if (adminTokens.isNotEmpty) {
        final queueStore = targetStores.first;
        await _repository.queuePushNotification(
          storeId: queueStore,
          notification: notification,
          targetTokens: adminTokens.toList(),
        );
      }
    } catch (e) {
      debugPrint('[FCM] syncPushNotification failed: $e');
    }
  }

  void dispose() {
    _messageSubscription?.cancel();
    _openedAppSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
    _messageController.close();
    _tokenRefreshController.close();
  }
}

/// Recorded registration operation for [FakePushNotificationService].
class FakeTokenOp {
  final String storeId;
  final String userId;
  final String token;

  const FakeTokenOp({
    required this.storeId,
    required this.userId,
    required this.token,
  });
}

/// In-memory fake implementation of [PushNotificationService] for unit and widget tests.
/// Completely avoids Firebase platform channels and mock complexities.
class FakePushNotificationService implements PushNotificationService {
  @override
  bool isInitialized = false;

  @override
  String? currentToken = 'fake_fcm_token_admin_device_123';

  bool permissionsRequested = false;
  bool? permissionResult = true;

  final List<FakeTokenOp> registeredOps = [];
  final List<FakeTokenOp> unregisteredOps = [];
  final List<NotificationItem> syncedNotifications = [];

  final StreamController<RemoteMessage> _messageController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<String> _tokenRefreshController =
      StreamController<String>.broadcast();

  @override
  Stream<RemoteMessage> get onMessage => _messageController.stream;

  @override
  Stream<String> get onTokenRefresh => _tokenRefreshController.stream;

  @override
  Future<bool> initialize() async {
    isInitialized = true;
    return true;
  }

  @override
  Future<bool?> requestPermissions() async {
    permissionsRequested = true;
    return permissionResult;
  }

  @override
  Future<String?> getToken() async => currentToken;

  @override
  Future<void> registerAdminToken({
    required String storeId,
    required String userId,
  }) async {
    if (currentToken != null) {
      final targets = storeId.trim() == 'all'
          ? const ['store_001', 'store_002']
          : [storeId.trim()];
      for (final s in targets) {
        if (s.isEmpty) continue;
        registeredOps.add(FakeTokenOp(
          storeId: s,
          userId: userId,
          token: currentToken!,
        ));
      }
    }
  }

  @override
  Future<void> unregisterAdminToken({
    required String storeId,
    required String userId,
  }) async {
    if (currentToken != null) {
      final targets = storeId.trim() == 'all'
          ? const ['store_001', 'store_002']
          : [storeId.trim()];
      for (final s in targets) {
        if (s.isEmpty) continue;
        unregisteredOps.add(FakeTokenOp(
          storeId: s,
          userId: userId,
          token: currentToken!,
        ));
      }
    }
  }

  @override
  Future<void> syncPushNotification({
    required String storeId,
    required NotificationItem notification,
  }) async {
    syncedNotifications.add(notification);
  }

  /// Helper to simulate incoming remote message in tests.
  void simulateIncomingMessage(RemoteMessage message) {
    _messageController.add(message);
  }

  /// Helper to simulate token refresh event in tests.
  void simulateTokenRefresh(String newToken) {
    currentToken = newToken;
    _tokenRefreshController.add(newToken);
  }

  void clear() {
    registeredOps.clear();
    unregisteredOps.clear();
    syncedNotifications.clear();
    permissionsRequested = false;
  }
}
