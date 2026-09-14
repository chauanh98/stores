import '../entities/supplier.dart';
import '../entities/supplier_debt_transaction.dart';

abstract class SupplierRepository {
  /// Stream danh sách nhà cung cấp
  Stream<List<Supplier>> watchAll({String? storeId});

  /// Lấy thông tin 1 nhà cung cấp theo id
  Future<Supplier?> fetchById(String id, {String? storeId});

  /// Thêm mới hoặc cập nhật nhà cung cấp
  Future<void> upsert(Supplier supplier, {String? storeId});

  /// Xóa nhà cung cấp
  Future<void> delete(String id, {String? storeId});

  /// Ghi nhận giao dịch công nợ NCC
  Future<void> recordDebtTransaction(SupplierDebtTransaction transaction, {String? storeId});

  /// Stream lịch sử công nợ của 1 nhà cung cấp
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(String supplierId, {String? storeId});

  /// Lấy danh sách lịch sử công nợ của 1 nhà cung cấp
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(String supplierId, {String? storeId});
}
