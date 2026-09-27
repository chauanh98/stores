import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure-Dart high-fidelity mock of [DataSnapshot] for testing.
class MockDataSnapshot extends Fake implements DataSnapshot {
  @override
  final dynamic value;

  @override
  final String? key;

  @override
  final bool exists;

  MockDataSnapshot({
    this.value,
    this.key,
    bool? exists,
  }) : exists = exists ?? (value != null);

  @override
  bool hasChild(String path) {
    if (value is! Map) return false;
    final parts = path.split('/');
    dynamic cur = value;
    for (final part in parts) {
      if (cur is Map && cur.containsKey(part)) {
        cur = cur[part];
      } else {
        return false;
      }
    }
    return cur != null;
  }

  @override
  DataSnapshot child(String path) {
    if (value is! Map) {
      return MockDataSnapshot(key: path.split('/').last, value: null, exists: false);
    }
    final parts = path.split('/');
    dynamic cur = value;
    for (final part in parts) {
      if (cur is Map && cur.containsKey(part)) {
        cur = cur[part];
      } else {
        return MockDataSnapshot(key: parts.last, value: null, exists: false);
      }
    }
    return MockDataSnapshot(
      key: parts.last,
      value: cur,
      exists: cur != null,
    );
  }

  @override
  Iterable<DataSnapshot> get children {
    if (value is Map) {
      return (value as Map).entries.map(
        (e) => MockDataSnapshot(
          key: e.key.toString(),
          value: e.value,
          exists: e.value != null,
        ),
      );
    }
    if (value is List) {
      final list = value as List;
      return Iterable.generate(list.length, (i) {
        return MockDataSnapshot(
          key: i.toString(),
          value: list[i],
          exists: list[i] != null,
        );
      });
    }
    return const [];
  }

  int get childrenCount {
    if (value is Map) return (value as Map).length;
    if (value is List) return (value as List).length;
    return 0;
  }
}

/// Pure-Dart high-fidelity mock of [DatabaseEvent].
class MockDatabaseEvent extends Fake implements DatabaseEvent {
  @override
  final DataSnapshot snapshot;

  @override
  final DatabaseEventType type;

  @override
  final String? previousChildKey;

  MockDatabaseEvent(
    this.snapshot, {
    this.type = DatabaseEventType.value,
    this.previousChildKey,
  });
}

/// A broadcast stream helper that tracks subscriber counts and cancellations deterministically.
class CancellableEventStream {
  final StreamController<DatabaseEvent> _controller =
      StreamController<DatabaseEvent>.broadcast();
  int activeListeners = 0;
  int cancelCount = 0;

  Stream<DatabaseEvent> get stream {
    return Stream<DatabaseEvent>.multi((multiController) {
      activeListeners++;
      final sub = _controller.stream.listen(
        multiController.add,
        onError: multiController.addError,
        onDone: multiController.close,
      );
      multiController.onCancel = () {
        activeListeners--;
        cancelCount++;
        sub.cancel();
      };
    });
  }

  void emit(DatabaseEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void emitSnapshot(DataSnapshot snapshot, {DatabaseEventType type = DatabaseEventType.value}) {
    emit(MockDatabaseEvent(snapshot, type: type));
  }

  void emitValue(dynamic value, {String? key}) {
    emitSnapshot(MockDataSnapshot(key: key, value: value));
  }

  void emitError(Object error, [StackTrace? stackTrace]) {
    if (!_controller.isClosed) {
      _controller.addError(error, stackTrace);
    }
  }

  void close() {
    _controller.close();
  }
}

/// Records method invocations on DatabaseReference and Query objects.
class MethodCallRecord {
  final String method;
  final String path;
  final dynamic value;
  final Map<String, dynamic>? extra;
  final DateTime timestamp;

  MethodCallRecord(
    this.method, {
    required this.path,
    this.value,
    this.extra,
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      'MethodCallRecord($method, path: $path, value: $value, extra: $extra)';
}

/// Central recorder to verify which methods (e.g. .get(), .set(), .update()) were called.
class MethodCallRecorder {
  final List<MethodCallRecord> calls = [];

  void record(
    String method, {
    required String path,
    dynamic value,
    Map<String, dynamic>? extra,
  }) {
    calls.add(MethodCallRecord(method, path: path, value: value, extra: extra));
  }

  bool _matchesPath(String callPath, String? targetPath) {
    if (targetPath == null) return true;
    return callPath == targetPath ||
        callPath.startsWith('$targetPath/') ||
        callPath.startsWith(targetPath) ||
        callPath.endsWith('/$targetPath') ||
        callPath.endsWith(targetPath) ||
        callPath.contains('/$targetPath/');
  }

  bool hasCalled(String method, {String? path}) {
    return calls.any((c) => c.method == method && _matchesPath(c.path, path));
  }

  int countCalls(String method, {String? path}) {
    return calls.where((c) => c.method == method && _matchesPath(c.path, path)).length;
  }

  List<MethodCallRecord> callsFor(String method, {String? path}) {
    return calls.where((c) => c.method == method && _matchesPath(c.path, path)).toList();
  }

  void clear() => calls.clear();
}

/// Pure-Dart high-fidelity mock of [Query] supporting filtering, ordering, and failure simulation.
class MockQuery extends Fake implements Query {
  @override
  final String path;
  final Map<String, dynamic> storeData;
  final String? orderedByChildKey;
  final dynamic startRange;
  final dynamic endRange;
  final dynamic equalToVal;
  final int? limitFirst;
  final int? limitLast;
  final MethodCallRecorder recorder;
  final bool shouldThrowOnGet;
  final Object? errorToThrow;
  final CancellableEventStream? queryValueStream;
  final CancellableEventStream? queryChildAddedStream;
  final CancellableEventStream? queryChildChangedStream;
  final CancellableEventStream? queryChildRemovedStream;

  MockQuery({
    required this.path,
    required this.storeData,
    required this.recorder,
    this.orderedByChildKey,
    this.startRange,
    this.endRange,
    this.equalToVal,
    this.limitFirst,
    this.limitLast,
    this.shouldThrowOnGet = false,
    this.errorToThrow,
    this.queryValueStream,
    this.queryChildAddedStream,
    this.queryChildChangedStream,
    this.queryChildRemovedStream,
  });

  @override
  Query orderByChild(String key) {
    return MockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      orderedByChildKey: key,
      startRange: startRange,
      endRange: endRange,
      equalToVal: equalToVal,
      limitFirst: limitFirst,
      limitLast: limitLast,
      shouldThrowOnGet: shouldThrowOnGet,
      errorToThrow: errorToThrow,
      queryValueStream: queryValueStream,
      queryChildAddedStream: queryChildAddedStream,
      queryChildChangedStream: queryChildChangedStream,
      queryChildRemovedStream: queryChildRemovedStream,
    );
  }

  @override
  Query startAt(dynamic value, {String? key}) {
    return MockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      orderedByChildKey: orderedByChildKey,
      startRange: value,
      endRange: endRange,
      equalToVal: equalToVal,
      limitFirst: limitFirst,
      limitLast: limitLast,
      shouldThrowOnGet: shouldThrowOnGet,
      errorToThrow: errorToThrow,
      queryValueStream: queryValueStream,
      queryChildAddedStream: queryChildAddedStream,
      queryChildChangedStream: queryChildChangedStream,
      queryChildRemovedStream: queryChildRemovedStream,
    );
  }

  @override
  Query endAt(dynamic value, {String? key}) {
    return MockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      orderedByChildKey: orderedByChildKey,
      startRange: startRange,
      endRange: value,
      equalToVal: equalToVal,
      limitFirst: limitFirst,
      limitLast: limitLast,
      shouldThrowOnGet: shouldThrowOnGet,
      errorToThrow: errorToThrow,
      queryValueStream: queryValueStream,
      queryChildAddedStream: queryChildAddedStream,
      queryChildChangedStream: queryChildChangedStream,
      queryChildRemovedStream: queryChildRemovedStream,
    );
  }

  @override
  Query equalTo(dynamic value, {String? key}) {
    return MockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      orderedByChildKey: orderedByChildKey,
      startRange: value,
      endRange: value,
      equalToVal: value,
      limitFirst: limitFirst,
      limitLast: limitLast,
      shouldThrowOnGet: shouldThrowOnGet,
      errorToThrow: errorToThrow,
      queryValueStream: queryValueStream,
      queryChildAddedStream: queryChildAddedStream,
      queryChildChangedStream: queryChildChangedStream,
      queryChildRemovedStream: queryChildRemovedStream,
    );
  }

  @override
  Query limitToFirst(int limit) {
    return MockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      orderedByChildKey: orderedByChildKey,
      startRange: startRange,
      endRange: endRange,
      equalToVal: equalToVal,
      limitFirst: limit,
      limitLast: limitLast,
      shouldThrowOnGet: shouldThrowOnGet,
      errorToThrow: errorToThrow,
      queryValueStream: queryValueStream,
      queryChildAddedStream: queryChildAddedStream,
      queryChildChangedStream: queryChildChangedStream,
      queryChildRemovedStream: queryChildRemovedStream,
    );
  }

  @override
  Query limitToLast(int limit) {
    return MockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      orderedByChildKey: orderedByChildKey,
      startRange: startRange,
      endRange: endRange,
      equalToVal: equalToVal,
      limitFirst: limitFirst,
      limitLast: limit,
      shouldThrowOnGet: shouldThrowOnGet,
      errorToThrow: errorToThrow,
      queryValueStream: queryValueStream,
      queryChildAddedStream: queryChildAddedStream,
      queryChildChangedStream: queryChildChangedStream,
      queryChildRemovedStream: queryChildRemovedStream,
    );
  }

  @override
  Future<DataSnapshot> get() async {
    recorder.record('get', path: path, extra: {
      'orderedByChildKey': orderedByChildKey,
      'startRange': startRange,
      'endRange': endRange,
      'equalToVal': equalToVal,
    });

    if (shouldThrowOnGet) {
      throw errorToThrow ??
          FirebaseException(
            plugin: 'firebase_database',
            code: 'index-not-defined',
            message: 'Index not defined for $orderedByChildKey at path $path',
          );
    }

    final Map<String, dynamic> filtered = {};
    storeData.forEach((k, v) {
      if (v is Map && orderedByChildKey != null) {
        final itemVal = v[orderedByChildKey]?.toString() ?? '';
        final start = startRange?.toString();
        final end = endRange?.toString();
        final eq = equalToVal?.toString();
        bool match = true;
        if (eq != null && itemVal != eq) match = false;
        if (start != null && itemVal.compareTo(start) < 0) match = false;
        if (end != null && itemVal.compareTo(end) > 0) match = false;
        if (match) filtered[k] = v;
      } else if (equalToVal != null && v is Map) {
        filtered[k] = v;
      } else {
        filtered[k] = v;
      }
    });

    return MockDataSnapshot(
      key: path.split('/').last,
      value: filtered.isEmpty ? null : filtered,
      exists: filtered.isNotEmpty,
    );
  }

  @override
  Stream<DatabaseEvent> get onChildAdded =>
      queryChildAddedStream?.stream ?? const Stream.empty();

  @override
  Stream<DatabaseEvent> get onChildChanged =>
      queryChildChangedStream?.stream ?? const Stream.empty();

  @override
  Stream<DatabaseEvent> get onChildRemoved =>
      queryChildRemovedStream?.stream ?? const Stream.empty();

  @override
  Stream<DatabaseEvent> get onValue {
    if (queryValueStream == null) {
      return Stream.fromFuture(get()).map((snap) => MockDatabaseEvent(snap));
    }
    return Stream<DatabaseEvent>.multi((multiController) {
      final sub = queryValueStream!.stream.listen(
        multiController.add,
        onError: multiController.addError,
        onDone: multiController.close,
      );
      if (storeData.isNotEmpty) {
        get().then((snap) {
          multiController.add(MockDatabaseEvent(snap));
        });
      }
      multiController.onCancel = () {
        sub.cancel();
      };
    });
  }
}

/// Pure-Dart high-fidelity mock of [DatabaseReference].
class MockDatabaseReference extends MockQuery implements DatabaseReference {
  final CancellableEventStream childAddedStream = CancellableEventStream();
  final CancellableEventStream childChangedStream = CancellableEventStream();
  final CancellableEventStream childRemovedStream = CancellableEventStream();
  final CancellableEventStream valueStream = CancellableEventStream();

  final Map<String, MockDatabaseReference> children = {};
  final MockDatabaseReference? _parentRef;
  bool simulateQueryFailure = false;
  Object? queryFailureError;
  bool throwOnGet = false;
  Object? throwOnGetError;
  int _pushCounter = 0;

  MockDatabaseReference({
    required super.path,
    required super.recorder,
    Map<String, dynamic>? initialData,
    MockDatabaseReference? parent,
    super.shouldThrowOnGet,
    super.errorToThrow,
  })  : _parentRef = parent,
        super(storeData: initialData ?? {});

  @override
  Stream<DatabaseEvent> get onChildAdded => childAddedStream.stream;

  @override
  Stream<DatabaseEvent> get onChildChanged => childChangedStream.stream;

  @override
  Stream<DatabaseEvent> get onChildRemoved => childRemovedStream.stream;

  @override
  Stream<DatabaseEvent> get onValue => valueStream.stream;

  @override
  String? get key => path.split('/').last;

  @override
  DatabaseReference? get parent => _parentRef;

  @override
  DatabaseReference get root {
    MockDatabaseReference curr = this;
    while (true) {
      final p = curr._parentRef;
      if (p == null) break;
      curr = p;
    }
    return curr;
  }

  @override
  DatabaseReference child(String childPath) {
    final segments =
        childPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return this;

    MockDatabaseReference current = this;
    for (final seg in segments) {
      current = current.children.putIfAbsent(
        seg,
        () {
          Map<String, dynamic> childStore = {};
          if (current.storeData[seg] is Map) {
            childStore =
                Map<String, dynamic>.from(current.storeData[seg] as Map);
          }
          return MockDatabaseReference(
            path: '${current.path}/$seg',
            recorder: recorder,
            initialData: childStore,
            parent: current,
          );
        },
      );
    }
    return current;
  }

  @override
  DatabaseReference push() {
    final generatedKey =
        '-M${DateTime.now().millisecondsSinceEpoch}_${_pushCounter++}';
    return child(generatedKey);
  }

  @override
  Query orderByChild(String key) {
    return MockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      orderedByChildKey: key,
      startRange: startRange,
      endRange: endRange,
      equalToVal: equalToVal,
      limitFirst: limitFirst,
      limitLast: limitLast,
      shouldThrowOnGet: simulateQueryFailure || shouldThrowOnGet,
      errorToThrow: queryFailureError ?? errorToThrow,
      queryValueStream: valueStream,
      queryChildAddedStream: childAddedStream,
      queryChildChangedStream: childChangedStream,
      queryChildRemovedStream: childRemovedStream,
    );
  }

  @override
  Query limitToFirst(int limit) {
    return MockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      orderedByChildKey: orderedByChildKey,
      startRange: startRange,
      endRange: endRange,
      equalToVal: equalToVal,
      limitFirst: limit,
      limitLast: limitLast,
      shouldThrowOnGet: simulateQueryFailure || shouldThrowOnGet,
      errorToThrow: queryFailureError ?? errorToThrow,
      queryValueStream: valueStream,
      queryChildAddedStream: childAddedStream,
      queryChildChangedStream: childChangedStream,
      queryChildRemovedStream: childRemovedStream,
    );
  }

  @override
  Query limitToLast(int limit) {
    return MockQuery(
      path: path,
      storeData: storeData,
      recorder: recorder,
      orderedByChildKey: orderedByChildKey,
      startRange: startRange,
      endRange: endRange,
      equalToVal: equalToVal,
      limitFirst: limitFirst,
      limitLast: limit,
      shouldThrowOnGet: simulateQueryFailure || shouldThrowOnGet,
      errorToThrow: queryFailureError ?? errorToThrow,
      queryValueStream: valueStream,
      queryChildAddedStream: childAddedStream,
      queryChildChangedStream: childChangedStream,
      queryChildRemovedStream: childRemovedStream,
    );
  }

  void setSimulateQueryFailure([bool fail = true, Object? error]) {
    simulateQueryFailure = fail;
    queryFailureError = error;
  }

  void setThrowOnGet([bool fail = true, Object? error]) {
    throwOnGet = fail;
    throwOnGetError = error;
  }

  bool get _shouldFailOnGet {
    if (throwOnGet || shouldThrowOnGet) return true;
    MockDatabaseReference? p = _parentRef;
    while (p != null) {
      if (p.throwOnGet || p.shouldThrowOnGet) return true;
      p = p._parentRef;
    }
    return false;
  }

  Object? get _effectiveThrowOnGetError {
    if (throwOnGetError != null) return throwOnGetError;
    if (errorToThrow != null) return errorToThrow;
    MockDatabaseReference? p = _parentRef;
    while (p != null) {
      if (p.throwOnGetError != null) return p.throwOnGetError;
      if (p.errorToThrow != null) return p.errorToThrow;
      p = p._parentRef;
    }
    return null;
  }

  @override
  Future<void> set(dynamic value) async {
    recorder.record('set', path: path, value: value);
    if (value is Map) {
      storeData.clear();
      storeData.addAll(Map<String, dynamic>.from(value));
    } else {
      storeData.clear();
      if (value != null) {
        storeData['__value__'] = value;
      }
    }
    if (_parentRef != null && key != null) {
      _parentRef.storeData[key!] = value;
    }
  }

  @override
  Future<void> update(Map<String, dynamic> value) async {
    recorder.record('update', path: path, value: value);
    storeData.addAll(value);
    if (_parentRef != null && key != null) {
      if (_parentRef.storeData[key!] is Map) {
        final existing = Map<String, dynamic>.from(_parentRef.storeData[key!] as Map);
        existing.addAll(value);
        _parentRef.storeData[key!] = existing;
      } else {
        _parentRef.storeData[key!] = Map<String, dynamic>.from(storeData);
      }
    }
  }

  @override
  Future<void> remove() async {
    recorder.record('remove', path: path);
    storeData.clear();
    if (_parentRef != null && key != null) {
      _parentRef.storeData.remove(key);
    }
  }

  @override
  Future<DataSnapshot> get() async {
    recorder.record('get', path: path);
    if (_shouldFailOnGet) {
      throw _effectiveThrowOnGetError ??
          FirebaseException(
            plugin: 'firebase_database',
            code: 'network-error',
            message: 'Simulated network failure on get() for $path',
          );
    }

    // Check if this ref represents a value stored in parent
    if (_parentRef != null && key != null && _parentRef.storeData.containsKey(key)) {
      final parentVal = _parentRef.storeData[key!];
      if (parentVal is Map) {
        return MockDataSnapshot(
          key: key,
          value: Map<String, dynamic>.from(parentVal),
          exists: true,
        );
      } else {
        return MockDataSnapshot(
          key: key,
          value: parentVal,
          exists: parentVal != null,
        );
      }
    }

    if (storeData.containsKey('__value__')) {
      return MockDataSnapshot(
        key: key,
        value: storeData['__value__'],
        exists: true,
      );
    }

    return MockDataSnapshot(
      key: key,
      value: storeData.isEmpty ? null : storeData,
      exists: storeData.isNotEmpty,
    );
  }

  void emitChildAdded(String childKey, dynamic value) {
    childAddedStream.emit(
      MockDatabaseEvent(
        MockDataSnapshot(key: childKey, value: value, exists: value != null),
        type: DatabaseEventType.childAdded,
      ),
    );
  }

  void emitChildChanged(String childKey, dynamic value) {
    childChangedStream.emit(
      MockDatabaseEvent(
        MockDataSnapshot(key: childKey, value: value, exists: value != null),
        type: DatabaseEventType.childChanged,
      ),
    );
  }

  void emitChildRemoved(String childKey, [dynamic value]) {
    childRemovedStream.emit(
      MockDatabaseEvent(
        MockDataSnapshot(key: childKey, value: value, exists: false),
        type: DatabaseEventType.childRemoved,
      ),
    );
  }

  void emitValue(dynamic value, {String? valueKey}) {
    valueStream.emit(
      MockDatabaseEvent(
        MockDataSnapshot(
          key: valueKey ?? key,
          value: value,
          exists: value != null,
        ),
        type: DatabaseEventType.value,
      ),
    );
  }

  void emitNullValue() {
    emitValue(null);
  }
}

/// Pure-Dart high-fidelity mock of [FirebaseDatabase].
class MockFirebaseDatabase extends Fake implements FirebaseDatabase {
  final Map<String, MockDatabaseReference> references = {};
  final List<String> requestedPaths = [];
  final MethodCallRecorder recorder = MethodCallRecorder();
  bool persistenceEnabled = false;
  int? persistenceCacheSizeBytes;

  MockDatabaseReference getOrCreateRef(String path,
      {Map<String, dynamic>? initialData}) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    requestedPaths.add(cleanPath);
    return references.putIfAbsent(
      cleanPath,
      () => MockDatabaseReference(
        path: cleanPath,
        recorder: recorder,
        initialData: initialData,
      ),
    );
  }

  @override
  DatabaseReference ref([String? path]) {
    return getOrCreateRef(path ?? '');
  }

  @override
  DatabaseReference refFromURL(String url) {
    final uri = Uri.parse(url);
    final p = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    return getOrCreateRef(p);
  }

  @override
  Future<void> setPersistenceEnabled(bool enabled) async {
    persistenceEnabled = enabled;
  }

  @override
  Future<void> setPersistenceCacheSizeBytes(int bytes) async {
    persistenceCacheSizeBytes = bytes;
  }

  /// Synchronously seeds data into the mock database at [path].
  void seedData(String path, Map<String, dynamic> data) {
    final reference = getOrCreateRef(path);
    data.forEach((k, v) {
      if (v is Map) {
        reference.storeData[k] = Map<String, dynamic>.from(v);
      } else {
        reference.storeData[k] = v;
      }
    });
  }

  /// Asynchronously seeds data into the mock database at [path].
  Future<void> seedDataAsync(String path, Map<String, dynamic> data) async {
    seedData(path, data);
  }

  /// Sets whether queries on the reference at [path] should fail (e.g. to test fallback).
  void setSimulateQueryFailure(String path, [bool fail = true, Object? error]) {
    final reference = getOrCreateRef(path);
    reference.setSimulateQueryFailure(fail, error);
  }

  /// Sets whether .get() on the reference at [path] should throw.
  void setThrowOnGet(String path, [bool fail = true, Object? error]) {
    final reference = getOrCreateRef(path);
    reference.setThrowOnGet(fail, error);
  }

  /// Helper to check if .get() was called on a specific path.
  bool wasGetCalled(String path) {
    return recorder.hasCalled('get', path: path);
  }

  /// Helper to get the number of times .get() was called on a path.
  int getCallCount(String path) {
    return recorder.countCalls('get', path: path);
  }
}
