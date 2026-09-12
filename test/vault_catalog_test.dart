import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/crypto/crypto.dart';

void main() {
  test(
    'legacy discovery, multiple vaults and independent passwords/records',
    () async {
      final dir = await Directory.systemTemp.createTemp('sm-catalog-test-');
      addTearDown(() => dir.delete(recursive: true));
      final catalog = VaultCatalog(directory: dir);
      expect(await catalog.list(), isEmpty);
      final first = await catalog.legacy.store.create(
        'Synthetic primary password 1!',
        name: 'Synthetic primary',
      );
      await catalog.legacy.store.save(first, [
        VaultEntry.create(
          title: 'Primary entry',
          password: 'Synthetic primary value',
        ),
      ]);
      final before = await catalog.legacy.file.readAsBytes();
      final secondRef = catalog.newVault();
      expect(
        await secondRef.file.exists(),
        isFalse,
      );
      final second = await secondRef.store.create(
        'Synthetic second password 1!',
        name: 'Synthetic second',
      );
      await secondRef.store.save(second, [
        VaultEntry.create(
          title: 'Second entry',
          password: 'Synthetic second value',
        ),
      ]);
      first.lock();
      second.lock();
      final discovered = await VaultCatalog(directory: dir).list();
      expect(
        discovered.map((v) => v.id),
        containsAll(['legacy', secondRef.id]),
      );
      expect(discovered, hasLength(2));
      expect(await catalog.legacy.file.readAsBytes(), before);
      await expectLater(
        secondRef.store.unlock('Synthetic primary password 1!'),
        throwsA(isA<VaultUnlockException>()),
      );
      final reopened = await secondRef.store.unlock(
        'Synthetic second password 1!',
      );
      expect(reopened.entries.single.title, 'Second entry');
      expect(reopened.name, 'Synthetic second');
      reopened.lock();
      await File('${dir.path}/vaults/ignore.json').writeAsString('{}');
      expect(await catalog.list(), hasLength(2));
      expect(catalog.newVault().id, isNot(secondRef.id));
    },
  );
}
