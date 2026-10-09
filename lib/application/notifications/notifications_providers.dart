import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firebase/fcm_remote_data_source.dart';
import '../../data/datasources/firebase/notification_remote_data_source.dart';
import '../../data/repositories/fcm_token_repository_impl.dart';
import '../../data/repositories/notification_repository_impl.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/entities/notification_type.dart';
import '../../domain/repositories/fcm_token_repository.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/entities/user_account.dart';
import '../auth/auth_providers.dart';
import 'fcm_service.dart';
import 'local_notification_service.dart';

export '../../data/datasources/firebase/fcm_remote_data_source.dart';
export '../../data/datasources/firebase/notification_remote_data_source.dart';
export '../../domain/entities/notification_item.dart';
export '../../domain/entities/notification_type.dart';
export '../../domain/repositories/fcm_token_repository.dart';
export '../../domain/repositories/notification_repository.dart';
export 'fcm_service.dart';

/// Auto-disposed provider for [NotificationRemoteDataSource].
/// Gracefully falls back to default constructor if Firebase is uninitialized.
final notificationRemoteDataSourceProvider =
    Provider.autoDispose<NotificationRemoteDataSource>((ref) {
  try {
    return NotificationRemoteDataSource(FirebaseDatabase.instance);
  } catch (_) {
    return NotificationRemoteDataSource();
  }
});

/// Auto-disposed provider for [NotificationRepository] implementation.
final notificationRepositoryProvider =
    Provider.autoDispose<NotificationRepository>((ref) {
  final remoteDataSource = ref.watch(notificationRemoteDataSourceProvider);
  return NotificationRepositoryImpl(remoteDataSource);
});

/// Auto-disposed provider for [FcmRemoteDataSource].
final fcmRemoteDataSourceProvider =
    Provider.autoDispose<FcmRemoteDataSource>((ref) {
  try {
    return FcmRemoteDataSource(FirebaseDatabase.instance);
  } catch (_) {
    return FcmRemoteDataSource();
  }
});

/// Auto-disposed provider for [FcmTokenRepository] implementation.
final fcmTokenRepositoryProvider =
    Provider.autoDispose<FcmTokenRepository>((ref) {
  final remoteDataSource = ref.watch(fcmRemoteDataSourceProvider);
  return FcmTokenRepositoryImpl(remoteDataSource);
});

/// Provider supplying the [PushNotificationService] instance.
/// Overridable in tests via `overrideWithValue(FakePushNotificationService())`.
final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  try {
    final repository = ref.watch(fcmTokenRepositoryProvider);
    final localService = ref.watch(localNotificationServiceProvider);
    final service = FirebasePushNotificationServiceImpl(
      repository: repository,
      localNotificationService: localService,
    );
    unawaited(service.initialize());
    return service;
  } catch (_) {
    return FakePushNotificationService();
  }
});

/// Auto-disposing sync provider that manages FCM token registration for Admin/Owner.
final fcmTokenSyncProvider = Provider.autoDispose<void>((ref) {
  final user = ref.watch(authProvider);
  final storeId = ref.watch(currentStoreIdProvider);
  final pushService = ref.watch(pushNotificationServiceProvider);

  if (user != null && user.isAdmin && storeId.trim().isNotEmpty) {
    unawaited(pushService.registerAdminToken(
      storeId: storeId,
      userId: user.username,
    ));
  }
});

/// Manages FCM token registration on login/startup, branch switches, and cleanup on logout.
final fcmTokenLifecycleManagerProvider = Provider<void>((ref) {
  final Set<String> registeredStoresForSession = {};

  ref.listen<UserAccount?>(authProvider, (previous, next) {
    final pushService = ref.read(pushNotificationServiceProvider);
    final currentStore = ref.read(currentStoreIdProvider);

    // If an admin user logged out or switched, clean up token
    if (previous != null &&
        previous.isAdmin &&
        (next == null || next.username != previous.username)) {
      final prevStoreId =
          (previous.storeId.isNotEmpty && previous.storeId != 'all')
              ? previous.storeId
              : currentStore;
      final Set<String> storesToClean = {
        ...registeredStoresForSession,
        if (prevStoreId.isNotEmpty && prevStoreId != 'all') prevStoreId,
        if (currentStore.isNotEmpty && currentStore != 'all') currentStore,
      };
      for (final sId in storesToClean) {
        unawaited(pushService.unregisterAdminToken(
          storeId: sId,
          userId: previous.username,
        ).catchError((e) {
          debugPrint('[FCM] unregisterAdminToken error: $e');
        }));
      }
      registeredStoresForSession.clear();
    }

    // If an admin user logged in or switched
    if (next != null && next.isAdmin) {
      final nextStoreId =
          (next.storeId.isNotEmpty && next.storeId != 'all')
              ? next.storeId
              : currentStore;
      final targetStores = (nextStoreId == 'all')
          ? const ['store_001', 'store_002']
          : [nextStoreId.isNotEmpty ? nextStoreId : 'store_001'];
      for (final sId in targetStores) {
        registeredStoresForSession.add(sId);
        unawaited(pushService.registerAdminToken(
          storeId: sId,
          userId: next.username,
        ).catchError((e) {
          debugPrint('[FCM] registerAdminToken error: $e');
        }));
      }
    }
  }, fireImmediately: true);

  // Monitor store branch switching for logged-in Admin
  ref.listen<String>(currentStoreIdProvider, (previous, next) {
    final user = ref.read(authProvider);
    if (user != null &&
        user.isAdmin &&
        next.isNotEmpty &&
        next != previous) {
      final targetBranches = (next == 'all')
          ? const ['store_001', 'store_002']
          : [next];
      final pushService = ref.read(pushNotificationServiceProvider);
      for (final b in targetBranches) {
        registeredStoresForSession.add(b);
        unawaited(pushService.registerAdminToken(
          storeId: b,
          userId: user.username,
        ).catchError((e) {
          debugPrint('[FCM] registerAdminToken on branch switch error: $e');
        }));
      }
    }
  });
});

/// Auto-disposed stream provider emitting real-time notifications for the active store.
///
/// CRITICAL RBAC & BANDWIDTH GUARD:
/// Only Admin and Owner accounts (`user?.isAdmin == true`) are permitted to listen to the
/// real-time notifications stream. For staff accounts (`nhanvien` / `supervisor` without admin)
/// or unauthenticated sessions (`user == null`), this immediately returns `Stream.value(<NotificationItem>[])`
/// without invoking `watchNotifications` on the repository or opening any Firebase stream listener.
/// This completely eliminates unauthorized access and protects the Firebase RTDB 10GB/month egress quota.
final notificationStreamProvider =
    StreamProvider.autoDispose<List<NotificationItem>>((ref) {
  final user = ref.watch(authProvider);
  final storeId = ref.watch(currentStoreIdProvider);

  // RBAC Guard: non-admins and logged-out users receive an empty stream with 0 Firebase queries.
  if (user == null || !user.isAdmin) {
    return Stream.value(<NotificationItem>[]);
  }

  // Safety guard: empty store ID returns empty stream without network listener
  if (storeId.trim().isEmpty) {
    return Stream.value(<NotificationItem>[]);
  }

  final repository = ref.watch(notificationRepositoryProvider);
  return repository.watchNotifications(storeId, limit: 50);
});

/// Auto-disposed provider calculating unread notification count.
/// Derived reactively from [notificationStreamProvider].
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notificationsAsync = ref.watch(notificationStreamProvider);
  return notificationsAsync.valueOrNull
          ?.where((item) => !item.isRead)
          .length ??
      0;
});

/// Auto-disposed state provider storing the active [NotificationCategory] filter.
/// Set to `null` to view all notifications.
final notificationCategoryFilterProvider =
    StateProvider.autoDispose<NotificationCategory?>((ref) => null);

/// Auto-disposed provider returning notifications filtered by the active [notificationCategoryFilterProvider].
final filteredNotificationsProvider =
    Provider.autoDispose<List<NotificationItem>>((ref) {
  final notifications =
      ref.watch(notificationStreamProvider).valueOrNull ?? const [];
  final categoryFilter = ref.watch(notificationCategoryFilterProvider);

  if (categoryFilter == null) {
    return notifications;
  }
  return notifications
      .where((item) => item.category == categoryFilter)
      .toList();
});

/// State controller managing notification mutation operations
/// (mark single as read, mark all as read, delete notification).
class NotificationController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  NotificationController(this._ref) : super(const AsyncData(null));

  /// Marks a specific notification as read.
  /// If [storeId] is omitted, defaults to [currentStoreIdProvider].
  Future<void> markAsRead(String id, {String? storeId}) async {
    state = const AsyncLoading();
    try {
      final String sId = (storeId != null && storeId.trim().isNotEmpty)
          ? storeId
          : _ref.read(currentStoreIdProvider);
      final repo = _ref.read(notificationRepositoryProvider);
      await repo.markAsRead(storeId: sId, id: id);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Marks all unread notifications in the store as read.
  /// If [storeId] is omitted, defaults to [currentStoreIdProvider].
  Future<void> markAllAsRead({String? storeId}) async {
    state = const AsyncLoading();
    try {
      final String sId = (storeId != null && storeId.trim().isNotEmpty)
          ? storeId
          : _ref.read(currentStoreIdProvider);
      final repo = _ref.read(notificationRepositoryProvider);
      await repo.markAllAsRead(sId);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Deletes a specific notification from the store.
  /// If [storeId] is omitted, defaults to [currentStoreIdProvider].
  Future<void> deleteNotification(String id, {String? storeId}) async {
    state = const AsyncLoading();
    try {
      final String sId = (storeId != null && storeId.trim().isNotEmpty)
          ? storeId
          : _ref.read(currentStoreIdProvider);
      final repo = _ref.read(notificationRepositoryProvider);
      await repo.deleteNotification(storeId: sId, id: id);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Adds a notification to the store via [NotificationRepository].
  Future<void> addNotification(NotificationItem notification) async {
    state = const AsyncLoading();
    try {
      final repo = _ref.read(notificationRepositoryProvider);
      await repo.addNotification(notification);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

/// Auto-disposed provider for [NotificationController].
final notificationControllerProvider = StateNotifierProvider.autoDispose<
    NotificationController, AsyncValue<void>>((ref) {
  return NotificationController(ref);
});
