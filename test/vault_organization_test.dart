import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';

import 'vault_sections_test.dart' show fixture;

VaultEntry record(String id, {String? folderId, int order = 0}) => VaultEntry(
  id: id,
  title: id,
  username: 'Synthetic user',
  password: 'Synthetic secret',
  notes: '',
  folderId: folderId,
  order: order,
);

const section = VaultFolder(id: 'section', name: 'Synthetic section', order: 4096);
const other = VaultFolder(id: 'other', name: 'Other section', order: 8192);
const folder = VaultFolder(id: 'folder', name: 'Synthetic folder', parentId: 'section', order: 1024);

void main() {
  test('batch import rebalances a full rank range and preserves mixed order', () {
    const lastSection = VaultFolder(id: 'last', name: 'Last', order: 9007199254740991);
    final organization = VaultOrganization(entries: [record('old')], folders: [lastSection]);
    final files = List.generate(
      50,
      (index) => VaultEntry.file(VaultAttachment.create('synthetic-$index.txt', [index])),
    );
    organization.appendEntries(files, null);
    expect(organization.children(null).map((item) => item.id), ['old', 'last', ...files.map((file) => file.id)]);
    expect(organization.folders.single.order, 1024);
    expect(
      organization.entries.skip(1).map((entry) => entry.attachments.single.bytes.single),
      List.generate(50, (index) => index),
    );
    expect(lastSection.order, 9007199254740991);
  });

  test('mixed items reorder, move between levels and retain source snapshot', () {
    final first = record('a', order: 0);
    final last = record('b', folderId: section.id, order: 2048);
    final file = VaultEntry.file(VaultAttachment.create('synthetic.txt', [1, 2, 3]), id: 'file');
    final source = [first, last, file];
    final organization = VaultOrganization(entries: source, folders: [section, other, folder]);
    organization.move(VaultItem.entry(file), section.id, beforeKey: 'folder:folder');
    expect(organization.children(section.id).map((item) => item.id), ['file', 'folder', 'b']);
    organization.move(VaultItem.entry(last), section.id, beforeKey: 'entry:file');
    expect(organization.children(section.id).map((item) => item.id), ['b', 'file', 'folder']);
    organization.move(VaultItem.entry(first), folder.id);
    organization.move(VaultItem.folder(folder), other.id);
    expect(organization.entries.singleWhere((entry) => entry.id == 'a').folderId, folder.id);
    expect(organization.folders.singleWhere((item) => item.id == folder.id).parentId, other.id);
    organization.move(VaultItem.entry(first), null, beforeKey: 'folder:section');
    expect(organization.children(null).first.id, 'a');
    expect(source.first.folderId, isNull);
    expect(source.last.folderId, isNull);
    expect(file.attachments.single.bytes, [1, 2, 3]);
  });

  test('dense order is rebalanced; no-op, invalid target and cycles cannot change it', () {
    final first = record('a', order: 0);
    final second = record('b', order: 1);
    final organization = VaultOrganization(entries: [first, second], folders: [section, other, folder]);
    organization.move(VaultItem.entry(second), null, beforeKey: 'entry:a');
    expect(organization.children(null).take(2).map((item) => item.id), ['b', 'a']);
    final orders = organization.entries.map((entry) => entry.order).toList();
    organization.move(VaultItem.entry(second), null, beforeKey: 'entry:b');
    expect(organization.entries.map((entry) => entry.order), orders);
    for (final target in [folder.id, section.id]) {
      expect(organization.canMove(const VaultItem.folder(section), target), isFalse);
    }
    expect(organization.canMove(const VaultItem.folder(folder), null), isFalse);
    expect(organization.canMove(const VaultItem.folder(folder), folder.id), isFalse);
    expect(() => organization.move(VaultItem.entry(first), 'missing'), throwsA(isA<VaultFormatException>()));
    expect(organization.entries.map((entry) => entry.order), orders);
  });

  test('deleting folders and sections keeps every secret and attachment', () {
    final organization = VaultOrganization(
      entries: [
        record('root'),
        record('direct', folderId: section.id),
        record('nested', folderId: folder.id),
      ],
      folders: [section, folder],
    );
    organization.deleteFolder(folder);
    expect(organization.children(section.id).map((item) => item.id).toSet(), {'direct', 'nested'});
    organization.deleteFolder(section);
    expect(organization.folders, isEmpty);
    expect(organization.entries.every((entry) => entry.folderId == null), isTrue);
    expect(organization.entries.map((entry) => entry.password), everyElement('Synthetic secret'));

    final nested = VaultOrganization(
      entries: [record('nested', folderId: folder.id)],
      folders: [section, folder],
    );
    nested.deleteFolder(section);
    expect(nested.folders, isEmpty);
    expect(nested.entries.single.folderId, isNull);
  });

  test('schema5 migrates without writing on open; save failure keeps file and session', () async {
    final directory = await Directory.systemTemp.createTemp('sky-organization-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/vault.smv');
    final oldEntries = [record('b'), record('a')].map((entry) => entry.toJson()..remove('order')).toList();
    final bytes = await fixture({
      'schemaVersion': 5,
      'revision': {'lineage': '0123456789abcdef0123456789abcdef', 'clock': <String, int>{}, 'keyEpoch': 0},
      'name': 'Synthetic vault',
      'folders': [
        {'id': section.id, 'name': section.name},
      ],
      'entries': oldEntries,
    });
    await file.writeAsBytes(bytes);
    final store = VaultStore(file: file);
    final session = await store.unlock('synthetic legacy password');
    addTearDown(session.lock);
    final organization = VaultOrganization(entries: session.entries, folders: session.folders);
    expect(organization.children(null).map((item) => item.id), ['b', 'a', 'section']);
    expect(await file.readAsBytes(), bytes);
    organization.folders.add(folder);
    organization.move(VaultItem.entry(session.entries.first), folder.id);
    final failing = VaultStore(
      file: file,
      beforeCommit: () async => throw const FileSystemException('Synthetic failure'),
    );
    await expectLater(
      failing.save(session, organization.entries, folders: organization.folders),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsBytes(), bytes);
    expect(session.entries.first.folderId, isNull);
    expect(session.folders.length, 1);
    await store.save(session, organization.entries, folders: organization.folders);
    final reopened = await store.unlock('synthetic legacy password');
    addTearDown(reopened.lock);
    expect(reopened.entries.first.folderId, folder.id);
    expect(reopened.folders.singleWhere((item) => item.id == folder.id).parentId, section.id);
    expect(reopened.entries.map((entry) => entry.toJson()), session.entries.map((entry) => entry.toJson()));
    final exported = File('${directory.path}/export.smv');
    await store.exportTo(session, exported);
    final imported = await VaultStore(file: File('${directory.path}/import.smv'))
        .importFrom(exported, 'synthetic legacy password');
    addTearDown(imported.lock);
    expect(imported.folders.map((item) => item.toJson()), session.folders.map((item) => item.toJson()));
  });

  test('new empty vault has no sections; invalid hierarchy and positions are rejected', () async {
    final session = await VaultCipher.create('Synthetic phrase 1!');
    addTearDown(session.lock);
    expect(session.entries, isEmpty);
    expect(session.folders, isEmpty);
    for (final folders in <List<VaultFolder>>[
      [folder],
      [section, folder, const VaultFolder(id: 'deep', name: 'Deep', parentId: 'folder')],
      [const VaultFolder(id: 'self', name: 'Self', parentId: 'self')],
      [const VaultFolder(id: 'a', name: 'A', parentId: 'b'), const VaultFolder(id: 'b', name: 'B', parentId: 'a')],
      [const VaultFolder(id: 'negative', name: 'Negative', order: -1)],
    ]) {
      await expectLater(session.encrypt([], folders: folders), throwsA(isA<VaultFormatException>()));
    }
    await expectLater(session.encrypt([record('negative', order: -1)]), throwsA(isA<VaultFormatException>()));
    expect(session.folders, isEmpty);
  });

  test('merge retains hierarchy and one-sided order across encrypted round trip', () async {
    final base = await VaultCipher.create('Synthetic phrase 1!');
    addTearDown(base.lock);
    final bytes = await base.encrypt(
      [record('a', folderId: folder.id), record('b', folderId: folder.id, order: 1024)],
      folders: [section, other, folder],
    );
    final common = await VaultCipher.unlock(bytes, 'Synthetic phrase 1!');
    addTearDown(common.lock);
    final organization = VaultOrganization(entries: common.entries, folders: common.folders);
    organization.move(VaultItem.entry(common.entries.last), folder.id, beforeKey: 'entry:a');
    organization.move(const VaultItem.folder(folder), other.id);
    final local = await VaultCipher.unlock(
      await common.encrypt(organization.entries, folders: organization.folders),
      'Synthetic phrase 1!',
    );
    addTearDown(local.lock);
    final remote = await VaultCipher.unlock(bytes, 'Synthetic phrase 1!');
    addTearDown(remote.lock);
    final merged = await VaultMerge.combine(common, local, remote);
    final result = await VaultCipher.unlock(
      await local.encrypt(merged.entries, folders: merged.folders),
      'Synthetic phrase 1!',
    );
    addTearDown(result.lock);
    expect(
      VaultOrganization(entries: result.entries, folders: result.folders).children(folder.id).map((item) => item.id),
      ['b', 'a'],
    );
    expect(result.folders.singleWhere((item) => item.id == folder.id).parentId, other.id);
    expect(await VaultMerge.sameContents(merged, local), isTrue);
    expect(await VaultMerge.sameContents(merged, common), isFalse);
  });

  test('concurrent section deletion and new child restore the parent without data loss', () async {
    final seed = await VaultCipher.create('Synthetic phrase 1!');
    addTearDown(seed.lock);
    final base = await VaultCipher.unlock(await seed.encrypt([], folders: [section]), 'Synthetic phrase 1!');
    addTearDown(base.lock);
    final local = await VaultCipher.unlock(await base.encrypt([], folders: []), 'Synthetic phrase 1!');
    addTearDown(local.lock);
    final remote = await VaultCipher.unlock(
      await base.encrypt([record('new', folderId: folder.id)], folders: [section, folder]),
      'Synthetic phrase 1!',
    );
    addTearDown(remote.lock);
    final merged = await VaultMerge.combine(base, local, remote);
    final result = await VaultCipher.unlock(
      await local.encrypt(merged.entries, folders: merged.folders),
      'Synthetic phrase 1!',
    );
    addTearDown(result.lock);
    expect(result.folders.map((item) => item.id).toSet(), {section.id, folder.id});
    expect(result.entries.single.folderId, folder.id);
    expect(result.entries.single.password, 'Synthetic secret');
  });

  test('sorting on one device and content editing on another do not duplicate a secret', () async {
    final seed = await VaultCipher.create('Synthetic phrase 1!');
    addTearDown(seed.lock);
    final base = await VaultCipher.unlock(
      await seed.encrypt([record('a'), record('b', order: 1024)]),
      'Synthetic phrase 1!',
    );
    addTearDown(base.lock);
    final organization = VaultOrganization(entries: base.entries, folders: []);
    organization.move(VaultItem.entry(base.entries.last), null, beforeKey: 'entry:a');
    final local = await VaultCipher.unlock(await base.encrypt(organization.entries), 'Synthetic phrase 1!');
    addTearDown(local.lock);
    final edited = VaultEntry.fromJson({...base.entries.first.toJson(), 'notes': 'Synthetic edit'});
    final remote = await VaultCipher.unlock(await base.encrypt([edited, base.entries.last]), 'Synthetic phrase 1!');
    addTearDown(remote.lock);
    final merged = await VaultMerge.combine(base, local, remote);
    expect(merged.conflicts, 0);
    expect(merged.entries.length, 2);
    expect(merged.entries.singleWhere((entry) => entry.id == 'a').notes, 'Synthetic edit');
    expect(VaultOrganization(entries: merged.entries, folders: []).children(null).map((item) => item.id), ['b', 'a']);
  });
}
