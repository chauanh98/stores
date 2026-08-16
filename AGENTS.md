# Flutter Store Project - Agent Core Directives

This document provides system-wide guidelines and architecture rules for all AI agents and developers operating in this workspace.

---

## 1. Project Overview & Tech Stack
- **Platform**: Flutter (Dart SDK `^3.5.3`)
- **State Management**: `flutter_riverpod` (v2.6.1+)
- **Routing**: `go_router` (v14.0+)
- **Backend & Storage**: Firebase (Core, Auth, Realtime Database, Storage)
- **Data Modeling & Serialization**: `freezed_annotation`, `json_annotation`, `build_runner`
- **Charts & UI**: `fl_chart`, `cupertino_icons`
- **File & Exports**: `excel`, `file_picker`, `share_plus`

---

## 2. Architectural Blueprint (Clean Architecture)

All code inside `lib/` must adhere strictly to the 4-tier Clean Architecture separation:

```text
lib/
├── core/             # Shared constants, theme, network clients, base utilities, formatters
├── domain/           # Pure Dart: Entities, value objects, failure classes, repository interfaces
│   ├── entities/
│   └── repositories/
├── data/             # Data sources (Firebase, local cache), DTO/Models (Freezed), Repo Impls
│   ├── models/
│   ├── datasources/
│   └── repositories/
├── application/      # Use cases, application services, business coordination
└── presentation/     # UI screens, widgets, Riverpod Notifiers/Controllers, routes
    ├── controllers/  # Riverpod Notifiers / AsyncNotifiers
    ├── views/        # Screens / Pages
    └── widgets/      # Reusable sub-widgets
```

### Layer Dependency Rules:
1. **`domain` layer is pure Dart**: It must **never** import Flutter UI packages (`flutter/material.dart`), Firebase, or Riverpod.
2. **`presentation` depends on `domain` and `application`**: Widgets interact with business logic strictly through Riverpod controllers/providers, never directly with raw data sources.
3. **`data` implements `domain` interfaces**: Data models convert raw Firebase JSON maps to Domain Entities.

---

## 3. Mandatory Development Rules

### A. State Management with Riverpod 2.x
- Prefer `Notifier` / `AsyncNotifier` (or `StateNotifier`) with immutable state.
- Always use `autoDispose` for view-specific providers (`@riverpod` or `.autoDispose`) to prevent memory leaks when screens close.
- In Widgets: Use `ref.watch()` inside `build()` for reactive UI. Use `ref.read()` only inside event callbacks (e.g. `onPressed`).
- Handle async states gracefully using `asyncState.when(data: ..., loading: ..., error: ...)`.

### B. Async & Context Safety
- Whenever using `BuildContext` across an `await` boundary, **always** guard it:
  ```dart
  final navigator = GoRouter.of(context);
  await someAsyncOperation();
  if (!context.mounted) return;
  navigator.push('/target');
  ```
- Always dispose controllers (`TextEditingController`, `ScrollController`, `AnimationController`, `StreamSubscription`) in `dispose()`.

### C. Database & Query Safety
- **Never fetch entire unindexed or unbounded nodes** from Firebase Realtime Database.
- Always apply query constraints (`limitToFirst`, `limitToLast`, `startAt`, `orderByChild`).

---

## 4. Multi-Agent & Skill System
Specialized subagents and runbooks are available in `.agents/`:
- **Skills (`.agents/skills/`)**:
  - `flutter-feature-scaffold`: Step-by-step feature generator from domain to UI.
  - `flutter-test-and-verify`: Linter check (`flutter analyze`) and test runner.
  - `riverpod-audit`: State and performance auditor.
  - `fifo-revenue-audit`: Logic validator for FIFO inventory and invoice calculations.
- **Rules (`.agents/rules/`)**:
  - Detailed guidelines for Riverpod, Clean Architecture, Firebase safety, and Memory safety.
