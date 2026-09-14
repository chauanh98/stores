import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/vietnamese_text_helper.dart';
import '../../data/datasources/firebase/supplier_remote_data_source.dart';
import '../../data/repositories/supplier_repository_impl.dart';
import '../../domain/entities/supplier.dart';
import '../../domain/entities/supplier_debt_transaction.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../auth/auth_providers.dart';
import 'supplier_list_notifier.dart';

export 'supplier_list_notifier.dart';

enum SupplierFilterStatus {
  all, // Tất cả
  hasDebt, // Còn nợ
  noDebt, // Hết nợ
}

class SupplierKpis {
  final int totalSuppliers;
  final double totalPurchase;
  final double totalDebt;

  const SupplierKpis({
    this.totalSuppliers = 0,
    this.totalPurchase = 0.0,
    this.totalDebt = 0.0,
  });
}

final supplierRemoteDataSourceProvider =
    Provider<SupplierRemoteDataSource>((ref) {
  return SupplierRemoteDataSource(FirebaseDatabase.instance);
});

final supplierRepositoryProvider = Provider<SupplierRepository>((ref) {
  final ds = ref.watch(supplierRemoteDataSourceProvider);
  return SupplierRepositoryImpl(ds);
});

final supplierListNotifierProvider =
    AutoDisposeAsyncNotifierProvider<SupplierListNotifier, List<Supplier>>(
  SupplierListNotifier.new,
);

final supplierSearchQueryProvider =
    StateProvider.autoDispose<String>((ref) => '');

final supplierFilterStatusProvider =
    StateProvider.autoDispose<SupplierFilterStatus>(
        (ref) => SupplierFilterStatus.all);

final supplierDebtTransactionsProvider =
    StreamProvider.autoDispose.family<List<SupplierDebtTransaction>, String>(
        (ref, supplierId) {
  final currentStore = ref.watch(currentStoreIdProvider);
  final repo = ref.watch(supplierRepositoryProvider);
  return repo.watchDebtTransactions(supplierId, storeId: currentStore);
});

List<Supplier> _filterSuppliers(
  List<Supplier> suppliers,
  String query,
  SupplierFilterStatus filterStatus,
) {
  var result = suppliers;

  // Filter by debt status
  switch (filterStatus) {
    case SupplierFilterStatus.all:
      break;
    case SupplierFilterStatus.hasDebt:
      result = result.where((s) => s.currentDebt > 0).toList();
      break;
    case SupplierFilterStatus.noDebt:
      result = result.where((s) => s.currentDebt <= 0).toList();
      break;
  }

  // Filter by search query
  final trimmed = query.trim();
  if (trimmed.isEmpty) return result;

  final normQuery = VietnameseTextHelper.normalizeUnaccented(trimmed);
  return result.where((s) {
    final codeMatch = s.code.toLowerCase().contains(trimmed.toLowerCase());
    final phoneMatch = s.phone.contains(trimmed);
    final nameNorm = VietnameseTextHelper.normalizeUnaccented(s.name);
    final addrNorm = VietnameseTextHelper.normalizeUnaccented(s.address);
    final emailNorm = s.email.toLowerCase();

    return codeMatch ||
        phoneMatch ||
        nameNorm.contains(normQuery) ||
        addrNorm.contains(normQuery) ||
        emailNorm.contains(trimmed.toLowerCase());
  }).toList();
}

final filteredSuppliersProvider =
    Provider.autoDispose<AsyncValue<List<Supplier>>>((ref) {
  final suppliersAsync = ref.watch(supplierListNotifierProvider);
  final query = ref.watch(supplierSearchQueryProvider);
  final status = ref.watch(supplierFilterStatusProvider);

  return suppliersAsync.whenData((suppliers) {
    final filtered = _filterSuppliers(suppliers, query, status);
    final sorted = List<Supplier>.from(filtered)
      ..sort((a, b) => b.currentDebt.compareTo(a.currentDebt) != 0
          ? b.currentDebt.compareTo(a.currentDebt)
          : a.name.compareTo(b.name));
    return sorted;
  });
});

final supplierKpisProvider = Provider.autoDispose<SupplierKpis>((ref) {
  final suppliersAsync = ref.watch(supplierListNotifierProvider);
  return suppliersAsync.maybeWhen(
    data: (suppliers) {
      final totalSuppliers = suppliers.length;
      final totalPurchase =
          suppliers.fold<double>(0.0, (sum, s) => sum + s.totalPurchase);
      final totalDebt =
          suppliers.fold<double>(0.0, (sum, s) => sum + s.currentDebt);
      return SupplierKpis(
        totalSuppliers: totalSuppliers,
        totalPurchase: totalPurchase,
        totalDebt: totalDebt,
      );
    },
    orElse: () => const SupplierKpis(),
  );
});

/// Seed initial suppliers if database is completely empty
Future<void> seedSuppliers(Ref ref) async {
  try {
    final repo = ref.read(supplierRepositoryProvider);
    final currentStore = ref.read(currentStoreIdProvider);

    final initialSuppliers = [
      Supplier(
        id: 'NCC000001',
        code: 'NCC000001',
        name: 'Công ty Cổ phần Thế Giới Số (Digiworld)',
        phone: '02839291234',
        email: 'contact@digiworld.com.vn',
        address: '195 Cô Bắc, P. Cô Giang, Quận 1, TP. Hồ Chí Minh',
        taxCode: '0302861742',
        totalPurchase: 145000000,
        currentDebt: 32500000,
        note: 'Nhà phân phối chính hãng Apple, Xiaomi, HP, ASUS',
        status: 'active',
        createdAt: DateTime.now().subtract(const Duration(days: 90)).toIso8601String(),
        createdBy: 'Admin',
      ),
      Supplier(
        id: 'NCC000002',
        code: 'NCC000002',
        name: 'Công ty TNHH Synnex FPT',
        phone: '02473006666',
        email: 'distribution@synnexfpt.com.vn',
        address: 'Tòa nhà FPT Cầu Giấy, Phố Duy Tân, Cầu Giấy, Hà Nội',
        taxCode: '0103636585',
        totalPurchase: 98000000,
        currentDebt: 15200000,
        note: 'Đối tác linh kiện, laptop Dell, Asus, máy in Canon',
        status: 'active',
        createdAt: DateTime.now().subtract(const Duration(days: 60)).toIso8601String(),
        createdBy: 'Admin',
      ),
      Supplier(
        id: 'NCC000003',
        code: 'NCC000003',
        name: 'Công ty TNHH Samsung Electronics Việt Nam',
        phone: '02838217300',
        email: 'b2b.vn@samsung.com',
        address: 'Số 2 Hải Triều, P. Bến Nghé, Quận 1, TP. Hồ Chí Minh',
        taxCode: '0300401888',
        totalPurchase: 76000000,
        currentDebt: 0.0,
        note: 'Nguồn hàng Samsung Galaxy, tablet, màn hình máy tính',
        status: 'active',
        createdAt: DateTime.now().subtract(const Duration(days: 45)).toIso8601String(),
        createdBy: 'Admin',
      ),
      Supplier(
        id: 'NCC000004',
        code: 'NCC000004',
        name: 'Công ty Cổ phần Công nghệ An Phát',
        phone: '02435637003',
        email: 'kd@anphatpc.com.vn',
        address: '49 Thái Hà, Đống Đa, Hà Nội',
        taxCode: '0101569420',
        totalPurchase: 42000000,
        currentDebt: 8700000,
        note: 'Phụ kiện bàn phím, chuột, tai nghe cơ bản',
        status: 'active',
        createdAt: DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
        createdBy: 'Admin',
      ),
    ];

    for (final s in initialSuppliers) {
      await repo.upsert(s, storeId: currentStore);
      if (s.currentDebt > 0) {
        await repo.recordDebtTransaction(
          SupplierDebtTransaction(
            id: 'TX_${s.code}_INIT',
            supplierId: s.id,
            date: DateTime.now().subtract(const Duration(days: 15)),
            type: SupplierDebtType.importBill,
            amount: s.currentDebt,
            remainingDebt: s.currentDebt,
            referenceCode: 'PN_INIT_${s.code}',
            note: 'Dư nợ đầu kỳ từ đơn nhập kho gần nhất',
            createdBy: 'Hệ thống',
          ),
          storeId: currentStore,
        );
      }
    }
  } catch (_) {
    // Background seeding failure handled gracefully
  }
}
