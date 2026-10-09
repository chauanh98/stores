import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Remote data source responsible for FCM token persistence and push queue management
/// on Firebase Realtime Database at path `stores/$storeId/fcm_tokens/$userId/$tokenId`.
class FcmRemoteDataSource {
  final FirebaseDatabase? _db;

  FcmRemoteDataSource([FirebaseDatabase? db]) : _db = db;

  FirebaseDatabase get _database {
    final db = _db;
    if (db != null) return db;
    return FirebaseDatabase.instance;
  }

  /// Helper to sanitize token strings so they can be safely used as Firebase RTDB keys.
  /// Firebase keys cannot contain '.', '#', '$', '[', ']', '/', or ASCII control characters.
  static String sanitizeTokenKey(String token) {
    return token.replaceAll(RegExp(r'[.#$\[\]/\x00-\x1F\x7F]'), '_');
  }

  DatabaseReference _userTokensRef(String storeId, String userId) =>
      _database.ref('stores/$storeId/fcm_tokens/$userId');

  DatabaseReference _storeTokensRef(String storeId) =>
      _database.ref('stores/$storeId/fcm_tokens');

  DatabaseReference _pushQueueRef(String storeId) =>
      _database.ref('stores/$storeId/fcm_queue');

  /// Saves or refreshes an Admin FCM token in RTDB.
  Future<void> saveToken({
    required String storeId,
    required String userId,
    required String token,
    Map<String, dynamic>? deviceInfo,
  }) async {
    if (storeId.trim().isEmpty || userId.trim().isEmpty || token.trim().isEmpty) {
      return;
    }
    try {
      final tokenId = sanitizeTokenKey(token);
      final ref = _userTokensRef(storeId, userId).child(tokenId);
      final data = <String, dynamic>{
        'token': token,
        'userId': userId,
        'storeId': storeId,
        'updatedAt': DateTime.now().toIso8601String(),
        if (deviceInfo != null) ...deviceInfo,
      };
      await ref.set(data);
    } catch (e) {
      debugPrint('[FcmRemoteDataSource] saveToken failed: $e');
    }
  }

  /// Removes a specific device token from RTDB on user logout.
  Future<void> deleteToken({
    required String storeId,
    required String userId,
    required String token,
  }) async {
    if (storeId.trim().isEmpty || userId.trim().isEmpty || token.trim().isEmpty) {
      return;
    }
    try {
      final tokenId = sanitizeTokenKey(token);
      await _userTokensRef(storeId, userId).child(tokenId).remove();
    } catch (e) {
      debugPrint('[FcmRemoteDataSource] deleteToken failed: $e');
    }
  }

  /// Clears all tokens associated with a given user under a store.
  Future<void> clearUserTokens({
    required String storeId,
    required String userId,
  }) async {
    if (storeId.trim().isEmpty || userId.trim().isEmpty) {
      return;
    }
    try {
      await _userTokensRef(storeId, userId).remove();
    } catch (e) {
      debugPrint('[FcmRemoteDataSource] clearUserTokens failed: $e');
    }
  }

  /// Fetches all active FCM tokens for Admin accounts in the specified store.
  Future<List<String>> getAdminTokens({
    required String storeId,
  }) async {
    if (storeId.trim().isEmpty) return [];
    try {
      final snap = await _storeTokensRef(storeId).get();
      final val = snap.value;
      if (val == null) return [];

      final List<String> tokens = [];

      void extractTokenFromEntry(dynamic tokenEntry) {
        if (tokenEntry == null) return;
        if (tokenEntry is Map) {
          final raw = tokenEntry['token'] ??
              tokenEntry['fcmToken'] ??
              tokenEntry['deviceToken'] ??
              tokenEntry['registrationToken'];
          if (raw != null) {
            final t = raw.toString().trim();
            if (t.isNotEmpty &&
                t != 'null' &&
                t != 'undefined' &&
                !tokens.contains(t)) {
              tokens.add(t);
            }
          }
        } else if (tokenEntry is String) {
          final t = tokenEntry.trim();
          if (t.isNotEmpty &&
              t != 'null' &&
              t != 'undefined' &&
              !tokens.contains(t)) {
            tokens.add(t);
          }
        }
      }

      void processUserEntry(dynamic userEntry) {
        if (userEntry == null) return;
        if (userEntry is Map) {
          for (final tokenEntry in userEntry.values) {
            extractTokenFromEntry(tokenEntry);
          }
        } else if (userEntry is Iterable) {
          for (final tokenEntry in userEntry) {
            extractTokenFromEntry(tokenEntry);
          }
        } else if (userEntry is String) {
          extractTokenFromEntry(userEntry);
        }
      }

      if (val is Map) {
        for (final userEntry in val.values) {
          processUserEntry(userEntry);
        }
      } else if (val is Iterable) {
        for (final userEntry in val) {
          processUserEntry(userEntry);
        }
      }
      return tokens;
    } catch (e) {
      debugPrint('[FcmRemoteDataSource] getAdminTokens failed: $e');
      return [];
    }
  }

  /// Enqueues a push notification payload for delivery.
  Future<void> queuePushNotification({
    required String storeId,
    required Map<String, dynamic> payload,
  }) async {
    if (storeId.trim().isEmpty) return;
    try {
      final ref = _pushQueueRef(storeId).push();
      final data = <String, dynamic>{
        'queueId': ref.key,
        'createdAt': DateTime.now().toIso8601String(),
        ...payload,
      };
      await ref.set(data);
    } catch (e) {
      debugPrint('[FcmRemoteDataSource] queuePushNotification failed: $e');
    }
  }
}
