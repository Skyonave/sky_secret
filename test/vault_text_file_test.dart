import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/files/text_document.dart';
import 'package:skysecret/core/files/vault_text_file.dart';

void main() {
  test('normalizes txt extension and rejects unsafe or empty names', () {
    expect(VaultTextFile.fileName('  Synthetic  '), 'Synthetic.txt');
    expect(VaultTextFile.fileName('Synthetic.TXT'), 'Synthetic.txt');
    expect(VaultTextFile.fileName('Synthetic.md'), 'Synthetic.md.txt');
    expect(VaultTextFile.fileName('я' * 236).length, 240);
    for (final name in ['', ' ', '.txt', '../secret', r'folder\file', 'CON', 'nul.txt', 'a.', 'a*.txt', 'я' * 237]) {
      expect(
        () => VaultTextFile.fileName(name),
        throwsA(isA<TextFileException>().having((e) => e.problem, 'problem', TextFileProblem.invalidName)),
        reason: name,
      );
    }
  });

  test('creates empty UTF-8 files before mixed siblings in root, section and folder', () {
    const section = VaultFolder(id: 'section', name: 'Synthetic section');
    const folder = VaultFolder(id: 'folder', name: 'Synthetic folder', parentId: 'section');
    final organization = VaultOrganization(entries: [], folders: [section, folder]);
    for (final parent in [null, section.id, folder.id]) {
      final previous = organization.children(parent).map((item) => item.id).toList();
      final entry = VaultTextFile.prepare(name: 'Synthetic', organization: organization, folderId: parent);
      expect(organization.children(parent).map((item) => item.id), [entry.id, ...previous]);
      expect(entry.folderId, parent);
      expect(entry.isFile, isTrue);
      final file = entry.attachments.single;
      expect(file.size, 0);
      final document = TextDocument.decode(file.name, file.bytes)!;
      expect(document.text, '');
      expect(document.encoding, 'UTF-8');
    }
  });

  test('duplicate names and missing destinations leave the draft organization unchanged', () {
    final organization = VaultOrganization(entries: [], folders: []);
    final existing = VaultTextFile.prepare(name: 'Synthetic', organization: organization);
    for (final (name, parent, problem) in [
      ('synthetic.TXT', null, TextFileProblem.nameTaken),
      ('Other', 'removed-folder', TextFileProblem.location),
    ]) {
      expect(
        () => VaultTextFile.prepare(name: name, organization: organization, folderId: parent),
        throwsA(isA<TextFileException>().having((e) => e.problem, 'problem', problem)),
      );
      expect(organization.entries.single, same(existing));
    }
  });

  test('file count limit rejects creation before adding a record', () {
    final existing = VaultEntry.file(VaultAttachment.create('Existing.txt', const []));
    final organization = VaultOrganization(entries: List.filled(VaultCipher.maxFiles, existing), folders: []);
    expect(
      () => VaultTextFile.prepare(name: 'New', organization: organization),
      throwsA(isA<TextFileException>().having((e) => e.problem, 'problem', TextFileProblem.limit)),
    );
    expect(organization.entries.length, VaultCipher.maxFiles);
  });

  test('new document survives encrypted save; failed creation leaves no empty entry', () async {
    final directory = await Directory.systemTemp.createTemp('skysecret-text-create-');
    addTearDown(() => directory.delete(recursive: true));
    final store = VaultStore(file: File('${directory.path}/synthetic.smv'));
    final session = await store.create('Synthetic master password 1!');
    addTearDown(session.lock);
    final before = await store.file.readAsBytes();
    final organization = VaultOrganization(entries: session.entries, folders: session.folders);
    final entry = VaultTextFile.prepare(name: 'Synthetic', organization: organization);
    final failing = VaultStore(
      file: store.file,
      beforeCommit: () async => throw const FileSystemException('Synthetic write failure'),
    );
    await expectLater(failing.save(session, organization.entries), throwsA(isA<FileSystemException>()));
    expect(session.entries, isEmpty);
    expect(await store.file.readAsBytes(), before);
    await store.save(session, organization.entries);
    final reopened = await store.unlock('Synthetic master password 1!');
    addTearDown(reopened.lock);
    expect(reopened.entries.single.id, entry.id);
    expect(reopened.entries.single.attachments.single.bytes, isEmpty);
    expect(reopened.entries.single.title, 'Synthetic.txt');
    final emptyFile = reopened.entries.single.attachments.single;
    final document = TextDocument.decode(emptyFile.name, emptyFile.bytes)!;
    final contents = document.encode('Synthetic text\nПример');
    final edited = VaultEntry.file(
      VaultAttachment(id: emptyFile.id, name: emptyFile.name, bytes: contents),
      id: entry.id,
    );
    contents.fillRange(0, contents.length, 0);
    await store.save(reopened, [edited]);
    reopened.lock();
    final editedSession = await store.unlock('Synthetic master password 1!');
    addTearDown(editedSession.lock);
    final stored = editedSession.entries.single.attachments.single;
    expect(TextDocument.decode(stored.name, stored.bytes)!.text, 'Synthetic text\nПример');
  });
}
