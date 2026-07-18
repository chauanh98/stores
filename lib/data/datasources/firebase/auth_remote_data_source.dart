import 'package:firebase_database/firebase_database.dart';

import '../../../domain/entities/user_account.dart';

class AuthRemoteDataSource {
  final FirebaseDatabase _db;

  AuthRemoteDataSource(this._db);

  DatabaseReference get _ref => _db.ref('stores/accounts');

  Future<UserAccount?> login(String username, String password) async {
    final snap = await _ref.child(username).get();
    if (snap.exists && snap.value != null) {
      final data = Map<String, dynamic>.from(snap.value as Map);
      if (data['password'] == password) {
        return UserAccount.fromMap(username, data);
      }
    }
    return null;
  }

  Stream<List<Map<String, dynamic>>> watchAllAccounts() {
    return _ref.onValue.map((event) {
      if (event.snapshot.value == null) return [];
      final Map<dynamic, dynamic> map =
          Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final List<Map<String, dynamic>> accounts = [];
      map.forEach((key, value) {
        if (value is Map) {
          final accountMap = Map<String, dynamic>.from(value);
          accountMap['username'] = key.toString();
          accounts.add(accountMap);
        }
      });
      return accounts;
    });
  }

  Future<void> saveAccount(String username, Map<String, dynamic> map) {
    return _ref.child(username).set(map);
  }

  Future<void> deleteAccount(String username) {
    return _ref.child(username).remove();
  }

  Future<String?> getAccountPassword(String username) async {
    final snap = await _ref.child(username).child('password').get();
    if (snap.exists && snap.value != null) {
      return snap.value.toString();
    }
    return null;
  }
}
