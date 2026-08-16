---
name: flutter-test-and-verify
description: Comprehensive verification workflow to analyze Dart code, run unit tests, and validate compilation.
---

# Flutter Verification & Quality Assurance Workflow

Use this skill whenever completing any code edits, refactors, or before closing a feature implementation.

## 1. Automated Verification Commands

Run the following checks systematically:

```bash
# 1. Check for syntax, static analysis, and linting issues
flutter analyze

# 2. Re-generate serialization / freezed files if models were touched
dart run build_runner build --delete-conflicting-outputs

# 3. Run all unit and widget tests
flutter test
```

---

## 2. Issue Resolution Checklist

If `flutter analyze` reports any issues:
- [ ] **Unused Imports / Variables**: Remove immediately.
- [ ] **Null Safety / Type Warnings**: Ensure proper null checks (`?.`, `??`, `if (x != null)`) instead of dangerous force unwrap `!`.
- [ ] **`use_build_context_synchronously`**: Add `if (!context.mounted) return;` before any context usage following an `await`.
- [ ] **Deprecated Members**: Upgrade to current Flutter 3.x / Riverpod 2.x APIs.

---

## 3. Targeted Test Execution
To run tests for a specific feature:
```bash
flutter test test/path/to/feature_test.dart
```
