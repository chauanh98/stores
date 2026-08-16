---
name: riverpod-audit
description: Audits Riverpod providers, UI rebuild frequency, memory leak prevention, and state lifecycles.
---

# Riverpod State & Memory Audit Workflow

Use this skill when auditing app performance, diagnosing memory leaks, or optimizing Flutter UI rendering.

## 1. Static Audit Checklist

### A. Provider Lifecycle Check
- [ ] Are screen-specific providers declared with `autoDispose`?
- [ ] Are `StreamProvider` or `AutoDisposeStreamNotifier` instances used for Firebase listeners so they unsubscribe automatically on unmount?

### B. Widget Rebuild Efficiency
- [ ] Is `ref.watch()` placed in small sub-widgets rather than at the root of a large page?
- [ ] Is `ref.watch(provider.select(...))` used for fine-grained subscriptions to prevent unnecessary widget rebuilds?
- [ ] Is `ref.read()` strictly used in callbacks (`onPressed`) and never inside the `build()` method?

### C. Async State Safety
- [ ] Are async states processed with `AsyncValue.when` or `whenOrNull` without assuming data is immediately available?
- [ ] Are mutations wrapped in `AsyncValue.guard()` to capture and propagate errors cleanly?

---

## 2. Detection Patterns

Scan for common anti-patterns in the codebase:

```bash
# 1. Look for ref.read in build methods (anti-pattern)
grep -rn "ref\.read(" lib/presentation/views/

# 2. Look for non-autoDispose providers in presentation/controllers
grep -rn "NotifierProvider<" lib/presentation/controllers/ | grep -v "AutoDispose"

# 3. Look for build context usage across await without mounted check
grep -rn "Navigator\." lib/ | grep -v "mounted"
```
