import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/core/services/filter_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FilterStorageService Key Resolution', () {
    test('resolveKey correctly prefixes domain names', () {
      expect(FilterStorageService.resolveKey('invoices'),
          FilterStorageService.invoicesKey);
      expect(FilterStorageService.resolveKey('customers'),
          FilterStorageService.customersKey);
      expect(FilterStorageService.resolveKey('products'),
          FilterStorageService.productsKey);
    });

    test('resolveKey leaves already-prefixed keys untouched', () {
      expect(
        FilterStorageService.resolveKey('filter_prefs_invoices'),
        'filter_prefs_invoices',
      );
      expect(
        FilterStorageService.resolveKey('filter_prefs_custom'),
        'filter_prefs_custom',
      );
    });

    test('resolveKey correctly creates user-scoped keys', () {
      expect(
        FilterStorageService.resolveKey('invoices', 'admin1'),
        'filter_prefs_admin1_invoices',
      );
      expect(
        FilterStorageService.resolveKey('customers', 'staff1'),
        'filter_prefs_staff1_customers',
      );
      expect(
        FilterStorageService.resolveKey('products', 'admin1'),
        'filter_prefs_admin1_products',
      );
      expect(
        FilterStorageService.resolveKey('filter_prefs_invoices', 'admin1'),
        'filter_prefs_admin1_invoices',
      );
      expect(
        FilterStorageService.resolveKey('filter_prefs_admin1_invoices', 'admin1'),
        'filter_prefs_admin1_invoices',
      );
      // Re-scoping from another user's key
      expect(
        FilterStorageService.resolveKey('filter_prefs_staff1_invoices', 'admin1'),
        'filter_prefs_admin1_invoices',
      );
    });

    test('resolveStoreKey creates user-scoped store key and sanitizes special characters', () {
      expect(
        FilterStorageService.resolveStoreKey('admin1'),
        'selected_store_admin1',
      );
      expect(
        FilterStorageService.resolveStoreKey('staff_pos'),
        'selected_store_staff_pos',
      );
      expect(
        FilterStorageService.resolveKey('selected_store', 'admin1'),
        'selected_store_admin1',
      );
      expect(
        FilterStorageService.resolveKey('selected_store_admin1', 'admin1'),
        'selected_store_admin1',
      );
      // Whitespace and empty fallback
      expect(
        FilterStorageService.resolveStoreKey('   '),
        'selected_store',
      );
      expect(
        FilterStorageService.resolveStoreKey(''),
        'selected_store',
      );
      // Special characters sanitization
      expect(
        FilterStorageService.resolveStoreKey('admin 01'),
        'selected_store_admin%2001',
      );
      expect(
        FilterStorageService.resolveStoreKey('store/admin'),
        'selected_store_store%2Fadmin',
      );
      expect(
        FilterStorageService.resolveStoreKey('user.name'),
        'selected_store_user%2Ename',
      );
    });
  });

  group('FilterStorageService with SharedPreferences', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'filter_prefs_invoices': jsonEncode({
          'status': 'completed',
          'paymentMethod': 'transfer',
        }),
      });
    });

    test('hydrates pre-existing values from SharedPreferences', () async {
      final service = FilterStorageService();
      final filters = await service.loadFilter('invoices');

      expect(filters, isNotNull);
      expect(filters?['status'], 'completed');
      expect(filters?['paymentMethod'], 'transfer');
    });

    test('saves and reloads filters across domains', () async {
      final service = FilterStorageService();

      await service.saveFilter('customers', {
        'debtFilter': 'inDebt',
        'timeRangeType': 'thisMonth',
      });

      final loaded = await service.loadFilter('customers');
      expect(loaded, isNotNull);
      expect(loaded?['debtFilter'], 'inDebt');
      expect(loaded?['timeRangeType'], 'thisMonth');

      // Verify it was actually written to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('filter_prefs_customers');
      expect(raw, isNotNull);
      expect(jsonDecode(raw!), containsPair('debtFilter', 'inDebt'));
    });

    test('clears filters from SharedPreferences and memory', () async {
      final service = FilterStorageService();
      await service.saveFilter('products', {
        'category': 'Electronics',
        'stockStatus': 'inStock',
      });

      expect(await service.loadFilter('products'), isNotNull);

      await service.clearFilter('products');
      expect(await service.loadFilter('products'), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filter_prefs_products'), isFalse);
    });

    test('sync read returns value once loaded into memory', () async {
      final service = FilterStorageService();
      await service.loadFilter('invoices');

      final syncValue = service.loadFilterSync('invoices');
      expect(syncValue, isNotNull);
      expect(syncValue?['status'], 'completed');
    });
  });

  group('FilterStorageService User-Scoped Store Persistence', () {
    test('persists, hydrates, and clears selected store per user', () async {
      SharedPreferences.setMockInitialValues({});
      final serviceAdmin = FilterStorageService(null, 'admin1');
      final serviceStaff = FilterStorageService(null, 'staff1');

      // Admin selects store_002
      await serviceAdmin.saveSelectedStore('store_002');

      // Admin sees store_002
      expect(await serviceAdmin.loadSelectedStore(), 'store_002');
      expect(serviceAdmin.loadSelectedStoreSync(), 'store_002');

      // Staff sees null (not contaminated by admin)
      expect(await serviceStaff.loadSelectedStore(), isNull);
      expect(serviceStaff.loadSelectedStoreSync(), isNull);

      // Verify SharedPreferences key
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_store_admin1'), 'store_002');
      expect(prefs.containsKey('selected_store_staff1'), isFalse);

      // Clear admin store
      await serviceAdmin.clearSelectedStore();
      expect(await serviceAdmin.loadSelectedStore(), isNull);
      expect(prefs.containsKey('selected_store_admin1'), isFalse);
    });

    test('rejects empty or whitespace usernames from saving or loading selected store', () async {
      SharedPreferences.setMockInitialValues({});
      final service = FilterStorageService(null, '   ');

      expect(await service.saveSelectedStore('store_002'), isFalse);
      expect(await service.loadSelectedStore(), isNull);
      expect(service.loadSelectedStoreSync(), isNull);
      expect(await service.clearSelectedStore(), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('selected_store'), isFalse);
      expect(prefs.containsKey('selected_store_   '), isFalse);
    });
  });

  group('FilterStorageService Multi-Account Filter Isolation', () {
    test('filters are completely isolated between user accounts (zero contamination)', () async {
      SharedPreferences.setMockInitialValues({});
      final serviceAdmin = FilterStorageService(null, 'admin1');
      final serviceStaff = FilterStorageService(null, 'staff1');

      // Admin saves invoice filter: status = 'debt'
      await serviceAdmin.saveFilter('invoices', {
        'status': 'debt',
        'paymentMethod': 'transfer',
      });

      // Staff saves customer filter: debtFilter = 'inDebt'
      await serviceStaff.saveFilter('customers', {
        'debtFilter': 'inDebt',
      });

      // Verify SharedPreferences has user-scoped keys
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('filter_prefs_admin1_invoices'), isTrue);
      expect(prefs.containsKey('filter_prefs_staff1_customers'), isTrue);

      // Staff does NOT see admin's invoice filter
      final staffInvoices = await serviceStaff.loadFilter('invoices');
      expect(staffInvoices, isNull);

      // Admin does NOT see staff's customer filter
      final adminCustomers = await serviceAdmin.loadFilter('customers');
      expect(adminCustomers, isNull);

      // Admin loads own invoices filter correctly
      final adminInvoices = await serviceAdmin.loadFilter('invoices');
      expect(adminInvoices?['status'], 'debt');
    });
  });

  group('FilterStorageService In-Memory Fallback', () {
    test('operates safely purely in-memory without error', () async {
      final service = FilterStorageService();

      await service.saveFilter('test_domain', {'key': 'value'});
      final loaded = await service.loadFilter('test_domain');
      expect(loaded, {'key': 'value'});

      expect(service.loadFilterSync('test_domain'), {'key': 'value'});

      await service.clearFilter('test_domain');
      expect(await service.loadFilter('test_domain'), isNull);
    });
  });

  group('filterStorageServiceProvider', () {
    test('provides a singleton or functional service via Riverpod container', () {
      final container = ProviderContainer();
      final service = container.read(filterStorageServiceProvider);
      expect(service, isA<FilterStorageService>());
      container.dispose();
    });
  });
}
