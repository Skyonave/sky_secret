import 'dart:async';
import 'dart:isolate';

class CancellableWorker<T> {
  final _port = ReceivePort();
  final _completion = Completer<T>();
  Isolate? _isolate;

  CancellableWorker(Future<T> Function() operation) {
    _port.listen(_receive);
    unawaited(_start(operation));
  }

  Future<T> get result => _completion.future;

  Future<void> _start(Future<T> Function() operation) async {
    try {
      final isolate = await Isolate.spawn(
        _execute<T>,
        (_port.sendPort, operation),
        paused: true,
        onExit: _port.sendPort,
        onError: _port.sendPort,
        errorsAreFatal: true,
      );
      if (_completion.isCompleted) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
        isolate.resume(isolate.pauseCapability!);
      }
    } catch (_) {
      if (!_completion.isCompleted) {
        _completion.completeError(StateError('Could not start crypto worker'));
        _close();
      }
    }
  }

  void _receive(dynamic message) {
    if (_completion.isCompleted) return;
    if (message is List && message.length == 2 && message[0] == true) {
      _completion.complete(message[1] as T);
    } else if (message is List && message.length == 3 && message[0] == false) {
      _completion.completeError(message[1] as Object, message[2] as StackTrace);
    } else {
      _completion.completeError(
        StateError('Crypto worker exited without result'),
      );
    }
    _close();
  }

  void cancel() {
    if (_completion.isCompleted) return;
    _completion.completeError(StateError('Crypto operation was cancelled'));
    _close();
  }

  void _close() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port.close();
  }
}

Future<void> _execute<T>((SendPort, Future<T> Function()) request) async {
  try {
    final value = await request.$2();
    Isolate.exit(request.$1, [true, value]);
  } catch (error, stack) {
    request.$1.send([false, error, stack]);
  }
}
