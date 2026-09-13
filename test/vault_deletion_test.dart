import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';

void main() {
  test(
    'deleting one vault preserves peers and backup; stale save fails',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sm-delete-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final catalog = VaultCatalog(directory: directory);
      final store = catalog.legacy.store;
      final session = await store.create('Synthetic deletion password 1!');
      addTearDown(session.lock);
      final backup = File('${directory.path}/backup.smv');
      await store.exportTo(session, backup);
      final originalBytes = await backup.readAsBytes();
      final other = catalog.newVault();
      await other.file.parent.create(recursive: true);
      await other.file.writeAsBytes(originalBytes);

      await store.delete();
      expect(await store.exists(), isFalse);
      expect((await catalog.list()).map((vault) => vault.id), [other.id]);
      expect(await backup.readAsBytes(), originalBytes);
      expect(await other.file.readAsBytes(), originalBytes);
      await expectLater(
        store.save(session, []),
        throwsA(isA<VaultConflictException>()),
      );
      expect(await store.exists(), isFalse);
      await other.store.delete();
      expect(await catalog.list(), isEmpty);
      expect(await backup.readAsBytes(), originalBytes);
    },
  );

  test(
    'cancelled or failed deletion keeps bytes and releases write guard',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sm-delete-cancel-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/synthetic.smv');
      final bytes = [1, 2, 3, 4];
      await file.writeAsBytes(bytes);
      var fail = true;
      final store = VaultStore(
        file: file,
        beforeCommit: () async {
          if (fail) throw const FileSystemException('Synthetic failure');
        },
      );
      await expectLater(store.delete(), throwsA(isA<FileSystemException>()));
      expect(await file.readAsBytes(), bytes);
      fail = false;
      await expectLater(store.delete(allowed: () => false), throwsStateError);
      expect(await file.readAsBytes(), bytes);
      await store.delete();
      expect(await file.exists(), isFalse);
    },
  );

  test('pending deletion rejects a second operation on the store', () async {
    final directory = await Directory.systemTemp.createTemp('sm-delete-busy-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/synthetic.smv');
    await file.writeAsBytes([1, 2, 3]);
    final entered = Completer<void>();
    final resume = Completer<void>();
    final store = VaultStore(
      file: file,
      beforeCommit: () async {
        entered.complete();
        await resume.future;
      },
    );
    final pending = store.delete();
    await entered.future;
    await expectLater(store.delete(), throwsA(isA<VaultConflictException>()));
    resume.complete();
    await pending;
    expect(await file.exists(), isFalse);
  });
}
