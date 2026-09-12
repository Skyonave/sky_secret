import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/crypto/protected_memory.dart';

void main() {
  test('text destroy and session revocation reject reads and adoption', () {
    final lifetime = SecretLifetime();
    final text = ProtectedText('Synthetic secret').ownFor(lifetime);
    final bytes = ProtectedBytes([1, 2, 3]).ownFor(lifetime);
    lifetime.revoke();
    lifetime.revoke();
    expect(text.read, throwsStateError);
    expect(() => text.isEmpty, throwsStateError);
    expect(bytes.read, throwsStateError);
    expect(() => bytes.ownFor(SecretLifetime()), throwsStateError);
    text.destroy();
    text.destroy();
    bytes.destroy();
    final standalone = ProtectedText('Synthetic');
    standalone.destroy();
    expect(standalone.read, throwsStateError);
  });

  test('Windows protected bytes preserve padding and chunk boundaries', () {
    for (final size in [0, 1, 15, 16, 17, 16383, 16384, 16385, 33001]) {
      final original = Uint8List.fromList(
        List.generate(size, (index) => index % 251),
      );
      final value = ProtectedBytes(original);
      expect(value.length, size);
      final first = value.read();
      expect(first, original);
      first.fillRange(0, first.length, 0);
      expect(value.read(), original);
      value.destroy();
      value.destroy();
      expect(value.read, throwsStateError);
    }
  });

  test(
    'protected values cross same-process isolates without a plaintext cache',
    () async {
      final value = ProtectedBytes([0, 1, 127, 255]);
      final readInWorker = await Isolate.run(value.read);
      expect(readInWorker, [0, 1, 127, 255]);
      final workerValue = await Isolate.run(
        () => ProtectedText('Synthetic текст 1! 🧪'),
      );
      expect(workerValue.read(), 'Synthetic текст 1! 🧪');
      expect(ProtectedText('').isEmpty, isTrue);
      expect(workerValue.isEmpty, isFalse);
      value.destroy();
    },
  );
}
