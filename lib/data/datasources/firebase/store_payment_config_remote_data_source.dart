import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../../../domain/entities/store_payment_config.dart';

class StorePaymentConfigRemoteDataSource {
  final FirebaseDatabase _db;

  StorePaymentConfigRemoteDataSource(this._db);

  DatabaseReference _ref(String storeId) =>
      _db.ref('store_payment_configs').child(storeId);

  Stream<StorePaymentConfig> watchConfig(String storeId) {
    return _ref(storeId).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is Map) {
        return StorePaymentConfig.fromMap(storeId, Map<String, dynamic>.from(value));
      }
      return StorePaymentConfig(storeId: storeId);
    });
  }

  Future<StorePaymentConfig> fetchConfig(String storeId) async {
    final snap = await _ref(storeId).get();
    final value = snap.value;
    if (value is Map) {
      return StorePaymentConfig.fromMap(storeId, Map<String, dynamic>.from(value));
    }
    return StorePaymentConfig(storeId: storeId);
  }

  Future<void> saveConfig(StorePaymentConfig config) {
    return _ref(config.storeId).set(config.toMap());
  }
}
