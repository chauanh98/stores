import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user_account.dart';

import '../../data/datasources/firebase/customer_remote_data_source.dart';
import '../../data/repositories/customer_repository_impl.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/customer_debt_transaction.dart';
import '../../domain/repositories/customer_repository.dart';
import '../auth/auth_providers.dart';
import '../../core/services/filter_storage_service.dart';
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

final customerDebtTransactionsProvider = StreamProvider.autoDispose
    .family<List<CustomerDebtTransaction>, String>((ref, customerId) {
  final ds = ref.watch(customerRemoteDataSourceProvider);
  return ds.watchDebtTransactions(customerId).map((list) {
    return list.map((m) => CustomerDebtTransaction.fromMap(m)).toList();
  });
});

final customerSearchQueryProvider =
    StateProvider.autoDispose<String>((ref) => '');

enum CustomerDebtFilter { all, inDebt, cleared }

final customerDebtFilterProvider = StateProvider<CustomerDebtFilter>((ref) {
  final user = ref.watch(authProvider);
  if (user != null && !user.canViewDebtSummary) return CustomerDebtFilter.all;
  if (user == null) return CustomerDebtFilter.all;

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadFilterSync('customers', user.username);
  if (saved != null && saved['debtFilter'] != null) {
    return CustomerDebtFilter.values.firstWhere(
      (e) => e.name == saved['debtFilter']?.toString(),
      orElse: () => CustomerDebtFilter.all,
    );
  }
  return CustomerDebtFilter.all;
});

/// Centralized persistence for all Customer filters.
/// Ensures debt status, time range, and custom date range (if active)
/// are always saved together without clobbering one another.
void persistCustomerFilters(
  dynamic ref, {
  CustomerDebtFilter? debtFilter,
  OverviewTimeRange? timeRangeType,
  bool resetTimeRange = false,
  DateTimeRange? customDateRange,
}) {
  final user = ref.read(authProvider) as UserAccount?;
  if (user == null) return;
  final storage =
      ref.read(filterStorageServiceProvider) as FilterStorageService;
  final canViewDebt = user.canViewDebtSummary;
  final activeDebt = canViewDebt
      ? (debtFilter ??
          (ref.read(customerDebtFilterProvider.notifier).state
              as CustomerDebtFilter))
      : CustomerDebtFilter.all;
  final OverviewTimeRange? activeTimeRange = resetTimeRange
      ? null
      : (timeRangeType ??
          (ref.read(customerTimeRangeTypeProvider.notifier).state
              as OverviewTimeRange?));
  final DateTimeRange activeCustomRange = customDateRange ??
      (ref.read(customerCustomDateRangeProvider.notifier).state
          as DateTimeRange);

  storage.saveFilter(
      'customers',
      {
        'version': 1,
        'debtFilter': activeDebt.name,
        'timeRangeType': activeTimeRange?.name,
        if (activeTimeRange == OverviewTimeRange.custom) ...{
          'customStartDate': activeCustomRange.start.toIso8601String(),
          'customEndDate': activeCustomRange.end.toIso8601String(),
        },
      },
      user.username);
}

final customerDebtCountsProvider =
    Provider.autoDispose<Map<CustomerDebtFilter, int>>((ref) {
  final customersAsync = ref.watch(customerListNotifierProvider);
  final searchQuery = ref.watch(customerSearchQueryProvider);
  final activeRange = ref.watch(customerActiveDateRangeProvider);
  final user = ref.watch(authProvider);

  return customersAsync.maybeWhen(
    data: (customers) {
      var scoped = customers;
      if (user != null && user.isStaff) {
        scoped =
            scoped.where((c) => _matchesStaffStore(c, user.storeId)).toList();
      }

      var filtered = _filterCustomers(scoped, searchQuery);

      if (activeRange != null) {
        filtered = filtered.where((c) {
          final date = _getCustomerEffectiveDate(c);
          if (date == null) return false;
          return !date.isBefore(activeRange.start) &&
              !date.isAfter(activeRange.end);
        }).toList();
      }

      final allCount = filtered.length;
      if (user != null && !user.canViewDebtSummary) {
        return {
          CustomerDebtFilter.all: allCount,
          CustomerDebtFilter.inDebt: 0,
          CustomerDebtFilter.cleared: 0,
        };
      }

      final inDebtCount =
          filtered.where((c) => (c.currentDebt ?? 0) > 0).length;
      final clearedCount =
          filtered.where((c) => (c.currentDebt ?? 0) <= 0).length;

      return {
        CustomerDebtFilter.all: allCount,
        CustomerDebtFilter.inDebt: inDebtCount,
        CustomerDebtFilter.cleared: clearedCount,
      };
    },
    orElse: () => {
      CustomerDebtFilter.all: 0,
      CustomerDebtFilter.inDebt: 0,
      CustomerDebtFilter.cleared: 0,
    },
  );
});

DateTime? _parseCustomerDate(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return null;
  final parsedIso = DateTime.tryParse(dateStr);
  if (parsedIso != null) return parsedIso;

  try {
    final parts = dateStr.trim().split(' ');
    final dateParts = parts[0].split('/');
    if (dateParts.length == 3) {
      final day = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final year = int.parse(dateParts[2]);
      int hour = 0;
      int minute = 0;
      if (parts.length > 1) {
        final timeParts = parts[1].split(':');
        if (timeParts.length >= 2) {
          hour = int.parse(timeParts[0]);
          minute = int.parse(timeParts[1]);
        }
      }
      return DateTime(year, month, day, hour, minute);
    }
  } catch (_) {}

  final numVal = int.tryParse(dateStr);
  if (numVal != null) {
    return DateTime.fromMillisecondsSinceEpoch(numVal);
  }

  return null;
}

DateTime? _getCustomerEffectiveDate(Customer c) {
  return _parseCustomerDate(c.createdAt) ??
      _parseCustomerDate(c.lastTransactionDate);
}

String _formatCustomerDate(String? dateStr) {
  final dt = _parseCustomerDate(dateStr);
  if (dt != null) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
  return 'Chưa rõ ngày';
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

bool _matchesStaffStore(Customer c, String userStoreId) {
  final userStore = userStoreId.trim().toLowerCase();
  final custBranch = (c.branch ?? '').trim().toLowerCase();

  // If customer has no branch specified, fallback default is store_001 / Chi nhánh Đông Thắng
  if (custBranch.isEmpty) {
    return userStore == 'store_001' ||
        userStore.isEmpty ||
        userStore == 'branch_1' ||
        userStore == 'đt' ||
        userStore == 'dt' ||
        userStore.contains('đông thắng') ||
        userStore.contains('dong thang');
  }

  // Exact ID match
  if (custBranch == userStore) return true;

  // Known branch alias matches: store_001 / Chi nhánh Đông Thắng (ĐT)
  if (userStore == 'store_001' ||
      userStore == 'branch_1' ||
      userStore == 'đt' ||
      userStore == 'dt' ||
      userStore.contains('đông thắng') ||
      userStore.contains('dong thang')) {
    if (custBranch == 'store_001' ||
        custBranch == 'branch_1' ||
        custBranch == 'đt' ||
        custBranch == 'dt' ||
        custBranch.contains('đông thắng') ||
        custBranch.contains('dong thang')) {
      return true;
    }
  } else if (userStore == 'store_002' ||
      userStore == 'branch_2' ||
      userStore == 'tb' ||
      userStore.contains('thới bình') ||
      userStore.contains('thoi binh') ||
      userStore.contains('thời bình')) {
    if (custBranch == 'store_002' ||
        custBranch == 'branch_2' ||
        custBranch == 'tb' ||
        custBranch.contains('thới bình') ||
        custBranch.contains('thoi binh') ||
        custBranch.contains('thời bình')) {
      return true;
    }
  } else {
    // Generic match on custom storeId
    if (custBranch.contains(userStore)) return true;
  }

  return false;
}

final processedCustomersProvider =
    Provider.autoDispose<AsyncValue<List<dynamic>>>((ref) {
  final customersAsync = ref.watch(customerListNotifierProvider);
  final searchQuery = ref.watch(customerSearchQueryProvider);
  final activeRange = ref.watch(customerActiveDateRangeProvider);
  final debtFilter = ref.watch(customerDebtFilterProvider);
  final user = ref.watch(authProvider);

  return customersAsync.whenData((customers) {
    var scoped = customers;
    if (user != null && user.isStaff) {
      scoped =
          scoped.where((c) => _matchesStaffStore(c, user.storeId)).toList();
    }

    var filtered = _filterCustomers(scoped, searchQuery);

    if (activeRange != null) {
      filtered = filtered.where((c) {
        final date = _getCustomerEffectiveDate(c);
        if (date == null) return false;
        return !date.isBefore(activeRange.start) &&
            !date.isAfter(activeRange.end);
      }).toList();
    }

    final canViewDebt = user == null || user.canViewDebtSummary;
    final effectiveDebtFilter =
        canViewDebt ? debtFilter : CustomerDebtFilter.all;

    switch (effectiveDebtFilter) {
      case CustomerDebtFilter.all:
        final sorted = List<Customer>.from(filtered)
          ..sort((a, b) {
            final ad = _getCustomerEffectiveDate(a);
            final bd = _getCustomerEffectiveDate(b);
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return bd.compareTo(ad);
          });

        final grouped = <String, List<Customer>>{};
        for (final customer in sorted) {
          final dateKey = _formatCustomerDate(
              customer.createdAt ?? customer.lastTransactionDate);
          grouped.putIfAbsent(dateKey, () => []).add(customer);
        }

        final listItems = <dynamic>[];
        for (final entry in grouped.entries) {
          listItems.add(entry.key);
          listItems.addAll(entry.value);
        }

        return listItems;

      case CustomerDebtFilter.inDebt:
        final inDebtList = filtered
            .where((c) => (c.currentDebt ?? 0) > 0)
            .toList()
          ..sort(
              (a, b) => b.displayCurrentDebt.compareTo(a.displayCurrentDebt));
        return inDebtList;

      case CustomerDebtFilter.cleared:
        final clearedList =
            filtered.where((c) => (c.currentDebt ?? 0) <= 0).toList();
        final sorted = List<Customer>.from(clearedList)
          ..sort((a, b) {
            final ad = _getCustomerEffectiveDate(a);
            final bd = _getCustomerEffectiveDate(b);
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return bd.compareTo(ad);
          });

        final grouped = <String, List<Customer>>{};
        for (final customer in sorted) {
          final dateKey = _formatCustomerDate(
              customer.createdAt ?? customer.lastTransactionDate);
          grouped.putIfAbsent(dateKey, () => []).add(customer);
        }

        final listItems = <dynamic>[];
        for (final entry in grouped.entries) {
          listItems.add(entry.key);
          listItems.addAll(entry.value);
        }

        return listItems;
    }
  });
});

// Helper function to seed customers from specific branches if shared_customers is empty
Future<void> seedCustomers(Ref ref) async {
  try {
    final repo = ref.read(customerRepositoryProvider);
    final targetStores = ['store_001', 'store_002'];

    for (final storeId in targetStores) {
      final snap = await FirebaseDatabase.instance
          .ref('stores/$storeId/customers')
          .get();

      if (snap.exists && snap.value != null) {
        final customersData = snap.value;
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
