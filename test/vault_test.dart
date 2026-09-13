import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';

void main() {
  const password = 'Synthetic test phrase — тест 🧪 1!';
  late Directory directory;
  late VaultStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('skysecret-vault-test-');
    store = VaultStore(file: File('${directory.path}/vault.smv'));
  });
  tearDown(() async => directory.delete(recursive: true));

  test('Argon2id RFC 9106 section 5.3 known-answer vector', () async {
    final key =
        await Argon2id(
          memory: 32,
          iterations: 3,
          parallelism: 4,
          hashLength: 32,
        ).deriveKey(
          secretKey: SecretKey(List.filled(32, 1)),
          nonce: List.filled(16, 2),
          optionalSecret: List.filled(8, 3),
          associatedData: List.filled(12, 4),
        );
    expect(
      (await key.extractBytes()).map((v) => v.toRadixString(16).padLeft(2, '0')).join(),
      '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
    );
    key.destroy();
  });

  test(
    'create, persist, restart, copy to another directory, unlock and edit',
    () async {
      final session = await store.create(password);
      expect(session.entries, isEmpty);
      final entry = VaultEntry.create(
        title: 'SYNTHETIC_TITLE',
        username: 'test-user',
        password: 'SYNTHETIC_SECRET',
        notes: 'Test note with Unicode: 雪 🧪',
      );
      await store.save(session, [entry]);
      final expectedEntry = entry.toJson();
      final encoded = await store.file.readAsBytes();
      final diskText = latin1.decode(encoded);
      for (final plain in [
        password,
        entry.title,
        entry.username,
        entry.password,
        entry.notes,
      ]) {
        expect(diskText.contains(plain), isFalse);
      }
      expect(
        await directory.list().length,
        5,
      );
      session.lock();
      expect(entry.toJson, throwsStateError);
      expect(session.entries, isEmpty);
      await expectLater(session.encrypt([]), throwsStateError);

      final restoredFile = await store.file.copy(
        '${directory.path}/restored.smv',
      );
      final restoredStore = VaultStore(file: restoredFile);
      final restored = await restoredStore.unlock(password);
      expect(restored.entries.single.toJson(), expectedEntry);
      await restoredStore.save(restored, []);
      restored.lock();
      final empty = await restoredStore.unlock(password);
      expect(empty.entries, isEmpty);
      empty.lock();
      expect(await store.file.readAsBytes(), encoded);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('21 wrong attempts do not mutate or destroy the vault; correct password still works', () async {
    final session = await store.create(password);
    session.lock();
    final before = await store.file.readAsBytes();
    for (var attempt = 0; attempt < 21; attempt++) {
      await expectLater(
        store.unlock('wrong synthetic phrase'),
        throwsA(isA<VaultUnlockException>()),
      );
    }
    expect(await store.file.readAsBytes(), before);
    final reopened = await store.unlock(password);
    reopened.lock();
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('tampered header, nonce, wrapped key, ciphertext, tags, truncation and swapped payload fail', () async {
    final first = await store.create(password);
    final second = await VaultCipher.create(password);
    final bytes = first.persistedBytes;
    expect(second.persistedBytes.sublist(24, 56), isNot(bytes.sublist(24, 56)));
    expect(second.persistedBytes, isNot(bytes));
    for (final offset in [24, 40, 56, 68, 100, 116, 128, bytes.length - 1]) {
      final changed = Uint8List.fromList(bytes)..[offset] ^= 1;
      await expectLater(
        VaultCipher.unlock(changed, password),
        throwsA(isA<VaultUnlockException>()),
      );
    }
    final swapped = Uint8List.fromList([
      ...bytes.sublist(0, 116),
      ...second.persistedBytes.sublist(116),
    ]);
    await expectLater(
      VaultCipher.unlock(swapped, password),
      throwsA(isA<VaultUnlockException>()),
    );
    await expectLater(
      VaultCipher.unlock(bytes.sublist(0, bytes.length - 1), password),
      throwsA(isA<VaultUnlockException>()),
    );
    for (final offset in [0, 8, 12, 16, 20]) {
      final changed = Uint8List.fromList(bytes)..[offset] ^= 0x80;
      await expectLater(
        VaultCipher.unlock(changed, password),
        throwsA(isA<VaultFormatException>()),
      );
    }
    await expectLater(
      VaultCipher.unlock(Uint8List(10), password),
      throwsA(isA<VaultFormatException>()),
    );
    await expectLater(
      VaultCipher.unlock(Uint8List(VaultCipher.maxFileBytes + 1), password),
      throwsA(isA<VaultFormatException>()),
    );
    first.lock();
    second.lock();
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('failed staging and stale writers preserve committed data', () async {
    final active = await store.create(password);
    final stale = await store.unlock(password);
    final entry = VaultEntry.create(
      title: 'Synthetic record',
      password: 'Synthetic secret',
    );
    final failing = VaultStore(
      file: store.file,
      beforeCommit: () async {
        final staged = await directory
            .list(recursive: true)
            .where((f) => f is File && f.path.endsWith('ciphertext'))
            .cast<File>()
            .single;
        expect(
          latin1.decode(await staged.readAsBytes()).contains(entry.password),
          isFalse,
        );
        throw const FileSystemException('Synthetic failure before commit');
      },
    );
    final before = await store.file.readAsBytes();
    await expectLater(
      failing.save(active, [entry]),
      throwsA(isA<FileSystemException>()),
    );
    expect(active.entries, isEmpty);
    expect(await store.file.readAsBytes(), before);
    await store.save(active, [entry]);
    expect(active.entries.single.title, entry.title);
    final after = await store.file.readAsBytes();
    await expectLater(
      store.save(stale, []),
      throwsA(isA<VaultConflictException>()),
    );
    await expectLater(
      store.create(password),
      throwsA(isA<VaultConflictException>()),
    );
    expect(await store.file.readAsBytes(), after);
    await store.save(active, [entry]);
    expect(
      await store.file.readAsBytes(),
      isNot(after),
    );
    active.lock();
    stale.lock();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
