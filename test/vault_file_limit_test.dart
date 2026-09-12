import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/crypto/crypto.dart';

import 'vault_sections_test.dart' show fixture;

Map<String, dynamic> fileEntry(int index) => {
  'id': 'synthetic-file-$index',
  'title': 'synthetic-$index.txt',
  'username': '',
  'password': '',
  'notes': '',
  'folderId': null,
  'kind': 'file',
  'attachments': [
    {'id': 'synthetic-$index', 'name': 'synthetic-$index.txt', 'data': ''},
  ],
};

void main() {
  test('5000 small files round trip; excess import is rejected without touching source', () async {
    final entries = List.generate(5000, fileEntry);
    final contents = {'schemaVersion': 4, 'name': null, 'folders': [], 'entries': entries};
    final accepted = await fixture(contents);
    final session = await VaultCipher.unlock(accepted, 'synthetic legacy password');
    expect(session.entries, hasLength(5000));
    session.lock();
    entries.add(fileEntry(5000));
    final rejected = await fixture(contents);
    final directory = await Directory.systemTemp.createTemp('sm-file-limit-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/oversized.smv');
    await source.writeAsBytes(rejected);
    final destination = VaultStore(file: File('${directory.path}/imported.smv'));
    await expectLater(
      destination.importFrom(source, 'synthetic legacy password'),
      throwsA(isA<VaultFormatException>()),
    );
    expect(await source.readAsBytes(), rejected);
    expect(await destination.exists(), isFalse);
  });

  test('legacy attachment totals are bounded before migration', () async {
    final contents = {
      'schemaVersion': 3,
      'name': null,
      'folders': [],
      'entries': List.generate(
        51,
        (entry) => {
          'id': 'synthetic-entry-$entry',
          'title': 'Synthetic entry',
          'username': '',
          'password': '',
          'notes': '',
          'folderId': null,
          'attachments': List.generate(
            100,
            (file) => {
              'id': 'synthetic-$entry-$file',
              'name': 'synthetic.txt',
              'data': '',
            },
          ),
        },
      ),
    };
    final bytes = await fixture(contents);
    await expectLater(VaultCipher.unlock(bytes, 'synthetic legacy password'), throwsA(isA<VaultFormatException>()));
  });
}
