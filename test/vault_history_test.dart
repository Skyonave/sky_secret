import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';

void main() {
  const password = 'Synthetic history password 123!';
  late Directory root;
  late VaultCatalog catalog;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('skysecret-history-unit-');
    catalog = VaultCatalog(directory: root);
  });
  tearDown(() => root.delete(recursive: true));

  test('save and deletion preserve authenticated snapshots, recovery creates a separate vault', () async {
    final reference = catalog.newVault();
    final session = await reference.store.create(password);
    final initial = session.persistedBytes;
    await reference.store.save(session, [
      VaultEntry.create(
        title: 'Synthetic',
        password: 'Synthetic history secret',
      ),
    ]);
    final latest = session.persistedBytes;
    await reference.store.delete();
    session.lock();
    expect(await catalog.list(), isEmpty);
    final history = await catalog.history();
    expect(history, hasLength(2));
    expect(await history.first.file.readAsBytes(), latest);
    expect(await history.last.file.readAsBytes(), initial);
    final recovered = catalog.newVault();
    final opened = await recovered.store.importFrom(
      history.first.file,
      password,
    );
    expect(opened.entries.single.password, 'Synthetic history secret');
    expect(await reference.store.exists(), isFalse);
    opened.lock();
  });

  test(
    'history failure prevents replacement and keeps the current ciphertext',
    () async {
      final store = catalog.legacy.store;
      final session = await store.create(password);
      final before = session.persistedBytes;
      await File(store.historyDirectory.path).writeAsString('synthetic obstruction');
      await expectLater(
        store.save(session, [VaultEntry.create(title: 'Synthetic')]),
        throwsA(isA<VaultFormatException>()),
      );
      expect(await store.readEncryptedSnapshot(), before);
      expect(session.persistedBytes, before);
      session.lock();
    },
  );

  test(
    'history retains 20 states until rotation removes old-password snapshots and cache',
    () async {
      final store = catalog.legacy.store;
      var session = await store.create(password);
      for (var i = 0; i < 23; i++) {
        await store.save(session, [VaultEntry.create(title: 'Synthetic $i')]);
      }
      expect(await store.history(), hasLength(20));
      final old = session.persistedBytes;
      final hash = 'a' * 40;
      await store.cacheBaseline(hash, old);
      session = await store.changePassword(
        session,
        password,
        'Synthetic next password 456!',
      );
      expect(await store.history(), isEmpty);
      expect(await store.readBaseline(hash), isNull);
      expect(store.snapshotCleanupPending, isFalse);
      await store.cacheBaseline(hash, old);
      expect(await store.readBaseline(hash), isNull);
      await expectLater(store.unlock(password), throwsA(isA<VaultUnlockException>()));
      session.lock();
    },
  );

  test(
    'copied writer identity is separated by working path and survives restart',
    () async {
      final first = catalog.legacy.store;
      final id = await first.writerIdentity();
      expect(await catalog.legacy.store.writerIdentity(), id);
      final second = catalog.newVault().store;
      await second.file.parent.create(recursive: true);
      await File('${first.file.path}.writer').copy('${second.file.path}.writer');
      expect(await second.writerIdentity(), isNot(id));
    },
  );
}
