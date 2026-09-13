import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';

import 'vault_sections_test.dart' show fixture;

const collectionPassword = 'Synthetic collection passphrase';

Future<void> saveRevision(VaultSession session, List<VaultEntry> entries) async {
  final bytes = await session.encrypt(entries);
  session.acceptPersisted(bytes, entries, session.folders, session.name);
}

void main() {
  test('metadata validates types and survives every entry copy', () {
    final entry = VaultEntry.create(
      title: 'Synthetic entry',
      password: 'Synthetic secret',
    ).withFavorite(true).inTrash(123);
    for (final copy in [
      entry.inFolder('folder'),
      entry.atPosition(null, 100),
      entry.withConflict('other'),
      VaultEntry.fromJson(entry.toJson()),
    ]) {
      expect(copy.isFavorite, isTrue);
      expect(copy.deletedAt, 123);
      expect(copy.password, 'Synthetic secret');
    }
    for (final invalid in [
      {...entry.toJson(), 'favorite': 'true'},
      {...entry.toJson(), 'favorite': null},
      {...entry.toJson(), 'deletedAt': -1},
      {...entry.toJson(), 'deletedAt': 1.5},
      {...entry.toJson(), 'deletedAt': 8640000000000001},
    ]) {
      expect(() => VaultEntry.fromJson(invalid), throwsA(isA<VaultFormatException>()));
    }
    expect(() => VaultEntry.fromJson(entry.toJson(), metadata: false), throwsA(isA<VaultFormatException>()));
  });

  test('trash restore preserves position and favorites; missing folder falls back to root', () {
    final folder = VaultFolder.create('Synthetic folder');
    final entry = VaultEntry.create(
      title: 'Synthetic entry',
      folderId: folder.id,
    ).atPosition(folder.id, 4096).withFavorite(true);
    final collection = VaultCollection(entries: [entry], folders: [folder]);
    expect(collection.delete(entry.id, 123), isTrue);
    expect(collection.active, isEmpty);
    expect(collection.trash.single.order, 4096);
    expect(entry.isDeleted, isFalse);
    expect(collection.restore(entry.id), isTrue);
    expect(collection.active.single.folderId, folder.id);
    expect(collection.active.single.isFavorite, isTrue);
    collection.delete(entry.id, 456);
    final missing = VaultCollection(entries: collection.entries, folders: []);
    missing.restore(entry.id);
    expect(missing.active.single.folderId, isNull);
    expect(missing.purge(entry.id), isFalse);
    missing.delete(entry.id, 789);
    expect(missing.purge(entry.id), isTrue);
    expect(missing.entries, isEmpty);
  });

  test('schema 7 opens without mutation; schema 8 metadata survives encrypted import and rotation', () async {
    final directory = await Directory.systemTemp.createTemp('sky-collection-');
    addTearDown(() => directory.delete(recursive: true));
    final store = VaultStore(file: File('${directory.path}/vault.smv'));
    final entry = VaultEntry.create(title: 'Synthetic legacy entry');
    final bytes = await fixture({
      'schemaVersion': 7,
      'name': null,
      'folders': [],
      'entries': [entry.toJson()],
      'revision': VaultRevision(VaultRevision.randomId(), {}).toJson(),
    }, password: collectionPassword);
    await store.file.writeAsBytes(bytes);
    var session = await store.unlock(collectionPassword);
    addTearDown(() => session.lock());
    expect(await store.file.readAsBytes(), bytes);
    expect(session.entries.single.isFavorite, isFalse);
    final file = VaultEntry.file(VaultAttachment.create('synthetic.txt', [1, 2, 3])).withFavorite(true).inTrash(987);
    await store.save(session, [session.entries.single.withFavorite(true), file]);
    session = await store.changePassword(session, collectionPassword, 'Synthetic replacement passphrase');
    final importedStore = VaultStore(file: File('${directory.path}/import.smv'));
    final imported = await importedStore.importEncryptedSnapshot(
      session.persistedBytes,
      'Synthetic replacement passphrase',
    );
    addTearDown(imported.lock);
    expect(imported.entries.first.isFavorite, isTrue);
    expect(imported.entries.last.deletedAt, 987);
    expect(imported.entries.last.attachments.single.bytes, [1, 2, 3]);
    final retained = imported.entries.last.inTrash(null);
    imported.lock();
    expect(() => retained.attachments.single.bytes, throwsStateError);
  });

  test('failed trash write preserves both in-memory entries and committed bytes', () async {
    final directory = await Directory.systemTemp.createTemp('sky-trash-failure-');
    addTearDown(() => directory.delete(recursive: true));
    final store = VaultStore(file: File('${directory.path}/vault.smv'));
    final session = await store.create(collectionPassword);
    addTearDown(session.lock);
    await store.save(session, [VaultEntry.create(title: 'Synthetic entry')]);
    final before = session.persistedBytes;
    final changed = VaultCollection(entries: session.entries, folders: session.folders)
      ..delete(session.entries.single.id, 123);
    final failing = VaultStore(
      file: store.file,
      beforeCommit: () async => throw const FileSystemException('Synthetic failure'),
    );
    await expectLater(failing.save(session, changed.entries), throwsA(isA<FileSystemException>()));
    expect(session.entries.single.isDeleted, isFalse);
    expect(await store.file.readAsBytes(), before);
  });

  test('trash remains subject to entry limits', () async {
    final session = await VaultCipher.create(collectionPassword);
    addTearDown(session.lock);
    final entries = List.generate(
      VaultCipher.maxEntries + 1,
      (index) => VaultEntry.create(title: 'Synthetic $index').inTrash(123),
    );
    await expectLater(session.encrypt(entries), throwsA(isA<VaultFormatException>()));
    expect(session.entries, isEmpty);
  });

  test('favorite and deletion merge independently without restoring deleted entries', () async {
    final base = await VaultCipher.create(collectionPassword);
    addTearDown(base.lock);
    await saveRevision(base, [VaultEntry.create(title: 'Synthetic entry')]);
    final local = await base.openRevision(base.persistedBytes);
    final remote = await base.openRevision(base.persistedBytes);
    await saveRevision(local, [local.entries.single.inTrash(123)]);
    await saveRevision(remote, [remote.entries.single.withFavorite(true)]);
    final merged = await VaultMerge.combine(base, local, remote);
    expect(merged.conflicts, 0);
    expect(merged.entries.single.isDeleted, isTrue);
    expect(merged.entries.single.isFavorite, isTrue);
    await saveRevision(remote, [remote.entries.single.inTrash(456)]);
    final bothDeleted = await VaultMerge.combine(base, local, remote);
    expect(bothDeleted.conflicts, 0);
    expect(bothDeleted.entries.single.deletedAt, 456);
  });

  test('concurrent edit and trash preserve both variants; permanent removal beats an unchanged branch', () async {
    final base = await VaultCipher.create(collectionPassword);
    addTearDown(base.lock);
    await saveRevision(base, [VaultEntry.create(title: 'Synthetic entry', password: 'Original synthetic password')]);
    final local = await base.openRevision(base.persistedBytes);
    final remote = await base.openRevision(base.persistedBytes);
    await saveRevision(local, [local.entries.single.inTrash(123)]);
    await saveRevision(remote, [
      VaultEntry.fromJson({...remote.entries.single.toJson(), 'password': 'Changed synthetic password'}),
    ]);
    final merged = await VaultMerge.combine(base, local, remote);
    expect(merged.entries, hasLength(2));
    expect(merged.conflicts, 1);
    expect(merged.entries.where((entry) => entry.isDeleted == false).single.password, 'Changed synthetic password');
    expect(merged.entries.where((entry) => entry.isDeleted).single.password, 'Original synthetic password');
    final removed = await local.openRevision(local.persistedBytes);
    final unchanged = await local.openRevision(local.persistedBytes);
    await saveRevision(removed, []);
    final purged = await VaultMerge.combine(local, removed, unchanged);
    expect(purged.entries, isEmpty);
  });
}
