import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../../../domain/entities/user_account.dart';

/// Exception thrown when remote authentication fails due to network or connection issues.
class AuthNetworkException implements Exception {
  final String message;
  const AuthNetworkException([this.message = 'Lỗi kết nối mạng']);

  @override
  String toString() => message;
}

class AuthRemoteDataSource {
  final FirebaseDatabase? _db;

  AuthRemoteDataSource([this._db]);

  DatabaseReference? get _ref {
    try {
      final db = _db ?? FirebaseDatabase.instance;
      return db.ref('stores/accounts');
    } catch (_) {
      return null;
    }
  }

  Future<UserAccount?> login(String username, String password) async {
    final ref = _ref;
    if (ref == null) {
      throw const AuthNetworkException('Không thể kết nối đến cơ sở dữ liệu');
    }
    try {
      final cleanUsername = username.trim();
      final snap = await ref.child(cleanUsername).get().timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw const AuthNetworkException(
                'Hết thời gian chờ phản hồi từ máy chủ'),
          );
      if (!snap.exists || snap.value == null) {
        return null; // Tài khoản không tồn tại
      }
      final data = Map<String, dynamic>.from(snap.value as Map);
      final savedPass = data['password']?.toString() ?? '';
      if (savedPass != password.toString()) {
        return null; // Mật khẩu không đúng
      }
      return UserAccount.fromMap(cleanUsername, data);
    } on AuthNetworkException {
      rethrow;
    } on TimeoutException {
      throw const AuthNetworkException('Hết thời gian kết nối đến máy chủ');
    } catch (e) {
      throw AuthNetworkException('Lỗi kết nối cơ sở dữ liệu: $e');
    }
  }

  /// Optimized: dùng debounced stream cho onChildAdded và onValue.take(1) kiểm tra node rỗng,
  /// loại bỏ hoàn toàn ref.get() để tránh tải kép dữ liệu accounts.
  Stream<List<Map<String, dynamic>>> watchAllAccounts() {
    final ref = _ref;
    if (ref == null) return Stream.value([]);
    final controller = StreamController<List<Map<String, dynamic>>>();
    final Map<String, Map<String, dynamic>> cache = {};
    Timer? debounceTimer;
    bool hasEmitted = false;

    void debouncedEmit() {
      debounceTimer?.cancel();
      debounceTimer = Timer(const Duration(milliseconds: 50), () {
        if (!controller.isClosed) {
          hasEmitted = true;
          controller.add(cache.values.toList());
        }
      });
    }

    final addSub = ref.onChildAdded.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final accountMap = Map<String, dynamic>.from(val);
        accountMap['username'] = event.snapshot.key.toString();
        cache[event.snapshot.key!] = accountMap;
        debouncedEmit();
      }
    });

    final changeSub = ref.onChildChanged.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final accountMap = Map<String, dynamic>.from(val);
        accountMap['username'] = event.snapshot.key.toString();
        cache[event.snapshot.key!] = accountMap;
        if (!controller.isClosed) {
          controller.add(cache.values.toList());
        }
      }
    });

    final removeSub = ref.onChildRemoved.listen((event) {
      final key = event.snapshot.key;
      if (key != null) {
        cache.remove(key);
        if (!controller.isClosed) {
          controller.add(cache.values.toList());
        }
      }
    });

    final emptyCheckSub = ref.limitToFirst(1).onValue.take(1).listen((event) {
      if (event.snapshot.value == null) {
        if (cache.isEmpty && !hasEmitted && !controller.isClosed) {
          hasEmitted = true;
          controller.add([]);
        }
      }
    });

    controller.onCancel = () {
      debounceTimer?.cancel();
      addSub.cancel();
      changeSub.cancel();
      removeSub.cancel();
      emptyCheckSub.cancel();
    };

    return controller.stream;
  }

  Future<void> saveAccount(String username, Map<String, dynamic> map) {
    final ref = _ref;
    if (ref == null) throw Exception('No database connection');
    return ref.child(username).set(map);
  }

  Future<void> deleteAccount(String username) {
    final ref = _ref;
    if (ref == null) throw Exception('No database connection');
    return ref.child(username).remove();
  }

  Future<String?> getAccountPassword(String username) async {
    final ref = _ref;
    if (ref == null) return null;
    try {
      final snap = await ref.child(username).child('password').get();
      if (snap.exists && snap.value != null) {
        return snap.value.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> updatePassword(
      String username, String oldPassword, String newPassword) async {
    final currentPass = await getAccountPassword(username);
    if (currentPass != null && currentPass != oldPassword) {
      throw Exception('Mật khẩu hiện tại không chính xác');
    }
    final ref = _ref;
    if (ref == null) throw Exception('No database connection');
    await ref.child(username).child('password').set(newPassword);
  }
}
