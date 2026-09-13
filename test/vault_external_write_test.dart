import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';

import 'vault_collection_test.dart' show collectionPassword;

void main() {
  for (final rotate in [false, true]) {
    test('external replacement during staging survives ${rotate ? 'rotation' : 'save'}', () async {
      final directory = await Directory.systemTemp.createTemp('sky-external-write-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/vault.smv');
      final session = await VaultStore(file: file).create(collectionPassword);
      final external = await VaultCipher.create(collectionPassword, name: 'Synthetic external vault');
      addTearDown(session.lock);
      addTearDown(external.lock);
      final original = session.persistedBytes;
      final externalBytes = external.persistedBytes;
      final writer = VaultStore(
        file: file,
        beforeCommit: () => file.writeAsBytes(externalBytes, flush: true),
      );
      await expectLater(
        rotate
            ? writer.changePassword(session, collectionPassword, 'Another synthetic phrase for audit 031')
            : writer.save(session, [VaultEntry.create(title: 'Synthetic local edit')]),
        throwsA(isA<VaultConflictException>()),
      );
      expect(await file.readAsBytes(), externalBytes);
      expect(session.persistedBytes, original);
      expect(session.isLocked, isFalse);
      expect(await File('${file.path}.rotation').exists(), isFalse);
    });
  }
}
