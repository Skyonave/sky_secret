import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';

Future<Uint8List> fixture(
  Map<String, dynamic> contents, {
  String password = 'synthetic legacy password',
  int version = 1,
}) async {
  final header = Uint8List(56)..setRange(0, 8, [83, 77, 86, 65, 85, 76, 84, 0]);
  final view = ByteData.sublistView(header);
  view.setUint32(8, version);
  view.setUint32(12, version == 1 ? 65536 : 1);
  view.setUint32(16, version == 1 ? 3 : 0);
  view.setUint32(20, version == 1 ? 4 : 0);
  header.fillRange(24, 40, 2);
  header.fillRange(40, 56, 3);
  final kek =
      await DartArgon2id(
        memory: 65536,
        iterations: 3,
        parallelism: 4,
        hashLength: 32,
        maxIsolates: 0,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: header.sublist(24, 40),
      );
  final keyBytes = List.filled(32, 4);
  final aes = AesGcm.with256bits();
  final wrapped = await aes.encrypt(
    keyBytes,
    secretKey: kek,
    nonce: List.filled(12, 5),
    aad: [...utf8.encode('SMV$version/wrap'), ...header],
  );
  final prefix = [...header, ...wrapped.concatenation()];
  final encrypted = await aes.encrypt(
    utf8.encode(jsonEncode(contents)),
    secretKey: SecretKey(keyBytes),
    nonce: List.filled(12, 6),
    aad: [...utf8.encode('SMV$version/data'), ...prefix],
  );
  kek.destroy();
  return Uint8List.fromList([...prefix, ...encrypted.concatenation()]);
}

void main() {
  const legacyEntry = {
    'id': 'synthetic-id',
    'title': 'Legacy synthetic record',
    'username': 'synthetic-user',
    'password': 'synthetic-password',
    'notes': 'Synthetic note',
  };

  test('legacy read is read-only; migration, names, moves and deletions survive reopen', () async {
    final dir = await Directory.systemTemp.createTemp('sm-sections-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/vault.smv');
    final before = await fixture({
      'entries': [legacyEntry],
    });
    await file.writeAsBytes(before);
    final store = VaultStore(file: file);
    final session = await store.unlock('synthetic legacy password');
    expect(session.name, isNull);
    expect(session.folders, isEmpty);
    expect(session.entries.single.folderId, isNull);
    expect(await file.readAsBytes(), before);
    final folder = VaultFolder.create('Synthetic folder');
    final changed = session.entries.single.inFolder(folder.id);
    final failing = VaultStore(
      file: file,
      beforeCommit: () async => throw const FileSystemException('Synthetic failure'),
    );
    await expectLater(
      failing.save(
        session,
        [changed],
        folders: [folder],
        name: 'Synthetic vault',
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsBytes(), before);
    expect(session.folders, isEmpty);
    expect(session.name, isNull);

    await store.save(
      session,
      [changed],
      folders: [folder],
      name: 'Synthetic vault',
    );
    final migrated = await file.readAsBytes();
    expect(migrated.sublist(0, 116), before.sublist(0, 116));
    expect(latin1.decode(migrated).contains(folder.name), isFalse);
    expect(latin1.decode(migrated).contains('Synthetic vault'), isFalse);
    final expectedEntry = changed.toJson();
    session.lock();
    expect(changed.toJson, throwsStateError);
    final reopened = await store.unlock('synthetic legacy password');
    expect(reopened.name, 'Synthetic vault');
    expect(reopened.folders.single.toJson(), folder.toJson());
    expect(reopened.entries.single.toJson(), expectedEntry);
    await store.save(
      reopened,
      reopened.entries,
      folders: [VaultFolder(id: folder.id, name: 'Renamed folder')],
    );
    expect(reopened.entries.single.folderId, folder.id);
    await store.save(reopened, [
      reopened.entries.single.inFolder(null),
    ], folders: []);
    expect(reopened.entries.single.password, legacyEntry['password']);
    expect(reopened.folders, isEmpty);
    await store.save(reopened, []);
    reopened.lock();
    final deleted = await store.unlock('synthetic legacy password');
    expect(deleted.entries, isEmpty);
    expect(deleted.name, 'Synthetic vault');
    deleted.lock();
  });

  test('invalid references, duplicate IDs and limits cannot replace committed data', () async {
    final session = await VaultCipher.create('Synthetic phrase 1!');
    final entry = VaultEntry.create(
      title: 'Synthetic record',
      folderId: 'missing',
    );
    await expectLater(
      session.encrypt([entry]),
      throwsA(isA<VaultFormatException>()),
    );
    final folder = VaultFolder.create('Synthetic section');
    await expectLater(
      session.encrypt([], folders: [folder, folder]),
      throwsA(isA<VaultFormatException>()),
    );
    await expectLater(
      session.encrypt([], name: ' '),
      throwsA(isA<VaultFormatException>()),
    );
    await expectLater(
      session.encrypt(
        [],
        folders: List.generate(101, (i) => VaultFolder.create('Synthetic $i')),
      ),
      throwsA(isA<VaultFormatException>()),
    );
    final invalid = await fixture({
      'schemaVersion': 5,
      'entries': [],
      'folders': [],
      'name': null,
    });
    await expectLater(
      VaultCipher.unlock(invalid, 'synthetic legacy password'),
      throwsA(isA<VaultFormatException>()),
    );
    session.lock();
  });
}
