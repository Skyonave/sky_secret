import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';

void main() {
  test('lock revokes original, moved, replaced and removed secret references', () async {
    final directory = await Directory.systemTemp.createTemp('sky-lifetime-');
    addTearDown(() => directory.delete(recursive: true));
    final store = VaultStore(file: File('${directory.path}/vault.smv'));
    final session = await store.create('Synthetic password 1!');
    addTearDown(session.lock);
    final folder = VaultFolder.create('Synthetic folder');
    final input = VaultEntry.create(
      title: 'Synthetic entry',
      username: 'Synthetic user',
      password: 'Synthetic secret',
      notes: 'Synthetic notes',
    );
    final attachment = VaultAttachment.create('synthetic.txt', [1, 2, 3]);
    await store.save(
      session,
      [input, VaultEntry.file(attachment)],
      folders: [folder],
    );
    final old = session.entries.first;
    final moved = old.inFolder(folder.id);
    final file = session.entries.last;
    await store.save(session, [moved, file.inFolder(folder.id)]);
    expect(
      identical(session.entries.last.attachments.single, attachment),
      isTrue,
    );
    expect(old.password, 'Synthetic secret');
    await store.save(session, [
      VaultEntry.create(title: 'Replacement', password: 'New synthetic'),
    ]);
    final latest = session.entries.single;
    session.lock();
    session.lock();
    for (final entry in [input, old, moved, file, latest]) {
      expect(() => entry.username, throwsStateError);
      expect(() => entry.password, throwsStateError);
      expect(() => entry.notes, throwsStateError);
      expect(() => entry.hasPassword, throwsStateError);
      expect(entry.toJson, throwsStateError);
    }
    expect(() => attachment.bytes, throwsStateError);
    expect(attachment.toJson, throwsStateError);
    expect(session.entries, isEmpty);
  });

  test(
    'lock cancels encryption before commit and revokes pending entries',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sky-cancel-save-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = VaultStore(file: File('${directory.path}/vault.smv'));
      final session = await store.create('Synthetic password 1!');
      final before = await store.file.readAsBytes();
      final entry = VaultEntry.create(
        title: 'Synthetic',
        password: 'Synthetic secret',
      );
      final saving = store.save(session, [entry]);
      final cancelled = expectLater(saving, throwsStateError);
      session.lock();
      await cancelled;
      expect(() => entry.password, throwsStateError);
      expect(await store.file.readAsBytes(), before);
      expect(directory.listSync().whereType<Directory>(), isEmpty);
    },
  );

  test('sharing entries across sessions does not share revocation', () async {
    final first = await VaultCipher.create('Synthetic first password 1!');
    final second = await VaultCipher.create('Synthetic second password 1!');
    addTearDown(first.lock);
    addTearDown(second.lock);
    final entries = [
      VaultEntry.create(title: 'Synthetic', password: 'Synthetic secret'),
    ];
    first.acceptPersisted(await first.encrypt(entries), entries, [], null);
    second.acceptPersisted(
      await second.encrypt(first.entries),
      first.entries,
      [],
      null,
    );
    final old = first.entries.single;
    first.lock();
    expect(() => old.password, throwsStateError);
    expect(second.entries.single.password, 'Synthetic secret');
    final reopened = await VaultCipher.unlock(
      second.persistedBytes,
      'Synthetic second password 1!',
    );
    addTearDown(reopened.lock);
    expect(reopened.entries.single.password, 'Synthetic secret');
  });
}
