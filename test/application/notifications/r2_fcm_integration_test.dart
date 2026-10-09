import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/notifications/local_notification_service.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/data/repositories/fcm_token_repository_impl.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/user_account.dart';

class _MockFcmTokenRepository implements FcmTokenRepository {
  final Map<String, Map<String, Map<String, dynamic>>> db = {};
  final List<Map<String, dynamic>> queuedDispatches = [];

  @override
  Future<void> saveToken({
    required String storeId,
    required String userId,
    required String token,
    Map<String, dynamic>? deviceInfo,
  }) async {
    final sanitizedToken = FcmRemoteDataSource.sanitizeTokenKey(token);
    db.putIfAbsent(storeId, () => {});
    db[storeId]!.putIfAbsent(userId, () => {});
    db[storeId]![userId]![sanitizedToken] = {
      'token': token,
      'userId': userId,
      'storeId': storeId,
      'updatedAt': DateTime.now().toIso8601String(),
      if (deviceInfo != null) ...deviceInfo,
    };
  }

  @override
  Future<void> deleteToken({
    required String storeId,
    required String userId,
    required String token,
  }) async {
    final sanitizedToken = FcmRemoteDataSource.sanitizeTokenKey(token);
    db[storeId]?[userId]?.remove(sanitizedToken);
  }

  @override
  Future<void> clearUserTokens({
    required String storeId,
    required String userId,
  }) async {
    db[storeId]?.remove(userId);
  }

  @override
  Future<List<String>> getAdminTokens({required String storeId}) async {
    final storeMap = db[storeId];
    if (storeMap == null) return [];
    final List<String> result = [];
    for (final userMap in storeMap.values) {
      for (final entry in userMap.values) {
        if (entry is Map && entry['token'] != null) {
          result.add(entry['token'].toString());
        }
      }
    }
    return result;
  }

  @override
  Future<void> queuePushNotification({
    required String storeId,
    required NotificationItem notification,
    required List<String> targetTokens,
  }) async {
    queuedDispatches.add({
      'storeId': storeId,
      'notificationId': notification.id,
      'title': notification.title,
      'body': notification.body,
      'targetTokens': targetTokens,
    });
  }
}

class _SpyFcmRemoteDataSource extends FcmRemoteDataSource {
  final List<Map<String, dynamic>> queuedCalls = [];
  final Map<String, List<String>> storeAdminTokens = {};

  @override
  Future<List<String>> getAdminTokens({required String storeId}) async {
    return storeAdminTokens[storeId] ?? [];
  }

  @override
  Future<void> queuePushNotification({
    required String storeId,
    required Map<String, dynamic> payload,
  }) async {
    queuedCalls.add({
      'storeId': storeId,
      'payload': payload,
    });
  }
}

class _MockNotificationRepository implements NotificationRepository {
  final List<NotificationItem> added = [];

  @override
  Future<void> addNotification(NotificationItem notification) async {
    added.add(notification);
  }

  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {}

  @override
  Future<void> markAllAsRead(String storeId) async {}

  @override
  Future<void> markAsRead(
      {required String storeId, required String id}) async {}

  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
      {int limit = 50}) {
    return Stream.value(added);
  }
}

class _TestAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _TestAuthNotifier([super.initial]);

  void setUser(UserAccount? u) => state = u;

  @override
  Future<void> logout() async {
    state = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storeId = 'store_branch_main';
  const adminUser = UserAccount(
    username: 'owner_duc',
    displayName: 'Chủ shop Đức',
    role: 'admin',
    storeId: storeId,
  );
  const staffUser = UserAccount(
    username: 'staff_binh',
    displayName: 'Nhân viên Bình',
    role: 'nhanvien',
    storeId: storeId,
  );

  group('R2.1: Background Handler — RemoteMessage Parsing & Local Notification', () {
    late FakeLocalNotificationService fakeLocalService;

    setUp(() {
      fakeLocalService = FakeLocalNotificationService();
    });

    test('1. Parses data payload and triggers local notification banner', () async {
      const message = RemoteMessage(
        messageId: 'msg_fcm_001',
        data: {
          'id': 'NOTIF_ORD_1001',
          'storeId': storeId,
          'title': 'Đơn hàng mới #HD01',
          'body': 'Đơn hàng mới #HD01: 250.000đ cho khách Nguyễn Văn A (Tạo bởi: Thu ngân Lan)',
          'type': 'orderCreated',
          'targetRoute': 'invoice_detail',
          'targetId': 'HD01',
        },
      );

      await handleFcmBackgroundMessage(
        message,
        localNotificationService: fakeLocalService,
      );

      expect(fakeLocalService.displayedCalls.length, equals(1));
      final call = fakeLocalService.displayedCalls.first;
      expect(call.title, equals('Đơn hàng mới #HD01'));
      expect(call.body, contains('250.000đ cho khách Nguyễn Văn A (Tạo bởi: Thu ngân Lan)'));
      expect(call.id, isPositive);

      final payload = NotificationPayload.tryParse(call.payload);
      expect(payload, isNotNull);
      expect(payload!.id, equals('NOTIF_ORD_1001'));
      expect(payload.storeId, equals(storeId));
      expect(payload.type, equals('orderCreated'));
      expect(payload.targetRoute, equals('invoice_detail'));
      expect(payload.targetId, equals('HD01'));
    });

    test('1b. Prefers notificationId over queue id to preserve business ID', () async {
      const message = RemoteMessage(
        messageId: 'msg_fcm_001b',
        data: {
          'id': '-O_push_queue_uuid_999',
          'notificationId': 'NOTIF_ORD_REAL_ID',
          'storeId': storeId,
          'title': 'Đơn hàng mới',
          'body': 'Đơn hàng mới #HD99',
        },
      );

      await handleFcmBackgroundMessage(
        message,
        localNotificationService: fakeLocalService,
      );

      expect(fakeLocalService.displayedCalls.length, equals(1));
      final call = fakeLocalService.displayedCalls.first;
      final payload = NotificationPayload.tryParse(call.payload);
      expect(payload, isNotNull);
      expect(payload!.id, equals('NOTIF_ORD_REAL_ID'));
    });

    test('2. Parses RemoteMessage.notification when data title and body are omitted', () async {
      const message = RemoteMessage(
        messageId: 'msg_fcm_002',
        notification: RemoteNotification(
          title: 'Khách hàng mới: Trần Văn C',
          body: 'Khách hàng: Trần Văn C • SĐT: 0901234567 (Tạo bởi: Quản lý Quân)',
        ),
        data: {
          'storeId': storeId,
          'targetRoute': 'customer_detail',
        },
      );

      await handleFcmBackgroundMessage(
        message,
        localNotificationService: fakeLocalService,
      );

      expect(fakeLocalService.displayedCalls.length, equals(1));
      final call = fakeLocalService.displayedCalls.first;
      expect(call.title, equals('Khách hàng mới: Trần Văn C'));
      expect(call.body, contains('Trần Văn C • SĐT: 0901234567'));
    });

    test('3. Safely ignores empty messages without throwing or crashing', () async {
      const emptyMessage = RemoteMessage(
        messageId: 'empty_msg',
        data: {},
      );

      await expectLater(
        handleFcmBackgroundMessage(
          emptyMessage,
          localNotificationService: fakeLocalService,
        ),
        completes,
      );

      expect(fakeLocalService.displayedCalls, isEmpty);
    });

    test('4. Robust against malformed data types and null fields', () async {
      const malformedMessage = RemoteMessage(
        messageId: null,
        data: {
          'title': null,
          'body': 'Phiếu trả #TH01 hoàn tiền: 50.000đ (Xử lý bởi: Thu ngân Lan)',
          'id': 12345, // int instead of string
          'storeId': null,
        },
      );

      await handleFcmBackgroundMessage(
        malformedMessage,
        localNotificationService: fakeLocalService,
      );

      expect(fakeLocalService.displayedCalls.length, equals(1));
      final call = fakeLocalService.displayedCalls.first;
      expect(call.title, equals('Thông báo cửa hàng')); // Default fallback title
      expect(call.body, contains('Phiếu trả #TH01'));
    });

    test('5. handleFcmBackgroundMessage displays heads-up banner when app is in terminated state', () async {
      // Simulates high-priority push delivered to terminated app by Google Play Services
      const terminatedMessage = RemoteMessage(
        messageId: 'terminated_msg_001',
        data: {
          'id': 'NOTIF_TERMINATED_ORD',
          'notificationId': 'NOTIF_TERMINATED_ORD',
          'storeId': storeId,
          'title': 'Đơn hàng mới #HD888',
          'body': '880.000đ - Khách: Nguyễn Văn A (Tạo bởi: Thu ngân Lan)',
          'priority': 'high',
          'channel_id': 'store_notifications_channel',
          'type': 'orderCreated',
          'targetRoute': 'invoice_detail',
          'targetId': 'HD888',
        },
      );

      await handleFcmBackgroundMessage(
        terminatedMessage,
        localNotificationService: fakeLocalService,
      );

      expect(fakeLocalService.displayedCalls.length, equals(1));
      final call = fakeLocalService.displayedCalls.first;
      expect(call.title, equals('Đơn hàng mới #HD888'));
      expect(call.body, equals('880.000đ - Khách: Nguyễn Văn A (Tạo bởi: Thu ngân Lan)'));
      expect(call.body.contains('HD888'), isFalse);
      expect(call.id, isPositive);

      final payload = NotificationPayload.tryParse(call.payload);
      expect(payload, isNotNull);
      expect(payload!.id, equals('NOTIF_TERMINATED_ORD'));
      expect(payload.storeId, equals(storeId));
      expect(payload.targetRoute, equals('invoice_detail'));
      expect(payload.targetId, equals('HD888'));
    });
  });

  group('R2.2: FCM Token Management — Database Persistence & Logout Cleanup', () {
    late _MockFcmTokenRepository mockTokenRepo;

    setUp(() {
      mockTokenRepo = _MockFcmTokenRepository();
    });

    test('1. Saves Admin device token with sanitized RTDB key', () async {
      const rawToken = 'fcm_token_admin.part1#part2/part3\$key[0]';
      await mockTokenRepo.saveToken(
        storeId: storeId,
        userId: adminUser.username,
        token: rawToken,
        deviceInfo: {'model': 'Pixel 8', 'os': 'Android 14'},
      );

      final tokens = await mockTokenRepo.getAdminTokens(storeId: storeId);
      expect(tokens.length, equals(1));
      expect(tokens.first, equals(rawToken));

      // Key must not contain illegal characters: . # $ [ ] /
      final sanitizedKey = FcmRemoteDataSource.sanitizeTokenKey(rawToken);
      expect(sanitizedKey.contains('.'), isFalse);
      expect(sanitizedKey.contains('#'), isFalse);
      expect(sanitizedKey.contains('\$'), isFalse);
      expect(sanitizedKey.contains('['), isFalse);
      expect(sanitizedKey.contains(']'), isFalse);
      expect(sanitizedKey.contains('/'), isFalse);
      expect(mockTokenRepo.db[storeId]?[adminUser.username]?[sanitizedKey], isNotNull);
    });

    test('2. Deletes device token on logout', () async {
      const token = 'fcm_admin_token_xyz_999';
      await mockTokenRepo.saveToken(
        storeId: storeId,
        userId: adminUser.username,
        token: token,
      );

      var tokens = await mockTokenRepo.getAdminTokens(storeId: storeId);
      expect(tokens, contains(token));

      // User logs out -> delete token
      await mockTokenRepo.deleteToken(
        storeId: storeId,
        userId: adminUser.username,
        token: token,
      );

      tokens = await mockTokenRepo.getAdminTokens(storeId: storeId);
      expect(tokens, isEmpty);
    });

    test('3. clearUserTokens removes all tokens for that user', () async {
      await mockTokenRepo.saveToken(
        storeId: storeId,
        userId: adminUser.username,
        token: 'token_phone_1',
      );
      await mockTokenRepo.saveToken(
        storeId: storeId,
        userId: adminUser.username,
        token: 'token_tablet_2',
      );

      var tokens = await mockTokenRepo.getAdminTokens(storeId: storeId);
      expect(tokens.length, equals(2));

      await mockTokenRepo.clearUserTokens(
        storeId: storeId,
        userId: adminUser.username,
      );

      tokens = await mockTokenRepo.getAdminTokens(storeId: storeId);
      expect(tokens, isEmpty);
    });

    test('4. sanitizeTokenKey removes control characters and illegal symbols safely', () {
      const evilToken = 'abc\x00def\x1Fghi\x7Fjkl.mno#pqr\$stu[vwx]yz/123';
      final sanitized = FcmRemoteDataSource.sanitizeTokenKey(evilToken);
      expect(sanitized.contains('\x00'), isFalse);
      expect(sanitized.contains('\x1F'), isFalse);
      expect(sanitized.contains('\x7F'), isFalse);
      expect(sanitized.contains('.'), isFalse);
      expect(sanitized.contains('#'), isFalse);
      expect(sanitized.contains('\$'), isFalse);
      expect(sanitized.contains('['), isFalse);
      expect(sanitized.contains(']'), isFalse);
      expect(sanitized.contains('/'), isFalse);
    });

    test('5. queuePushNotification maps notificationId, storeId, and targetTokens into payload', () async {
      final notif = NotificationItem(
        id: 'NOTIF_ORD_PAYLOAD_TEST',
        storeId: storeId,
        title: 'Đơn hàng mới',
        body: 'Nội dung thông báo',
        type: NotificationType.orderCreated,
        createdAt: DateTime.now(),
        targetRoute: 'invoice_detail',
        targetId: 'HD99',
      );

      await mockTokenRepo.queuePushNotification(
        storeId: storeId,
        notification: notif,
        targetTokens: ['token_alpha', 'token_beta'],
      );

      expect(mockTokenRepo.queuedDispatches.length, equals(1));
      final queued = mockTokenRepo.queuedDispatches.first;
      expect(queued['storeId'], equals(storeId));
      expect(queued['notificationId'], equals('NOTIF_ORD_PAYLOAD_TEST'));
      expect(queued['targetTokens'], contains('token_alpha'));
      expect(queued['targetTokens'], contains('token_beta'));
    });

    test('6. FcmTokenRepositoryImpl dispatches high-priority push payload with channel and sound', () async {
      final spyRemote = _SpyFcmRemoteDataSource();
      final realRepo = FcmTokenRepositoryImpl(spyRemote);

      final notif = NotificationItem(
        id: 'NOTIF_HIGH_PRIORITY_TEST',
        storeId: storeId,
        title: 'Đơn hàng mới #HD100',
        body: '500.000đ - Khách: Nguyễn Văn A (Tạo bởi: Thu ngân Lan)',
        type: NotificationType.orderCreated,
        createdAt: DateTime.now(),
        targetRoute: 'invoice_detail',
        targetId: 'HD100',
        metadata: {'orderId': 'HD100', 'total': 500000.0},
      );

      await realRepo.queuePushNotification(
        storeId: storeId,
        notification: notif,
        targetTokens: ['fcm_admin_token_1', 'fcm_admin_token_2'],
      );

      expect(spyRemote.queuedCalls.length, equals(1));
      final queued = spyRemote.queuedCalls.first;
      expect(queued['storeId'], equals(storeId));
      final payload = queued['payload'] as Map<String, dynamic>;

      // Root level high-priority flags
      expect(payload['priority'], equals('high'));
      expect(payload['channel_id'], equals('store_notifications_channel'));
      expect(payload['channelId'], equals('store_notifications_channel'));
      expect(payload['sound'], equals('default'));
      expect(payload['vibrate'], isTrue);

      // Android platform config for waking device & heads-up banner
      final android = payload['android'] as Map<String, dynamic>;
      expect(android['priority'], equals('high'));
      final androidNotif = android['notification'] as Map<String, dynamic>;
      expect(androidNotif['channel_id'], equals('store_notifications_channel'));
      expect(androidNotif['sound'], equals('default'));
      expect(androidNotif['default_sound'], isTrue);
      expect(androidNotif['default_vibrate_timings'], isTrue);

      // Data map for background/terminated handler
      final data = payload['data'] as Map<String, dynamic>;
      expect(data['priority'], equals('high'));
      expect(data['channel_id'], equals('store_notifications_channel'));
      expect(data['sound'], equals('default'));
      expect(data['notificationId'], equals('NOTIF_HIGH_PRIORITY_TEST'));

      // Target tokens
      final tokens = payload['targetTokens'] as List<String>;
      expect(tokens, contains('fcm_admin_token_1'));
      expect(tokens, contains('fcm_admin_token_2'));
    });

    test('7. FirebasePushNotificationServiceImpl fetches admin tokens and dispatches push payload', () async {
      final spyRemote = _SpyFcmRemoteDataSource();
      spyRemote.storeAdminTokens[storeId] = ['admin_token_alpha', 'admin_token_beta'];
      final realRepo = FcmTokenRepositoryImpl(spyRemote);
      final fakeLocal = FakeLocalNotificationService();

      final pushService = FirebasePushNotificationServiceImpl(
        repository: realRepo,
        localNotificationService: fakeLocal,
      );

      final notif = NotificationItem(
        id: 'NOTIF_SYNC_PUSH_TEST',
        storeId: storeId,
        title: 'Đơn hàng mới #HD101',
        body: '350.000đ - Khách: Khách lẻ (Tạo bởi: Thu ngân Lan)',
        type: NotificationType.orderCreated,
        createdAt: DateTime.now(),
        targetRoute: 'invoice_detail',
        targetId: 'HD101',
      );

      await pushService.syncPushNotification(
        storeId: storeId,
        notification: notif,
      );

      expect(spyRemote.queuedCalls.length, equals(1));
      final queued = spyRemote.queuedCalls.first;
      expect(queued['storeId'], equals(storeId));
      final payload = queued['payload'] as Map<String, dynamic>;
      expect(payload['priority'], equals('high'));
      expect(payload['channel_id'], equals('store_notifications_channel'));
      final tokens = payload['targetTokens'] as List<String>;
      expect(tokens, contains('admin_token_alpha'));
      expect(tokens, contains('admin_token_beta'));
    });

    test('8. FirebasePushNotificationServiceImpl skips dispatch when store has no admin tokens', () async {
      final spyRemote = _SpyFcmRemoteDataSource();
      spyRemote.storeAdminTokens[storeId] = [];
      final realRepo = FcmTokenRepositoryImpl(spyRemote);
      final fakeLocal = FakeLocalNotificationService();

      final pushService = FirebasePushNotificationServiceImpl(
        repository: realRepo,
        localNotificationService: fakeLocal,
      );

      final notif = NotificationItem(
        id: 'NOTIF_NO_ADMIN_TEST',
        storeId: storeId,
        title: 'Đơn hàng mới #HD102',
        body: '120.000đ - Khách: Khách lẻ (Tạo bởi: Thu ngân Lan)',
        type: NotificationType.orderCreated,
        createdAt: DateTime.now(),
      );

      await pushService.syncPushNotification(
        storeId: storeId,
        notification: notif,
      );

      expect(spyRemote.queuedCalls, isEmpty);
    });
  });

  group('R2.3: Riverpod Lifecycle & Push Trigger Coordination', () {
    late _MockNotificationRepository mockNotifRepo;
    late FakePushNotificationService fakePushService;

    setUp(() {
      mockNotifRepo = _MockNotificationRepository();
      fakePushService = FakePushNotificationService();
    });

    test('1. NotificationDispatcher triggers push sync to Admin devices', () async {
      final dispatcher = NotificationDispatcher(mockNotifRepo, fakePushService);

      final order = Order(
        id: 'HD_SYNC_01',
        customerId: 'KH001',
        customerName: 'Trần Văn X',
        createdAt: DateTime.now(),
        items: const [],
        total: 500000.0,
      );

      await dispatcher.notifyOrderCreated(
        storeId: storeId,
        order: order,
        user: staffUser,
      );

      expect(mockNotifRepo.added.length, equals(1));
      expect(fakePushService.syncedNotifications.length, equals(1));
      final synced = fakePushService.syncedNotifications.first;
      expect(synced.id, equals(mockNotifRepo.added.first.id));
      expect(synced.body, equals('500.000đ - Khách: Trần Văn X (Tạo bởi: Nhân viên Bình)'));
      expect(synced.body.contains('HD_SYNC_01'), isFalse);
    });

    test('2. fcmTokenLifecycleManager registers token on Admin login and unregisters on logout', () async {
      final testAuthNotifier = _TestAuthNotifier();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => testAuthNotifier),
          pushNotificationServiceProvider.overrideWithValue(fakePushService),
          currentStoreIdProvider.overrideWith((ref) => storeId),
        ],
      );
      addTearDown(container.dispose);

      // Start listening to token lifecycle
      container.read(fcmTokenLifecycleManagerProvider);

      // 1. Staff login -> should NOT register admin token
      testAuthNotifier.setUser(staffUser);
      expect(fakePushService.registeredOps, isEmpty);

      // 2. Admin login -> registers admin token
      testAuthNotifier.setUser(adminUser);
      expect(fakePushService.registeredOps.length, equals(1));
      expect(fakePushService.registeredOps.first.userId, equals(adminUser.username));
      expect(fakePushService.registeredOps.first.storeId, equals(storeId));

      // 3. Admin logout -> unregisters admin token
      await testAuthNotifier.logout();
      expect(fakePushService.unregisteredOps.length, equals(1));
      expect(fakePushService.unregisteredOps.first.userId, equals(adminUser.username));
      expect(fakePushService.unregisteredOps.first.storeId, equals(storeId));
    });

    test('3. fcmTokenLifecycleManager registers token immediately on startup if Admin is already cached (instant session)', () async {
      // Container boots up with admin already authenticated
      final testAuthNotifier = _TestAuthNotifier(adminUser);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => testAuthNotifier),
          pushNotificationServiceProvider.overrideWithValue(fakePushService),
          currentStoreIdProvider.overrideWith((ref) => storeId),
        ],
      );
      addTearDown(container.dispose);

      // Reading provider fires immediately without waiting for an auth transition
      container.read(fcmTokenLifecycleManagerProvider);

      expect(fakePushService.registeredOps.length, equals(1));
      expect(fakePushService.registeredOps.first.userId, equals(adminUser.username));
      expect(fakePushService.registeredOps.first.storeId, equals(storeId));
    });

    test('4. fcmTokenLifecycleManager registers token for new store when Admin switches branch', () async {
      const switchingAdmin = UserAccount(
        username: 'switching_admin',
        displayName: 'Quản trị viên',
        role: 'admin',
        storeId: 'all',
      );
      final testAuthNotifier = _TestAuthNotifier(switchingAdmin);
      final storeBranchProvider = StateProvider<String>((ref) => 'store_001');
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => testAuthNotifier),
          pushNotificationServiceProvider.overrideWithValue(fakePushService),
          currentStoreIdProvider.overrideWith((ref) => ref.watch(storeBranchProvider)),
        ],
      );
      addTearDown(container.dispose);

      container.read(fcmTokenLifecycleManagerProvider);
      expect(fakePushService.registeredOps.length, equals(1));
      expect(fakePushService.registeredOps.last.storeId, equals('store_001'));

      // Switch branch to store_002
      container.read(storeBranchProvider.notifier).state = 'store_002';
      await Future<void>.delayed(Duration.zero);

      // Should have registered for the switched branch
      expect(fakePushService.registeredOps.any((op) => op.storeId == 'store_002'), isTrue);
    });

    test('5. fcmTokenLifecycleManager avoids "all" as storeId and resolves to valid store', () async {
      const chainAdmin = UserAccount(
        username: 'chain_boss',
        displayName: 'Chủ chuỗi',
        role: 'admin',
        storeId: 'all', // Chain-wide admin
      );

      final testAuthNotifier = _TestAuthNotifier();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => testAuthNotifier),
          pushNotificationServiceProvider.overrideWithValue(fakePushService),
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
        ],
      );
      addTearDown(container.dispose);

      container.read(fcmTokenLifecycleManagerProvider);

      testAuthNotifier.setUser(chainAdmin);

      expect(fakePushService.registeredOps.length, equals(1));
      // Must not register under 'all'
      expect(fakePushService.registeredOps.first.storeId, isNot(equals('all')));
      expect(fakePushService.registeredOps.first.storeId, equals('store_001'));
    });
  });
}
