import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/firebase/auth_remote_data_source.dart';
import '../../domain/entities/user_account.dart';

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(FirebaseDatabase.instance);
});

class AuthNotifier extends StateNotifier<UserAccount?> {
  final AuthRemoteDataSource _dataSource;

  AuthNotifier(this._dataSource) : super(null);

  Future<String?> login(String username, String password) async {
    try {
      final user = await _dataSource.login(username, password);
      if (user != null) {
        state = user;
        return null; // Success
      } else {
        return 'Tên đăng nhập hoặc mật khẩu không đúng.';
      }
    } catch (e) {
      return 'Có lỗi xảy ra: $e';
    }
  }

  void logout() {
    state = null;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, UserAccount?>((ref) {
  final dataSource = ref.watch(authRemoteDataSourceProvider);
  return AuthNotifier(dataSource);
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

final availableStoresProvider = FutureProvider<Map<String, String>>((ref) async {
  final accountsSnap = await FirebaseDatabase.instance.ref('stores/accounts').get();
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
    
    if (nameSnap.exists && nameSnap.value != null && nameSnap.value != "") {
      result[id] = nameSnap.value.toString();
    } else if (addrSnap.exists && addrSnap.value != null && addrSnap.value != "") {
      result[id] = addrSnap.value.toString();
    } else {
      result[id] = id;
    }
  }
  return result;
});