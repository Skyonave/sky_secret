import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/files/text_document.dart';

import 'vault_sections_test.dart' show fixture;

void main() {
  test('schema 3 attachments become independent files; failed migration preserves source', () async {
    final dir = await Directory.systemTemp.createTemp('sm-file-kind-test-');
    addTearDown(() => dir.delete(recursive: true));
    final attachment = VaultAttachment.create(
      'synthetic.txt',
      utf8.encode('Synthetic contents'),
    );
    final source = await fixture({
      'schemaVersion': 3,
      'name': 'Synthetic',
      'folders': [
        {'id': 'folder', 'name': 'Synthetic folder'},
      ],
      'entries': [
        {
          'id': 'file:${attachment.id}',
          'title': 'Synthetic text',
          'username': 'Synthetic login',
          'password': 'Synthetic secret',
          'notes': 'Synthetic note',
          'folderId': 'folder',
          'attachments': [attachment.toJson()],
        },
      ],
    });
    final file = File('${dir.path}/vault.smv');
    await file.writeAsBytes(source);
    final store = VaultStore(file: file);
    final session = await store.unlock('synthetic legacy password');
    expect(session.entries.length, 2);
    expect(session.entries.first.isFile, isFalse);
    expect(session.entries.first.attachments, isEmpty);
    expect(session.entries.last.isFile, isTrue);
    expect(session.entries.last.folderId, 'folder');
    expect(session.entries.last.attachments.single.bytes, attachment.bytes);
    expect(session.entries.map((e) => e.id).toSet().length, 2);
    expect(await file.readAsBytes(), source);
    final failing = VaultStore(
      file: file,
      beforeCommit: () async => throw const FileSystemException('Synthetic failure'),
    );
    await expectLater(
      failing.save(session, session.entries),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsBytes(), source);
    await store.save(session, session.entries);
    final reopened = await store.unlock('synthetic legacy password');
    expect(
      reopened.entries.map((e) => e.toJson()).toList(),
      session.entries.map((e) => e.toJson()).toList(),
    );
    await store.save(reopened, [reopened.entries.last.inFolder(null)]);
    final moved = await store.unlock('synthetic legacy password');
    expect(moved.entries.single.isFile, isTrue);
    expect(moved.entries.single.folderId, isNull);
    expect(moved.entries.single.attachments.single.bytes, attachment.bytes);
    session.lock();
    reopened.lock();
    moved.lock();
  });
  test(
    'plain text formats preserve BOM, encoding and line endings on edit',
    () {
      for (final name in [
        'file.txt',
        'file.md',
        'file.json',
        'file.csv',
        'file.yaml',
        'file.xml',
        'file.dart',
      ]) {
        final doc = TextDocument.decode(
          name,
          Uint8List.fromList(utf8.encode('Synthetic\r\ntext')),
        )!;
        expect(doc.text, 'Synthetic\ntext');
        expect(
          utf8.decode(doc.encode('${doc.text}\nupdated')),
          'Synthetic\r\ntext\r\nupdated',
        );
      }
      for (final endian in [Endian.little, Endian.big]) {
        const sample = 'Синтетический\r\nтекст 🔐';
        final bytes = Uint8List(2 + sample.length * 2);
        final data = ByteData.sublistView(bytes);
        data.setUint16(0, 0xfeff, endian);
        for (var i = 0; i < sample.length; i++) {
          data.setUint16(2 + 2 * i, sample.codeUnitAt(i), endian);
        }
        final doc = TextDocument.decode('file.txt', bytes)!;
        expect(doc.encode(doc.text), bytes);
        expect(
          TextDocument.decode(
            'file.txt',
            doc.encode('${doc.text}\nChanged'),
          )!.text,
          '${doc.text}\nChanged',
        );
      }
      final bom = Uint8List.fromList([
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode('Synthetic'),
      ]);
      expect(TextDocument.decode('file.txt', bom)!.encode('Synthetic'), bom);
      expect(TextDocument.decode('file.bin', Uint8List.fromList([65])), isNull);
      expect(
        TextDocument.decode('file.txt', Uint8List.fromList([0xff, 0x00])),
        isNull,
      );
      expect(
        TextDocument.decode(
          'file.txt',
          Uint8List.fromList([0xff, 0xfe, 0x00, 0xd8]),
        ),
        isNull,
      );
      expect(
        TextDocument.decode('file.txt', Uint8List.fromList([65, 0])),
        isNull,
      );
      expect(
        TextDocument.decode('file.txt', Uint8List(TextDocument.maxBytes + 1)),
        isNull,
      );
    },
  );
}
