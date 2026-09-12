import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sequential Argon2 preserves the full vault KDF profile', () async {
    final input = SecretKeyData(
      utf8.encode('Synthetic KDF compatibility fixture'),
      overwriteWhenDestroyed: true,
    );
    final key = await DartArgon2id(
      memory: 65536,
      iterations: 3,
      parallelism: 4,
      hashLength: 32,
      maxIsolates: 0,
    ).deriveKey(secretKey: input, nonce: List.generate(16, (i) => i));
    try {
      expect(
        (await key.extractBytes())
            .map((v) => v.toRadixString(16).padLeft(2, '0'))
            .join(),
        '4d658e076fd7efa8440955c2cf1d1877da19d556d9768afff508405b764afa62',
      );
    } finally {
      key.destroy();
      input.destroy();
    }
  });
}
