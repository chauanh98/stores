---
name: flutter-feature-scaffold
description: Step-by-step workflow to scaffold a complete new Flutter feature adhering to Clean Architecture and Riverpod standards.
---

# Flutter Feature Scaffold Workflow

Use this skill whenever a new feature, domain module, or screen is requested.

## 1. Directory Structure Creation
Create the following structure under `lib/`:

```text
lib/
├── domain/
│   ├── entities/<feature_name>.dart
│   └── repositories/<feature_name>_repository.dart
├── data/
│   ├── models/<feature_name>_model.dart
│   └── repositories/<feature_name>_repository_impl.dart
└── presentation/
    ├── controllers/<feature_name>_controller.dart
    ├── views/<feature_name>_view.dart
    └── widgets/<feature_name>_widget.dart
```

---

## 2. Implementation Steps

### Step A: Domain Layer (Pure Dart)
1. Write the Entity class with immutable fields.
2. Define the abstract repository interface:
   ```dart
   abstract interface class FeatureRepository {
     Future<List<FeatureEntity>> getItems();
     Future<void> saveItem(FeatureEntity item);
   }
   ```

### Step B: Data Layer
1. Create Freezed Data Model with `fromJson` and `toDomain()` converter:
   ```dart
   @freezed
   class FeatureModel with _$FeatureModel {
     const factory FeatureModel({
       required String id,
       required String title,
     }) = _FeatureModel;

     factory FeatureModel.fromJson(Map<String, dynamic> json) => _$FeatureModelFromJson(json);
   }
   ```
2. Implement Repository in `data/repositories/<feature_name>_repository_impl.dart`.
3. Expose the Repository Provider in a shared provider file:
   ```dart
   final featureRepositoryProvider = Provider<FeatureRepository>((ref) {
     final db = ref.watch(firebaseDatabaseProvider);
     return FeatureRepositoryImpl(db);
   });
   ```

### Step C: Presentation Layer (Riverpod Controller & UI)
1. Create `AutoDisposeAsyncNotifier` or `AutoDisposeNotifier` in `presentation/controllers/`:
   ```dart
   final featureControllerProvider = AutoDisposeAsyncNotifierProvider<FeatureController, List<FeatureEntity>>(
     FeatureController.new,
   );
   ```
2. Create View in `presentation/views/` using `ConsumerWidget` or `ConsumerStatefulWidget`.

---

## 3. Code Generation & Validation
After creating Freezed / JSON Serializable models, run:
```bash
dart run build_runner build --delete-conflicting-outputs
flutter analyze
```
