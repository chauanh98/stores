import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/firebase/customer_remote_data_source.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/import_result.dart';
import '../../../domain/repositories/customer_repository.dart';
import '../customers_providers.dart';

final importCustomersUseCaseProvider = Provider<ImportCustomersUseCase>((ref) {
  return ImportCustomersUseCase(
    customerRepository: ref.watch(customerRepositoryProvider),
    customerDataSource: ref.watch(customerRemoteDataSourceProvider),
  );
});

class ImportCustomersUseCase {
  final CustomerRepository customerRepository;
  final CustomerRemoteDataSource? customerDataSource;

  ImportCustomersUseCase({
    required this.customerRepository,
    this.customerDataSource,
  });

  /// Normalizes phone digits: strips non-digits, normalizes +84/84 prefix to 0
  static String normalizePhone(String? phone) {
    if (phone == null) return '';
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('84') && digits.length >= 10) {
      digits = '0${digits.substring(2)}';
    } else if (digits.length == 9 && !digits.startsWith('0')) {
      digits = '0$digits';
    }
    return digits;
  }

  Future<ImportResult> execute({
    required List<Customer> customers,
  }) async {
    if (customers.isEmpty) {
      return const ImportResult();
    }

    int added = 0;
    int updated = 0;
    int skipped = 0;
    int errors = 0;
    final List<String> errorMessages = [];

    // 1. Fetch existing customers to build lookup index
    List<Customer> existingCustomers = [];
    try {
      existingCustomers = await customerRepository.watchAll().first.timeout(
            const Duration(seconds: 4),
            onTimeout: () => <Customer>[],
          );
    } catch (_) {
      existingCustomers = [];
    }

    final Map<String, Customer> idMap = {};
    final Map<String, Customer> phoneMap = {};

    for (final c in existingCustomers) {
      final idKey = c.id.trim().toLowerCase();
      if (idKey.isNotEmpty) idMap[idKey] = c;

      final p = normalizePhone(c.phone);
      if (p.length >= 8) phoneMap[p] = c;
    }

    // 2. Process imported customers
    for (final imported in customers) {
      try {
        final importedId = imported.id.trim().toLowerCase();
        final importedPhone = normalizePhone(imported.phone);

        Customer? existing;
        if (importedId.isNotEmpty && idMap.containsKey(importedId)) {
          existing = idMap[importedId];
        } else if (importedPhone.length >= 8 &&
            phoneMap.containsKey(importedPhone)) {
          existing = phoneMap[importedPhone];
        }

        // Secondary fallback to single-lookup if prefetch was empty or missing
        if (existing == null && importedId.isNotEmpty) {
          try {
            existing = await customerRepository.fetchById(imported.id);
          } catch (_) {}
        }

        if (existing != null) {
          // DUPLICATE DETECTED:
          // Update contact info (name, address, email, group, notes, etc.)
          // STRICTLY PRESERVE purchases, currentDebt, totalSales, netSales.
          final mergedCustomer = existing.copyWith(
            name:
                imported.name.trim().isNotEmpty ? imported.name : existing.name,
            phone: imported.phone.trim().isNotEmpty
                ? imported.phone
                : existing.phone,
            address: imported.address.trim().isNotEmpty
                ? imported.address
                : existing.address,
            email: imported.email.trim().isNotEmpty
                ? imported.email
                : existing.email,
            group: imported.group ?? existing.group,
            notes: imported.notes ?? existing.notes,
            type: imported.type ?? existing.type,
            branch: imported.branch ?? existing.branch,
            deliveryArea: imported.deliveryArea ?? existing.deliveryArea,
            ward: imported.ward ?? existing.ward,
            company: imported.company ?? existing.company,
            taxCode: imported.taxCode ?? existing.taxCode,
            identityCard: imported.identityCard ?? existing.identityCard,
            dob: imported.dob ?? existing.dob,
            gender: imported.gender ?? existing.gender,
            facebook: imported.facebook ?? existing.facebook,
            status: imported.status ?? existing.status,
            // Strictly preserved:
            id: existing.id,
            purchases: existing.purchases,
            currentDebt: existing.currentDebt,
            totalSales: existing.totalSales,
            netSales: existing.netSales,
            createdAt: existing.createdAt,
            createdBy: existing.createdBy,
            lastTransactionDate: existing.lastTransactionDate,
          );

          await customerRepository.upsert(mergedCustomer);

          // Update indices
          final updatedId = mergedCustomer.id.trim().toLowerCase();
          if (updatedId.isNotEmpty) idMap[updatedId] = mergedCustomer;
          final updatedPhone = normalizePhone(mergedCustomer.phone);
          if (updatedPhone.length >= 8) phoneMap[updatedPhone] = mergedCustomer;

          updated++;
        } else {
          // NEW CUSTOMER:
          await customerRepository.upsert(imported);

          final newId = imported.id.trim().toLowerCase();
          if (newId.isNotEmpty) idMap[newId] = imported;
          final newPhone = normalizePhone(imported.phone);
          if (newPhone.length >= 8) phoneMap[newPhone] = imported;

          added++;
        }
      } catch (e) {
        errors++;
        errorMessages
            .add('Lỗi tại khách hàng ${imported.id} (${imported.name}): $e');
      }
    }

    return ImportResult(
      total: customers.length,
      added: added,
      updated: updated,
      skipped: skipped,
      errors: errors,
      errorMessages: errorMessages,
    );
  }
}
