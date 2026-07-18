import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firebase/inventory_remote_data_source.dart';
import '../../data/repositories/inventory_repository_impl.dart';
import '../../domain/entities/inventory_transaction.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../auth/auth_providers.dart';

final inventoryRemoteDataSourceProvider =
    Provider<InventoryRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return InventoryRemoteDataSource(FirebaseDatabase.instance, storeId);
});

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  final ds = ref.watch(inventoryRemoteDataSourceProvider);
  return InventoryRepositoryImpl(ds);
});

// Selected date (day) for filtering imports
final selectedImportDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

// Filter mode: single day or custom range
enum ImportFilterMode { day, range }

final importFilterModeProvider = StateProvider<ImportFilterMode>((ref) {
  return ImportFilterMode.day;
});

// Selected custom range
final selectedImportRangeProvider = StateProvider<TupleDateRange>((ref) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day, 0, 0, 0);
  final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  return TupleDateRange(start, end);
});

class TupleDateRange {
  final DateTime start;
  final DateTime end;

  const TupleDateRange(this.start, this.end);
}

// Unified stream depending on mode
final importsFilteredProvider =
    StreamProvider.autoDispose<List<InventoryTransaction>>((ref) {
  final repository = ref.watch(inventoryRepositoryProvider);
  final mode = ref.watch(importFilterModeProvider);
  if (mode == ImportFilterMode.day) {
    final selected = ref.watch(selectedImportDateProvider);
    final start =
        DateTime(selected.year, selected.month, selected.day, 0, 0, 0);
    final end =
        DateTime(selected.year, selected.month, selected.day, 23, 59, 59, 999);
    return repository.watchImportsByDateRange(start, end);
  } else {
    final range = ref.watch(selectedImportRangeProvider);
    return repository.watchImportsByDateRange(range.start, range.end);
  }
});

// Transactions by product
final transactionsByProductProvider = StreamProvider.family
    .autoDispose<List<InventoryTransaction>, String>((ref, productId) {
  final repository = ref.watch(inventoryRepositoryProvider);
  return repository.watchByProduct(productId);
});
