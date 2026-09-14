import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../../../domain/entities/store_payment_config.dart';
import '../../models/store_payment_config_model.dart';

class StorePaymentConfigRemoteDataSource {
  final FirebaseDatabase? _db;

  StorePaymentConfigRemoteDataSource([this._db]);

  DatabaseReference? _ref(String storeId) =>
      _db?.ref('store_payment_configs').child(storeId);

  Stream<StorePaymentConfig> watchConfig(String storeId) {
    final ref = _ref(storeId);
    if (ref == null) return const Stream.empty();
    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      if (value is Map) {
        return StorePaymentConfigModel.fromMap(
          Map<String, dynamic>.from(value),
          storeId,
        ).toDomain();
      }
      return StorePaymentConfig(storeId: storeId);
    });
  }

  Future<StorePaymentConfig> fetchConfig(String storeId) async {
    final ref = _ref(storeId);
    if (ref == null) return StorePaymentConfig(storeId: storeId);
    final snap = await ref.get();
    final value = snap.value;
    if (value is Map) {
      return StorePaymentConfigModel.fromMap(
        Map<String, dynamic>.from(value),
        storeId,
      ).toDomain();
    }
    return StorePaymentConfig(storeId: storeId);
  }

  Future<void> saveConfig(StorePaymentConfig config) {
    final ref = _ref(config.storeId);
    if (ref == null) return Future.value();
    final model = StorePaymentConfigModel.fromDomain(config);
    return ref.set(model.toMap());
  }
}
