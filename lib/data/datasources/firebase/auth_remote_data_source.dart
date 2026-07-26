import 'dart:async';

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

  /// Optimized: dùng onChildAdded/Changed/Removed thay vì onValue
  Stream<List<Map<String, dynamic>>> watchAllAccounts() {
    final controller = StreamController<List<Map<String, dynamic>>>();
    final Map<String, Map<String, dynamic>> cache = {};
    bool initialLoaded = false;

    void safeEmit() {
      if (initialLoaded && !controller.isClosed) {
        controller.add(cache.values.toList());
      }
    }

    final addSub = _ref.onChildAdded.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final accountMap = Map<String, dynamic>.from(val);
        accountMap['username'] = event.snapshot.key.toString();
        cache[event.snapshot.key!] = accountMap;
        safeEmit();
      }
    });

    final changeSub = _ref.onChildChanged.listen((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final accountMap = Map<String, dynamic>.from(val);
        accountMap['username'] = event.snapshot.key.toString();
        cache[event.snapshot.key!] = accountMap;
        safeEmit();
      }
    });

    final removeSub = _ref.onChildRemoved.listen((event) {
      cache.remove(event.snapshot.key);
      safeEmit();
    });

    _ref.get().then((snap) {
      if (snap.value != null && snap.value is Map) {
        final map = Map<dynamic, dynamic>.from(snap.value as Map);
        map.forEach((key, value) {
          if (value is Map) {
            final accountMap = Map<String, dynamic>.from(value);
            accountMap['username'] = key.toString();
            cache[key.toString()] = accountMap;
          }
        });
      }
      initialLoaded = true;
      safeEmit();
    }).catchError((err) {
      if (!controller.isClosed) {
        controller.addError(err);
      }
    });

    controller.onCancel = () {
      addSub.cancel();
      changeSub.cancel();
      removeSub.cancel();
    };

    return controller.stream;
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
