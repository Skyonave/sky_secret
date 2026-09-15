import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/settings/vault_tree_preferences.dart';
import 'package:skysecret/ui/vault/controllers/vault_deletion_controller.dart';

void main() {
  test('deleted entry is absent on disk and undo preserves protected fields until session lock', () async {
    final directory = await Directory.systemTemp.createTemp('inline-undo-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = VaultStore(file: File('${directory.path}/vault.smv'));
    const password = 'Synthetic undo test passphrase 2026';
    final session = await store.create(password);
    addTearDown(session.lock);
    final folder = VaultFolder.create('Folder');
    await store.save(
      session,
      [
        VaultEntry.create(
          title: 'Synthetic',
          username: 'User',
          password: 'Synthetic secret',
          notes: 'Notes',
          folderId: folder.id,
        ).withFavorite(true),
        VaultEntry.file(VaultAttachment.create('test.txt', [1, 2, 3]), folderId: folder.id),
      ],
      folders: [folder],
    );
    final snapshot = session.entries.first.inTrash(101);
    final fileSnapshot = session.entries.last.inTrash(101);
    final before = session.entries.map((entry) => entry.toJson()).toList();
    await store.save(session, []);
    final deleted = await store.unlock(password);
    expect(deleted.entries, isEmpty);
    deleted.lock();
    expect(snapshot.password, 'Synthetic secret');
    await store.save(session, [snapshot.inTrash(null), fileSnapshot.inTrash(null)]);
    final restored = await store.unlock(password);
    expect(restored.entries.map((entry) => entry.toJson()).toList(), before);
    restored.lock();
    await store.save(session, []);
    session.lock();
    expect(() => snapshot.password, throwsStateError);
    expect(() => fileSnapshot.attachments.single.bytes, throwsStateError);
  });

  test('undo deadlines are independent and revoked at ten seconds or on lock', () {
    final controller = VaultDeletionController();
    final now = DateTime.utc(2026, 9, 15);
    controller.start('first', 101, now);
    controller.start('second', 202, now.add(const Duration(seconds: 3)));
    expect(controller.remaining('first', now), 10);
    expect(controller.remaining('first', now.add(const Duration(milliseconds: 9999))), 1);
    expect(controller.timestamp('first'), 101);
    controller.expire(now.add(const Duration(seconds: 10)));
    expect(controller.ids, {'second'});
    expect(controller.remaining('second', now.add(const Duration(seconds: 10))), 3);
    controller.remove('second');
    expect(controller.ids, isEmpty);
    controller.start('first', 303, now);
    controller.clear();
    expect(controller.timestamp('first'), isNull);
    expect(controller.remaining('first', now), 0);
  });

  test('collapsed sections persist per vault and concurrent saves keep the latest state', () async {
    final directory = await Directory.systemTemp.createTemp('tree-preferences-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/tree.json');
    final preferences = VaultTreePreferences(file: file);
    await preferences.load();
    final first = preferences.save('vault-a', {'folder', '@favorites'});
    final second = preferences.save('vault-b', {'section'});
    final third = preferences.save('vault-a', {'@favorites'});
    await Future.wait([first, second, third]);
    final loaded = VaultTreePreferences(file: file);
    await loaded.load();
    expect(loaded.collapsed('vault-a'), {'@favorites'});
    expect(loaded.collapsed('vault-b'), {'section'});
    loaded.collapsed('vault-a').clear();
    expect(loaded.collapsed('vault-a'), {'@favorites'});
    await loaded.save('vault-a', {});
    await preferences.load();
    expect(preferences.collapsed('vault-a'), isEmpty);
  });

  test('failed tree writes retain previous state and corrupted input is rejected', () async {
    final directory = await Directory.systemTemp.createTemp('tree-preferences-failure-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/tree.json');
    final preferences = VaultTreePreferences(file: file);
    await preferences.save('vault', {'folder'});
    await file.delete();
    await Directory(file.path).create();
    await expectLater(preferences.save('vault', {}), throwsA(isA<FileSystemException>()));
    expect(preferences.collapsed('vault'), {'folder'});
    await Directory(file.path).delete();
    await file.writeAsString('{"version":1,"vaults":{"vault":[42]}}');
    await expectLater(preferences.load(), throwsFormatException);
    expect(preferences.collapsed('vault'), {'folder'});
  });

  test('new entries precede siblings without changing their order or unrelated folders', () {
    final folder = VaultFolder.create('Folder');
    final older = VaultEntry.create(title: 'Older', username: '', password: '', notes: '').atPosition(folder.id, 0);
    final later = VaultEntry.create(title: 'Later', username: '', password: '', notes: '').atPosition(folder.id, 1024);
    final root = VaultEntry.create(title: 'Root', username: '', password: '', notes: '').atPosition(null, 2048);
    final first = VaultEntry.create(title: 'First', username: '', password: '', notes: '');
    final second = VaultEntry.create(title: 'Second', username: '', password: '', notes: '');
    final organization = VaultOrganization(entries: [older, later, root], folders: [folder]);
    organization.prependEntries([first, second], folder.id);
    expect(organization.children(folder.id).map((item) => item.id), [first.id, second.id, older.id, later.id]);
    expect(organization.entries.singleWhere((entry) => entry.id == root.id).order, 2048);
    expect(organization.entries.singleWhere((entry) => entry.id == first.id).folderId, folder.id);
    expect(() => organization.prependEntries([], 'missing'), throwsA(isA<VaultFormatException>()));
  });
}
