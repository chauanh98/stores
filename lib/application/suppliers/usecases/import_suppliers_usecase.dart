import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/import_result.dart';
import '../../../domain/entities/supplier.dart';
import '../../../domain/repositories/supplier_repository.dart';
import '../suppliers_providers.dart';

final importSuppliersUseCaseProvider = Provider<ImportSuppliersUseCase>((ref) {
  return ImportSuppliersUseCase(
    supplierRepository: ref.watch(supplierRepositoryProvider),
  );
});

class ImportSuppliersUseCase {
  final SupplierRepository supplierRepository;

  ImportSuppliersUseCase({
    required this.supplierRepository,
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
    required List<Supplier> suppliers,
    String? targetStoreId,
  }) async {
    if (suppliers.isEmpty) {
      return const ImportResult();
    }

    int added = 0;
    int updated = 0;
    int skipped = 0;
    int errors = 0;
    final List<String> errorMessages = [];

    // 1. Fetch existing suppliers for the target store / all stores
    List<Supplier> existingSuppliers = [];
    try {
      existingSuppliers = await supplierRepository
          .watchAll(storeId: targetStoreId)
          .first
          .timeout(
            const Duration(seconds: 4),
            onTimeout: () => <Supplier>[],
          );
    } catch (_) {
      existingSuppliers = [];
    }

    final Map<String, Supplier> idMap = {};
    final Map<String, Supplier> codeMap = {};
    final Map<String, Supplier> phoneMap = {};

    for (final s in existingSuppliers) {
      final idKey = s.id.trim().toLowerCase();
      if (idKey.isNotEmpty) idMap[idKey] = s;

      final codeKey = s.code.trim().toLowerCase();
      if (codeKey.isNotEmpty) codeMap[codeKey] = s;

      final p = normalizePhone(s.phone);
      if (p.length >= 8) phoneMap[p] = s;
    }

    // 2. Process imported suppliers
    for (final imported in suppliers) {
      try {
        final importedId = imported.id.trim().toLowerCase();
        final importedCode = imported.code.trim().toLowerCase();
        final importedPhone = normalizePhone(imported.phone);

        Supplier? existing;
        if (importedId.isNotEmpty && idMap.containsKey(importedId)) {
          existing = idMap[importedId];
        } else if (importedCode.isNotEmpty &&
            codeMap.containsKey(importedCode)) {
          existing = codeMap[importedCode];
        } else if (importedId.isNotEmpty && codeMap.containsKey(importedId)) {
          existing = codeMap[importedId];
        } else if (importedCode.isNotEmpty && idMap.containsKey(importedCode)) {
          existing = idMap[importedCode];
        } else if (importedPhone.length >= 8 &&
            phoneMap.containsKey(importedPhone)) {
          existing = phoneMap[importedPhone];
        }

        // Secondary fallback to fetchById
        if (existing == null && importedId.isNotEmpty) {
          try {
            existing = await supplierRepository.fetchById(imported.id,
                storeId: targetStoreId);
          } catch (_) {}
        }

        if (existing != null) {
          // DUPLICATE DETECTED:
          // Update contact info and note
          // STRICTLY PRESERVE currentDebt and totalPurchase
          final mergedSupplier = existing.copyWith(
            name:
                imported.name.trim().isNotEmpty ? imported.name : existing.name,
            phone: imported.phone.trim().isNotEmpty
                ? imported.phone
                : existing.phone,
            email: imported.email.trim().isNotEmpty
                ? imported.email
                : existing.email,
            address: imported.address.trim().isNotEmpty
                ? imported.address
                : existing.address,
            taxCode: imported.taxCode ?? existing.taxCode,
            note: imported.note ?? existing.note,
            status: imported.status.trim().isNotEmpty
                ? imported.status
                : existing.status,
            branch: imported.branch ?? existing.branch,
            // Strictly preserve key identities:
            id: existing.id,
            code: existing.code,
            // Update if imported provides positive balance, otherwise preserve existing
            currentDebt: imported.currentDebt > 0
                ? imported.currentDebt
                : existing.currentDebt,
            totalPurchase: imported.totalPurchase > 0
                ? imported.totalPurchase
                : existing.totalPurchase,
            createdAt: existing.createdAt,
            createdBy: existing.createdBy,
          );

          await supplierRepository.upsert(mergedSupplier,
              storeId: targetStoreId);

          // Update indices
          final updatedId = mergedSupplier.id.trim().toLowerCase();
          if (updatedId.isNotEmpty) idMap[updatedId] = mergedSupplier;
          final updatedCode = mergedSupplier.code.trim().toLowerCase();
          if (updatedCode.isNotEmpty) codeMap[updatedCode] = mergedSupplier;
          final updatedPhone = normalizePhone(mergedSupplier.phone);
          if (updatedPhone.length >= 8) phoneMap[updatedPhone] = mergedSupplier;

          updated++;
        } else {
          // NEW SUPPLIER:
          await supplierRepository.upsert(imported, storeId: targetStoreId);

          final newId = imported.id.trim().toLowerCase();
          if (newId.isNotEmpty) idMap[newId] = imported;
          final newCode = imported.code.trim().toLowerCase();
          if (newCode.isNotEmpty) codeMap[newCode] = imported;
          final newPhone = normalizePhone(imported.phone);
          if (newPhone.length >= 8) phoneMap[newPhone] = imported;

          added++;
        }
      } catch (e) {
        errors++;
        errorMessages.add(
            'Lỗi tại nhà cung cấp ${imported.code.isNotEmpty ? imported.code : imported.id} (${imported.name}): $e');
      }
    }

    return ImportResult(
      total: suppliers.length,
      added: added,
      updated: updated,
      skipped: skipped,
      errors: errors,
      errorMessages: errorMessages,
    );
  }
}
