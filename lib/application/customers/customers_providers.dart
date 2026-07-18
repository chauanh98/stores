import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firebase/customer_remote_data_source.dart';
import '../../data/repositories/customer_repository_impl.dart';
import '../../domain/entities/customer.dart';
import '../../domain/repositories/customer_repository.dart';
import '../reports/overview_providers.dart';
import 'customer_list_notifier.dart';

final customerRemoteDataSourceProvider =
    Provider<CustomerRemoteDataSource>((ref) {
  return CustomerRemoteDataSource(FirebaseDatabase.instance);
});

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  final ds = ref.watch(customerRemoteDataSourceProvider);
  return CustomerRepositoryImpl(ds);
});

final customerListNotifierProvider =
    AutoDisposeAsyncNotifierProvider<CustomerListNotifier, List<Customer>>(
  CustomerListNotifier.new,
);

final customerSearchQueryProvider =
    StateProvider.autoDispose<String>((ref) => '');

DateTime? _parseCustomerDate(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return null;
  return DateTime.tryParse(dateStr);
}

String _formatCustomerDate(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return 'Không rõ ngày tạo';
  final dt = DateTime.tryParse(dateStr);
  if (dt != null) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
  return dateStr;
}

List<Customer> _filterCustomers(List<Customer> customers, String query) {
  final trimmedQuery = query.trim();
  if (trimmedQuery.isEmpty) return customers;

  final lowercaseQuery = trimmedQuery.toLowerCase();
  return customers.where((customer) {
    return customer.name.toLowerCase().contains(lowercaseQuery) ||
        customer.phone.toLowerCase().contains(lowercaseQuery) ||
        customer.email.toLowerCase().contains(lowercaseQuery) ||
        customer.address.toLowerCase().contains(lowercaseQuery);
  }).toList();
}

final processedCustomersProvider =
    Provider.autoDispose<AsyncValue<List<dynamic>>>((ref) {
  final customersAsync = ref.watch(customerListNotifierProvider);
  final searchQuery = ref.watch(customerSearchQueryProvider);
  final activeRange = ref.watch(customerActiveDateRangeProvider);

  return customersAsync.whenData((customers) {
    var filtered = _filterCustomers(customers, searchQuery);

    if (activeRange != null) {
      filtered = filtered.where((c) {
        final date = _parseCustomerDate(c.createdAt);
        if (date == null) return false;
        return !date.isBefore(activeRange.start) &&
            !date.isAfter(activeRange.end);
      }).toList();
    }

    final sorted = List<Customer>.from(filtered)
      ..sort((a, b) {
        final ad = _parseCustomerDate(a.createdAt);
        final bd = _parseCustomerDate(b.createdAt);
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

    final grouped = <String, List<Customer>>{};
    for (final customer in sorted) {
      final dateKey = _formatCustomerDate(customer.createdAt);
      grouped.putIfAbsent(dateKey, () => []).add(customer);
    }

    final listItems = <dynamic>[];
    for (final entry in grouped.entries) {
      listItems.add(entry.key);
      listItems.addAll(entry.value);
    }

    return listItems;
  });
});

// Helper function to seed customers from all stores if shared_customers is empty
Future<void> seedCustomers(Ref ref) async {
  try {
    final repo = ref.read(customerRepositoryProvider);
    final storesSnap = await FirebaseDatabase.instance.ref('stores').get();

    if (storesSnap.exists && storesSnap.value != null) {
      final storesMap = Map<String, dynamic>.from(storesSnap.value as Map);
      for (final entry in storesMap.entries) {
        if (entry.key == 'accounts') continue;
        final storeData = Map<String, dynamic>.from(entry.value as Map);
        final customersData = storeData['customers'];
        if (customersData == null) continue;

        final Map customersMap = customersData is List
            ? customersData.asMap()
            : Map.from(customersData as Map);

        for (final custVal in customersMap.values) {
          if (custVal == null) continue;
          final custMap = Map.from(custVal as Map);

          final customer = Customer(
            id: custMap['id']?.toString() ?? '',
            name: custMap['name']?.toString() ?? '',
            phone: custMap['phone']?.toString() ?? '',
            email: custMap['email']?.toString() ?? '',
            address: custMap['address']?.toString() ?? '',
            purchases: const [],
            type: custMap['type']?.toString(),
            branch: custMap['branch']?.toString(),
            deliveryArea: custMap['deliveryArea']?.toString(),
            ward: custMap['ward']?.toString(),
            company: custMap['company']?.toString(),
            taxCode: custMap['taxCode']?.toString(),
            identityCard: custMap['identityCard']?.toString(),
            dob: custMap['dob']?.toString(),
            gender: custMap['gender']?.toString(),
            facebook: custMap['facebook']?.toString(),
            group: custMap['group']?.toString(),
            notes: custMap['notes']?.toString(),
            createdBy: custMap['createdBy']?.toString(),
            createdAt: custMap['createdAt']?.toString(),
            lastTransactionDate: custMap['lastTransactionDate']?.toString(),
            currentDebt: custMap['currentDebt'] != null
                ? (custMap['currentDebt'] as num).toDouble()
                : null,
            totalSales: custMap['totalSales'] != null
                ? (custMap['totalSales'] as num).toDouble()
                : null,
            netSales: custMap['netSales'] != null
                ? (custMap['netSales'] as num).toDouble()
                : null,
            status: custMap['status']?.toString() ?? '1',
          );

          if (customer.id.isNotEmpty && customer.name.isNotEmpty) {
            await repo.upsert(customer);
          }
        }
      }
    }
  } catch (_) {
    // Fail silently on background seeding
  }
}
