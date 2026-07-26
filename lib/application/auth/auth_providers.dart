import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/firebase/auth_remote_data_source.dart';
import '../../domain/entities/user_account.dart';

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(FirebaseDatabase.instance);
});

final authLoadingProvider = StateProvider<bool>((ref) => true);

class AuthNotifier extends StateNotifier<UserAccount?> {
  final AuthRemoteDataSource _dataSource;
  final Ref _ref;

  AuthNotifier(this._dataSource, this._ref) : super(null) {
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('saved_username');
      final password = prefs.getString('saved_password');
      if (username != null && password != null) {
        final user = await _dataSource.login(username, password);
        if (user != null) {
          state = user;
        } else {
          // Xoá thông tin lưu nếu đăng nhập không hợp lệ (ví dụ: đổi mật khẩu)
          await prefs.remove('saved_username');
          await prefs.remove('saved_password');
        }
      }
    } catch (_) {
      // Bỏ qua lỗi mạng khi khởi động, để người dùng vào màn hình login tự nhập thủ công
    } finally {
      _ref.read(authLoadingProvider.notifier).state = false;
    }
  }

  Future<String?> login(String username, String password) async {
    try {
      final user = await _dataSource.login(username, password);
      if (user != null) {
        state = user;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_username', username);
        await prefs.setString('saved_password', password);
        return null; // Success
      } else {
        return 'Tên đăng nhập hoặc mật khẩu không đúng.';
      }
    } catch (e) {
      return 'Có lỗi xảy ra: $e';
    }
  }

  Future<void> logout() async {
    state = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_username');
      await prefs.remove('saved_password');
    } catch (_) {}
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, UserAccount?>((ref) {
  final dataSource = ref.watch(authRemoteDataSourceProvider);
  return AuthNotifier(dataSource, ref);
});

final selectedStoreIdProvider = StateProvider<String?>((ref) => null);

// A convenient provider just to get the current store id or empty string
final currentStoreIdProvider = Provider<String>((ref) {
  final selected = ref.watch(selectedStoreIdProvider);
  if (selected != null) return selected;

  final user = ref.watch(authProvider);
  return user?.storeId ?? 'store_001';
});

final currentStoreNameProvider = FutureProvider<String>((ref) async {
  final storeId = ref.watch(currentStoreIdProvider);
  final db = FirebaseDatabase.instance.ref('stores/$storeId');
  final nameSnap = await db.child('name').get();
  if (nameSnap.exists && nameSnap.value != null && nameSnap.value != "") {
    return nameSnap.value.toString();
  }
  final addrSnap = await db.child('address').get();
  if (addrSnap.exists && addrSnap.value != null && addrSnap.value != "") {
    return addrSnap.value.toString();
  }
  return storeId;
});

final availableStoresProvider =
    FutureProvider<Map<String, String>>((ref) async {
  final accountsSnap =
      await FirebaseDatabase.instance.ref('stores/accounts').get();
  final Set<String> storeIds = {};
  if (accountsSnap.exists && accountsSnap.value != null) {
    try {
      final map = Map<String, dynamic>.from(accountsSnap.value as Map);
      for (final v in map.values) {
        if (v is Map && v['storeId'] != null) {
          storeIds.add(v['storeId'].toString());
        }
      }
    } catch (_) {}
  }

  final Map<String, String> result = {};
  final idsToFetch = storeIds.isEmpty ? ['store_001', 'store_002'] : storeIds;

  for (final id in idsToFetch) {
    final db = FirebaseDatabase.instance.ref('stores/$id');
    final nameSnap = await db.child('name').get();
    final addrSnap = await db.child('address').get();

    if (nameSnap.exists &&
        nameSnap.value != null &&
        nameSnap.value.toString().isNotEmpty) {
      result[id] = nameSnap.value.toString();
    } else if (addrSnap.exists &&
        addrSnap.value != null &&
        addrSnap.value.toString().isNotEmpty) {
      result[id] = addrSnap.value.toString();
    } else {
      if (id == 'store_001') {
        result[id] = 'Chi nhánh Thới Bình';
      } else if (id == 'store_002') {
        result[id] = 'Chi nhánh Đông Thắng';
      } else {
        result[id] = 'Chi nhánh $id';
      }
    }
  }
  return result;
});

final accountsListProvider =
    StreamProvider.autoDispose<List<UserAccount>>((ref) {
  final ds = ref.watch(authRemoteDataSourceProvider);
  return ds.watchAllAccounts().map((list) {
    return list
        .map((m) => UserAccount.fromMap(m['username'] as String, m))
        .toList();
  });
});
