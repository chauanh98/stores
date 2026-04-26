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
}