import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/crypto/crypto.dart';

import 'vault_sections_test.dart' show fixture;

void main() {
  const composed = 'synthetic café password phrase';
  const decomposed = 'synthetic cafe\u0301 password phrase';

  test('independent v2 fixture uses profile 1 and NFC; spaces remain significant', () async {
    final bytes = await fixture({'entries': []}, password: composed, version: 2);
    final opened = await VaultCipher.unlock(bytes, decomposed);
    opened.lock();
    await expectLater(VaultCipher.unlock(bytes, '$composed '), throwsA(isA<VaultUnlockException>()));
    final created = await VaultCipher.create(decomposed);
    final header = ByteData.sublistView(created.persistedBytes);
    expect([header.getUint32(8), header.getUint32(12), header.getUint32(16), header.getUint32(20)], [2, 1, 0, 0]);
    final reopened = await VaultCipher.unlock(created.persistedBytes, composed);
    reopened.lock();
    created.lock();
  });

  test('v1 stays byte-exact through save and migrates only on password change', () async {
    final directory = await Directory.systemTemp.createTemp('sm-v1-compatibility-');
    addTearDown(() => directory.delete(recursive: true));
    final bytes = await fixture({'entries': []}, password: decomposed);
    final store = VaultStore(file: File('${directory.path}/legacy.smv'));
    await store.file.writeAsBytes(bytes);
    await expectLater(store.unlock(composed), throwsA(isA<VaultUnlockException>()));
    var session = await store.unlock(decomposed);
    await store.save(session, [VaultEntry.create(title: 'Synthetic migration record')]);
    expect(session.persistedBytes.sublist(0, 116), bytes.sublist(0, 116));
    session = await store.changePassword(session, decomposed, composed);
    expect(ByteData.sublistView(session.persistedBytes).getUint32(8), 2);
    session.lock();
    final reopened = await store.unlock(decomposed);
    expect(reopened.entries.single.title, 'Synthetic migration record');
    reopened.lock();
  });

  test('unknown profiles, reserved parameters and versions fail before derivation', () async {
    final bytes = await fixture({'entries': []}, password: composed, version: 2);
    for (final parameter in [(8, 3), (12, 0), (12, 65536), (16, 1), (20, 0xffffffff)]) {
      final invalid = Uint8List.fromList(bytes);
      ByteData.sublistView(invalid).setUint32(parameter.$1, parameter.$2);
      await expectLater(VaultCipher.unlock(invalid, ''), throwsA(isA<VaultFormatException>()));
    }
  });
}
