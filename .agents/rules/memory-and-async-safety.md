# Memory & Async Safety Rules for Flutter

## 1. Async Gap & Context Mounting Check

Using `BuildContext` across asynchronous gaps without checking `mounted` is a primary cause of runtime crashes and memory leaks.

```dart
// ❌ FORBIDDEN
Future<void> _submitForm(BuildContext context) async {
  await performAsyncSave();
  Navigator.of(context).pop(); // Crash if widget was unmounted!
}

// ✅ REQUIRED - Stateful Widget
Future<void> _submitForm() async {
  await performAsyncSave();
  if (!mounted) return;
  Navigator.of(context).pop();
}

// ✅ REQUIRED - ConsumerWidget / Helper Function
Future<void> _submitForm(BuildContext context) async {
  await performAsyncSave();
  if (!context.mounted) return;
  Navigator.of(context).pop();
}
```

---

## 2. Proper Controller and Listener Disposal

Every controller created in a `StatefulWidget` MUST be released in `dispose()`:

```dart
class _CustomFormState extends State<CustomForm> {
  late final TextEditingController _textController;
  late final ScrollController _scrollController;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _subscription?.cancel();
    super.dispose();
  }
}
```

*Note: For `TextEditingController` inside Riverpod / Stateless widgets, prefer using `flutter_hooks` (`useTextEditingController()`) or state-driven text fields.*

---

## 3. Large List Rendering Performance
- Always use `ListView.builder` or `CustomScrollView` with `SliverList.builder` rather than `ListView(children: [...])` or `Column` for dynamic/scrollable content.
- Provide `itemExtent` or `prototypeItem` if item sizes are uniform to eliminate layout measurement overhead.
- Use `const` constructors aggressively for sub-trees that don't depend on dynamic variables.
