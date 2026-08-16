# Clean Architecture Guidelines for Flutter

## 1. Separation of Concerns & Layer Independence

```text
       ┌────────────────────────┐
       │   Presentation Layer   │  (Widgets, Controllers, Riverpod Notifiers)
       └───────────┬────────────┘
                   │ depends on
       ┌───────────▼────────────┐
       │   Application Layer    │  (Use Cases, Business Services)
       └───────────┬────────────┘
                   │ depends on
       ┌───────────▼────────────┐
       │      Domain Layer      │  (Pure Dart: Entities, Repository Interfaces)
       └───────────▲────────────┘
                   │ implemented by
       ┌───────────┴────────────┐
       │       Data Layer       │  (Firebase, Local Storage, Models/DTOs)
       └────────────────────────┘
```

### Layer Rules:

1. **Domain Layer (`lib/domain/`)**:
   - MUST be completely agnostic of UI frameworks and external data sources.
   - **Forbidden**: `import 'package:flutter/material.dart';`, `import 'package:firebase_...';`, `import 'package:flutter_riverpod/flutter_riverpod.dart';`.
   - Contains:
     - `entities/`: Immutable business models.
     - `repositories/`: Abstract repository contracts (interfaces).

   ```dart
   // lib/domain/repositories/invoice_repository.dart
   abstract interface class InvoiceRepository {
     Future<List<Invoice>> getInvoices({required DateTime startDate, required DateTime endDate, int limit = 50});
     Future<void> saveInvoice(Invoice invoice);
   }
   ```

2. **Data Layer (`lib/data/`)**:
   - Implements the Domain repository interfaces.
   - Contains `models/` with Freezed & JSON serialization (`fromJson`, `toJson`).
   - Converts Data Models (`InvoiceModel`) to/from Domain Entities (`Invoice`).
   - Handles network errors and maps them to Domain Failures/Exceptions.

   ```dart
   // lib/data/repositories/invoice_repository_impl.dart
   class InvoiceRepositoryImpl implements InvoiceRepository {
     final FirebaseDatabase _database;
     InvoiceRepositoryImpl(this._database);

     @override
     Future<List<Invoice>> getInvoices({required DateTime startDate, required DateTime endDate, int limit = 50}) async {
       try {
         final snapshot = await _database.ref('invoices')
           .orderByChild('createdAt')
           .startAt(startDate.toIso8601String())
           .endAt(endDate.toIso8601String())
           .limitToLast(limit)
           .get();

         if (!snapshot.exists || snapshot.value == null) return [];
         final data = snapshot.value as Map<dynamic, dynamic>;
         return data.entries.map((e) => InvoiceModel.fromMap(e.key, e.value).toDomain()).toList();
       } catch (e) {
         throw DatabaseFailure('Failed to fetch invoices: $e');
       }
     }
   }
   ```

3. **Presentation Layer (`lib/presentation/`)**:
   - Widgets consume Notifiers through Riverpod.
   - Never instantiates Repository implementations directly; always receives them via Riverpod dependency injection.
