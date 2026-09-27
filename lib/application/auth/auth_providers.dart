import 'dart:async';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/filter_storage_service.dart';
import '../../data/datasources/firebase/auth_remote_data_source.dart';
import '../../domain/entities/user_account.dart';

import 'user_filter_hydration.dart';

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  try {
    return AuthRemoteDataSource(FirebaseDatabase.instance);
  } catch (_) {
    return AuthRemoteDataSource();
  }
});

final authLoadingProvider = StateProvider<bool>((ref) {
  final prefs = FilterStorageService.sharedPrefs;
  final cached = AuthNotifier.loadCachedUserSync(prefs);
  if (cached != null) return false;
  final hasSavedCreds = prefs?.getString('saved_username') != null &&
      prefs?.getString('saved_password') != null;
  return hasSavedCreds;
});

/// Ensures filterStorageUsernameResolver is connected to authProvider.
void setupFilterStorageResolver() {
  filterStorageUsernameResolver = (r) {
    try {
      return r.read(authProvider)?.username;
    } catch (_) {
      return null;
    }
  };
}

class AuthNotifier extends StateNotifier<UserAccount?> {
  final AuthRemoteDataSource _dataSource;
  final Ref _ref;
  int _authEpoch = 0;
  bool _isManualLoginActive = false;

  AuthNotifier(this._dataSource, this._ref, [UserAccount? initialUser])
      : super(initialUser) {
    setupFilterStorageResolver();
    scheduleMicrotask(_tryAutoLogin);
  }

  static UserAccount? loadCachedUserSync(SharedPreferences? prefs) {
    if (prefs == null) return null;
    final accountJson = prefs.getString('saved_user_account');
    final sessionJson = prefs.getString('saved_user_session');
    final username = prefs.getString('saved_username');

    UserAccount? parseUser(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          final user = UserAccount.fromJson(map);
          final userU = user.username.trim().toLowerCase();
          final savedU = username?.trim().toLowerCase();
          if (userU.isNotEmpty &&
              (savedU == null || savedU.isEmpty || userU == savedU)) {
            return user;
          }
        }
      } catch (_) {}
      return null;
    }

    return parseUser(accountJson) ?? parseUser(sessionJson);
  }

  Future<void> _tryAutoLogin() async {
    if (_isManualLoginActive) return;
    final epoch = ++_authEpoch;
    try {
      final prefs = FilterStorageService.sharedPrefs ??
          await SharedPreferences.getInstance();
      FilterStorageService.setSharedPrefs(prefs);
      if (!mounted || epoch != _authEpoch || _isManualLoginActive) return;

      final accountJson = prefs.getString('saved_user_account');
      final sessionJson = prefs.getString('saved_user_session');
      final username = prefs.getString('saved_username');
      final password = prefs.getString('saved_password');

      UserAccount? parseUserJson(String? raw) {
        if (raw == null || raw.trim().isEmpty) return null;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final map = Map<String, dynamic>.from(decoded);
            final user = UserAccount.fromJson(map);
            final userU = user.username.trim().toLowerCase();
            final savedU = username?.trim().toLowerCase();
            if (userU.isNotEmpty &&
                (savedU == null || savedU.isEmpty || userU == savedU)) {
              return user;
            }
          }
        } catch (_) {}
        return null;
      }

      final cachedUser =
          state ?? (parseUserJson(accountJson) ?? parseUserJson(sessionJson));

      // Tự động dọn dẹp các khóa cache thực sự bị hỏng / không hợp lệ
      if (accountJson != null && parseUserJson(accountJson) == null) {
        try {
          await prefs.remove('saved_user_account');
        } catch (_) {}
      }
      if (sessionJson != null && parseUserJson(sessionJson) == null) {
        try {
          await prefs.remove('saved_user_session');
        } catch (_) {}
      }

      if (!mounted || epoch != _authEpoch) return;

      // 1. Khởi động tức thì (Instant Startup Session):
      // Nếu có saved_user_account hoặc saved_user_session hợp lệ, khôi phục ngay lập tức state = UserAccount
      // để người dùng vào thẳng màn hình chính không phải chờ đợi hay thấy màn hình login.
      if (cachedUser != null) {
        if (state != cachedUser) {
          state = cachedUser;
        }
        await _hydrateUserSelectedStore(cachedUser);
        if (!mounted || epoch != _authEpoch) return;
        await rehydrateAllUserFilters(_ref, cachedUser, () => state?.username);
        if (mounted && epoch == _authEpoch) {
          try {
            _ref.read(authLoadingProvider.notifier).state = false;
          } catch (_) {}
        }
      }

      if (username == null || password == null) {
        if (mounted && epoch == _authEpoch) {
          try {
            _ref.read(authLoadingProvider.notifier).state = false;
          } catch (_) {}
        }
        return;
      }

      // 2. Tái xác thực trong nền hoặc đăng nhập nếu chưa có cachedUser
      try {
        final remoteUser = await _dataSource.login(username, password);
        if (!mounted || epoch != _authEpoch) return;

        if (remoteUser != null) {
          // Máy chủ phản hồi thành công -> cập nhật trạng thái mới nhất và lưu cache
          if (!mounted || epoch != _authEpoch) return;
          state = remoteUser;
          final userJson = jsonEncode(remoteUser.toJson());
          if (!mounted || epoch != _authEpoch) return;
          await prefs.setString('saved_user_account', userJson);
          if (!mounted || epoch != _authEpoch) return;
          await prefs.setString('saved_user_session', userJson);
          if (!mounted || epoch != _authEpoch) return;
          await _hydrateUserSelectedStore(remoteUser);
          if (!mounted || epoch != _authEpoch) return;
          await rehydrateAllUserFilters(
              _ref, remoteUser, () => state?.username);
        } else {
          // Máy chủ trả về null -> Mã lỗi xác thực rõ ràng:
          // Mật khẩu đã bị đổi từ xa hoặc tài khoản đã bị vô hiệu hóa / xóa khỏi hệ thống.
          // Chỉ trong trường hợp này mới xóa thông tin đăng nhập!
          if (!mounted || epoch != _authEpoch) return;
          await prefs.remove('saved_username');
          if (!mounted || epoch != _authEpoch) return;
          await prefs.remove('saved_password');
          if (!mounted || epoch != _authEpoch) return;
          await prefs.remove('saved_user_account');
          if (!mounted || epoch != _authEpoch) return;
          await prefs.remove('saved_user_session');
          if (!mounted || epoch != _authEpoch) return;
          state = null;
          _ref.read(selectedStoreIdProvider.notifier).state = null;
          try {
            resetAllInMemoryFilters(_ref);
          } catch (_) {}
        }
      } on AuthNetworkException catch (_) {
        // Gặp lỗi kết nối, Firebase handshake trễ, hoặc mạng chập chờn / offline:
        // Tuyệt đối không xóa saved_username / saved_password / saved_user_account.
        // Giữ nguyên phiên làm việc cục bộ của người dùng (cachedUser).
      } catch (_) {
        // Bất kỳ lỗi mạng / timeout nào khác: cũng tuyệt đối giữ nguyên phiên!
      }
    } catch (_) {
      // Bỏ qua lỗi SharedPreferences khi khởi động
    } finally {
      if (mounted && epoch == _authEpoch) {
        try {
          _ref.read(authLoadingProvider.notifier).state = false;
        } catch (_) {}
      }
    }
  }

  Future<String?> login(String username, String password) async {
    _isManualLoginActive = true;
    final epoch = ++_authEpoch;
    try {
      final user = await _dataSource.login(username, password);
      if (!mounted || epoch != _authEpoch) return null;
      if (user != null) {
        // Ghi nhận ngay vào SharedPreferences trước khi thực hiện các tác vụ khác
        final prefs = FilterStorageService.sharedPrefs ??
            await SharedPreferences.getInstance();
        if (!mounted || epoch != _authEpoch) return null;
        FilterStorageService.setSharedPrefs(prefs);
        final userJson = jsonEncode(user.toJson());
        await prefs.setString('saved_username', username.trim());
        if (!mounted || epoch != _authEpoch) return null;
        await prefs.setString('saved_password', password);
        if (!mounted || epoch != _authEpoch) return null;
        await prefs.setString('saved_user_account', userJson);
        if (!mounted || epoch != _authEpoch) return null;
        await prefs.setString('saved_user_session', userJson);
        if (!mounted || epoch != _authEpoch) return null;

        state = user;
        await _hydrateUserSelectedStore(user);
        if (!mounted || epoch != _authEpoch) return null;
        await rehydrateAllUserFilters(_ref, user, () => state?.username);
        return null; // Success
      } else {
        return 'Tên đăng nhập hoặc mật khẩu không đúng.';
      }
    } on AuthNetworkException catch (e) {
      return e.message;
    } catch (e) {
      return 'Có lỗi xảy ra: $e';
    } finally {
      if (epoch == _authEpoch) {
        _isManualLoginActive = false;
      }
    }
  }

  Future<void> _hydrateUserSelectedStore(UserAccount user) async {
    if (!mounted) return;
    if (user.canSwitchStore) {
      final storage = _ref.read(filterStorageServiceProvider);
      // selectedStoreIdProvider automatically reactively watches authProvider.
      // We only perform async fallback load if the synchronous check returned null.
      if (storage.loadSelectedStoreSync(user.username) == null) {
        final asyncSaved = await storage.loadSelectedStore(user.username);
        if (!mounted || state?.username != user.username) return;
        if (asyncSaved != null && asyncSaved.isNotEmpty) {
          _ref.read(selectedStoreIdProvider.notifier).state = asyncSaved;
        }
      }
    }
  }

  Future<void> logout() async {
    _authEpoch++;
    state = null;
    try {
      _ref.read(authLoadingProvider.notifier).state = false;
    } catch (_) {}
    try {
      resetAllInMemoryFilters(_ref);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_username');
      await prefs.remove('saved_password');
      await prefs.remove('saved_user_account');
      await prefs.remove('saved_user_session');
    } catch (_) {}
  }
}

/// Extension to synchronize saved credentials when updating user password
extension AuthNotifierPasswordExtension on AuthNotifier {
  Future<void> updateSavedPassword(String newPassword) async {
    try {
      final shared = FilterStorageService.sharedPrefs;
      if (shared != null) {
        await shared.setString('saved_password', newPassword);
        return;
      }
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(milliseconds: 50),
        onTimeout: () => throw TimeoutException('prefs timeout'),
      );
      await prefs.setString('saved_password', newPassword);
    } catch (_) {}
  }
}

final StateNotifierProvider<AuthNotifier, UserAccount?> authProvider =
    StateNotifierProvider<AuthNotifier, UserAccount?>((ref) {
  setupFilterStorageResolver();
  final dataSource = ref.watch(authRemoteDataSourceProvider);
  final prefs = FilterStorageService.sharedPrefs;
  final initialUser = AuthNotifier.loadCachedUserSync(prefs);
  return AuthNotifier(dataSource, ref, initialUser);
});

final StateProvider<String?> selectedStoreIdProvider =
    StateProvider<String?>((ref) {
  setupFilterStorageResolver();
  final user = ref.watch(authProvider);
  if (user == null || !user.canSwitchStore) return null;

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadSelectedStoreSync(user.username);
  if (saved != null && saved.isNotEmpty) {
    return saved;
  }

  return null;
});

// A convenient provider just to get the current store id or empty string
final Provider<String> currentStoreIdProvider = Provider<String>((ref) {
  setupFilterStorageResolver();

  final user = ref.watch(authProvider);
  // Nếu là Nhân viên hoặc Giám sát (không có quyền canSwitchStore), bắt buộc trả về storeId cá nhân
  if (user != null && !user.canSwitchStore) {
    return user.storeId.isNotEmpty && user.storeId != 'all'
        ? user.storeId
        : 'store_001';
  }

  final selected = ref.watch(selectedStoreIdProvider);
  if (selected != null && selected.isNotEmpty && selected != 'all') {
    return selected;
  }

  if (user != null && user.storeId.isNotEmpty && user.storeId != 'all') {
    return user.storeId;
  }

  return 'store_001';
});

final currentStoreNameProvider = FutureProvider<String>((ref) async {
  final storeId = ref.watch(currentStoreIdProvider);
  try {
    final availableStores = await ref.watch(availableStoresProvider.future);
    if (availableStores.containsKey(storeId)) {
      return availableStores[storeId]!;
    }
  } catch (e) {
    rethrow;
  }

  if (storeId == 'store_001') {
    return 'Chi nhánh Đông Thắng';
  } else if (storeId == 'store_002') {
    return 'Chi nhánh Thới Bình';
  }
  return 'Chi nhánh $storeId';
});

final availableStoresProvider =
    FutureProvider<Map<String, String>>((ref) async {
  try {
    final accountsSnap =
        await FirebaseDatabase.instance.ref('stores/accounts').get();
    final Set<String> storeIds = {};
    if (accountsSnap.exists && accountsSnap.value != null) {
      try {
        final map = Map<String, dynamic>.from(accountsSnap.value as Map);
        for (final v in map.values) {
          if (v is Map && v['storeId'] != null) {
            final sId = v['storeId'].toString();
            if (sId.isNotEmpty && sId != 'all') {
              storeIds.add(sId);
            }
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
          result[id] = 'Chi nhánh Đông Thắng';
        } else if (id == 'store_002') {
          result[id] = 'Chi nhánh Thới Bình';
        } else {
          result[id] = 'Chi nhánh $id';
        }
      }
    }
    return result;
  } catch (_) {
    return {
      'store_001': 'Chi nhánh Đông Thắng',
      'store_002': 'Chi nhánh Thới Bình',
    };
  }
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
