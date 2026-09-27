import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/vietnamese_text_helper.dart';
import '../../data/datasources/firebase/supplier_remote_data_source.dart';
import '../../data/repositories/supplier_repository_impl.dart';
import '../../domain/entities/supplier.dart';
import '../../domain/entities/supplier_debt_transaction.dart';
import '../../domain/repositories/supplier_repository.dart';
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

final supplierDebtTransactionsProvider = StreamProvider.autoDispose
    .family<List<SupplierDebtTransaction>, String>((ref, supplierId) {
  final repo = ref.watch(supplierRepositoryProvider);
  return repo.watchDebtTransactions(supplierId);
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
  // Production suppliers are stored in 'shared_suppliers'.
  // We avoid seeding dummy consumer electronics data.
}
