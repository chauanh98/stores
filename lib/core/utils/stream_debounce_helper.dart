import 'dart:async';

/// A [StreamTransformer] that buffers data events and emits only the latest
/// event after [duration] of silence. If the source stream finishes while
/// an event is pending, it flushes that event before closing.
StreamTransformer<T, T> debounceStream<T>([
  Duration duration = const Duration(milliseconds: 250),
]) {
  return StreamTransformer<T, T>.fromBind((Stream<T> input) {
    StreamController<T>? controller;
    StreamSubscription<T>? subscription;
    Timer? timer;
    T? pendingData;
    bool hasPending = false;

    controller = StreamController<T>(
      sync: true,
      onListen: () {
        subscription = input.listen(
          (data) {
            pendingData = data;
            hasPending = true;
            timer?.cancel();
            timer = Timer(duration, () {
              if (controller != null && !controller.isClosed) {
                controller.add(data);
                hasPending = false;
                pendingData = null;
              }
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            if (controller != null && !controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
          onDone: () {
            timer?.cancel();
            if (hasPending && controller != null && !controller.isClosed) {
              controller.add(pendingData as T);
              hasPending = false;
              pendingData = null;
            }
            if (controller != null && !controller.isClosed) {
              controller.close();
            }
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        timer?.cancel();
        hasPending = false;
        pendingData = null;
        return subscription?.cancel();
      },
    );

    return controller.stream;
  });
}

/// Convenience extension on [Stream] providing the `.debounce()` operator.
extension StreamDebounceExtension<T> on Stream<T> {
  Stream<T> debounce([
    Duration duration = const Duration(milliseconds: 250),
  ]) {
    return transform(debounceStream<T>(duration));
  }
}
