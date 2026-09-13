import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/cancellable_worker.dart';

Future<int> Function() waitingJob(
  SendPort started,
  SendPort exited,
) => () async {
  Isolate.current.addOnExitListener(exited);
  started.send(true);
  return Future<int>.delayed(const Duration(minutes: 1), () => 1);
};

void main() {
  test('worker returns values and preserves operation failures', () async {
    expect(await CancellableWorker(() async => 42).result, 42);
    await expectLater(
      CancellableWorker<int>(() async => throw const FormatException()).result,
      throwsFormatException,
    );
  });

  test('cancellation before spawn completion rejects the result', () async {
    final worker = CancellableWorker(() async => 42);
    final result = expectLater(worker.result, throwsStateError);
    worker.cancel();
    worker.cancel();
    await result;
  });

  test('cancellation terminates a running isolate', () async {
    final started = ReceivePort();
    final exited = ReceivePort();
    addTearDown(started.close);
    addTearDown(exited.close);
    final worker = CancellableWorker(
      waitingJob(started.sendPort, exited.sendPort),
    );
    final result = expectLater(worker.result, throwsStateError);
    await started.first;
    worker.cancel();
    await result;
    await exited.first.timeout(const Duration(seconds: 10));
  });
}
