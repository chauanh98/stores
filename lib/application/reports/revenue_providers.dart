import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../data/datasources/firebase/order_remote_data_source.dart';
import '../../data/datasources/firebase/inventory_remote_data_source.dart';
import '../../data/datasources/firebase/product_remote_data_source.dart';
import '../../data/repositories/revenue_repository_impl.dart';
import '../../domain/entities/revenue_report.dart';
import '../auth/auth_providers.dart';

final orderRemoteDataSourceProvider = Provider<OrderRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return OrderRemoteDataSource(FirebaseDatabase.instance, storeId);
});

final inventoryRemoteDataSourceProvider = Provider<InventoryRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return InventoryRemoteDataSource(FirebaseDatabase.instance, storeId);
});

final productRemoteDataSourceProvider = Provider<ProductRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return ProductRemoteDataSource(FirebaseDatabase.instance, storeId);
});

final revenueRepositoryProvider = Provider<RevenueRepositoryImpl>((ref) {
  final orderDs = ref.watch(orderRemoteDataSourceProvider);
  final inventoryDs = ref.watch(inventoryRemoteDataSourceProvider);
  final productDs = ref.watch(productRemoteDataSourceProvider);
  return RevenueRepositoryImpl(orderDs, inventoryDs, productDs);
});

// Dùng StreamProvider để tự động cập nhật khi có đơn hàng mới
final revenueByDateProvider = StreamProvider.family<RevenueReport, DateTime>((ref, date) async* {
  final repository = ref.watch(revenueRepositoryProvider);
  // Lắng nghe thay đổi orders trong ngày và map sang báo cáo
  final startOfDay = DateTime(date.year, date.month, date.day);
  final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  final ordersStream = ref.watch(orderRemoteDataSourceProvider).watchByDateRange(startOfDay, endOfDay);

  await for (final orders in ordersStream) {
    // Debug: In ra số lượng orders
    print('RevenueProvider: Found ${orders.length} orders for date ${date.toIso8601String()}');
    
    // Lấy dữ liệu inventory và products snapshot hiện tại để tính
    final inventory = await ref.watch(inventoryRemoteDataSourceProvider).watchAll().first;
    final products = await ref.watch(productRemoteDataSourceProvider).watchAll().first;
    
    print('RevenueProvider: Found ${inventory.length} inventory transactions, ${products.length} products');
    
    // Tính toán báo cáo trực tiếp với dữ liệu đã lấy được
    final report = repository.calculateRevenueReport(
      orders: orders,
      inventoryTransactions: inventory,
      products: products,
      date: date,
    );
    
    print('RevenueProvider: Generated report with revenue: ${report.totalRevenue}, cost: ${report.totalCost}, profit: ${report.profit}');
    
    yield report;
  }
});

final revenueByDateRangeProvider = StreamProvider.family<RevenueSummary, DateTimeRange>((ref, range) async* {
  final repository = ref.watch(revenueRepositoryProvider);
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
  final ordersStream = ref.watch(orderRemoteDataSourceProvider).watchByDateRange(start, end);
  
  await for (final orders in ordersStream) {
    // Lấy dữ liệu inventory và products snapshot hiện tại để tính
    final inventory = await ref.watch(inventoryRemoteDataSourceProvider).watchAll().first;
    final products = await ref.watch(productRemoteDataSourceProvider).watchAll().first;
    
    // Tính toán summary trực tiếp với dữ liệu đã lấy được
    yield await repository.getRevenueByDateRange(range.start, range.end);
  }
});