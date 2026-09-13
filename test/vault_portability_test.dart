import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';

import 'vault_sections_test.dart' show fixture;

void main() {
  test(
    'extensionless backup preserves binary files; imports never replace data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sm-portable-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final original = VaultStore(file: File('${directory.path}/original.smv'));
      final session = await original.create(
        'Synthetic original password 1!',
        name: 'Synthetic vault',
      );
      final binary = Uint8List.fromList(List.generate(65537, (i) => i % 256));
      final file = VaultAttachment.create('synthetic.bin', binary);
      final empty = VaultAttachment.create('empty.txt', []);
      final folder = VaultFolder.create('Synthetic folder');
      await original.save(
        session,
        [
          VaultEntry.create(
            title: 'Synthetic entry',
            folderId: folder.id,
            password: 'Synthetic secret',
          ),
          VaultEntry.file(file, folderId: folder.id),
          VaultEntry.file(empty, folderId: folder.id),
        ],
        folders: [folder],
      );
      final backup = File('${directory.path}/backup');
      await original.exportTo(session, backup);
      expect(await backup.readAsBytes(), session.persistedBytes);
      if (Platform.isWindows) {
        expect(await File('${backup.path}.lock').exists(), isFalse);
      }
      final restoredStore = VaultStore(
        file: File('${directory.path}/clean-profile/restored.smv'),
      );
      final restored = await restoredStore.importFrom(
        backup,
        'Synthetic original password 1!',
      );
      expect(restored.name, session.name);
      expect(
        restored.entries.map((e) => e.toJson()).toList(),
        session.entries.map((e) => e.toJson()).toList(),
      );
      final extracted = File('${directory.path}/output.bin');
      await VaultStore.extract(
        restored,
        restored.entries[1].attachments.single,
        extracted,
      );
      expect(await extracted.readAsBytes(), binary);
      if (Platform.isWindows) {
        expect(await File('${extracted.path}.lock').exists(), isFalse);
        final concurrent = File('${directory.path}/concurrent.smv');
        Future<bool> exportOnce() async {
          try {
            await original.exportTo(session, concurrent);
            return true;
          } on VaultConflictException {
            return false;
          } on FileSystemException {
            return false;
          }
        }

        final outcomes = await Future.wait([exportOnce(), exportOnce()]);
        expect(outcomes.where((success) => success), hasLength(1));
        expect(await concurrent.readAsBytes(), session.persistedBytes);
        expect(await File('${concurrent.path}.lock').exists(), isFalse);
      }
      final unchanged = await restoredStore.file.readAsBytes();
      await expectLater(
        restoredStore.importFrom(backup, 'Synthetic original password 1!'),
        throwsA(isA<VaultConflictException>()),
      );
      expect(await restoredStore.file.readAsBytes(), unchanged);
      await expectLater(
        original.exportTo(session, backup),
        throwsA(isA<VaultConflictException>()),
      );
      await expectLater(
        VaultStore.extract(
          restored,
          restored.entries[1].attachments.single,
          extracted,
        ),
        throwsA(isA<VaultConflictException>()),
      );
      expect(await extracted.readAsBytes(), binary);
      final invalid = File('${directory.path}/corrupt.smv');
      final corrupt = await backup.readAsBytes();
      corrupt[corrupt.length - 1] ^= 1;
      await invalid.writeAsBytes(corrupt);
      final untouched = VaultStore(
        file: File('${directory.path}/must-not-exist.smv'),
      );
      await expectLater(
        untouched.importFrom(invalid, 'Synthetic original password 1!'),
        throwsA(isA<VaultUnlockException>()),
      );
      await expectLater(
        untouched.importFrom(backup, 'Incorrect synthetic password'),
        throwsA(isA<VaultUnlockException>()),
      );
      expect(await untouched.exists(), isFalse);
      restored.lock();
      session.lock();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'rotation changes salt/key, preserves files, old copies and atomic failure',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sm-rotate-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = VaultStore(file: File('${directory.path}/vault.smv'));
      final session = await store.create('Synthetic old password 1!');
      await store.save(session, [
        VaultEntry.file(VaultAttachment.create('file.bin', [0, 255, 1])),
      ]);
      final before = session.persistedBytes;
      final entries = session.entries;
      final expectedEntry = entries.single.toJson();
      final failing = VaultStore(
        file: store.file,
        beforeCommit: () async => throw const FileSystemException('Synthetic failure'),
      );
      await expectLater(
        failing.changePassword(
          session,
          'Synthetic old password 1!',
          'Synthetic new password 1!',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.file.readAsBytes(), before);
      expect(session.isLocked, isFalse);
      expect(entries.single.toJson(), expectedEntry);
      await expectLater(
        store.changePassword(
          session,
          'Wrong synthetic password',
          'Synthetic new password 1!',
        ),
        throwsA(isA<VaultUnlockException>()),
      );
      final replacement = await store.changePassword(
        session,
        'Synthetic old password 1!',
        'Synthetic new password 1!',
      );
      expect(session.isLocked, isTrue);
      expect(entries.single.toJson, throwsStateError);
      expect(replacement.entries.single.toJson(), expectedEntry);
      expect(
        replacement.persistedBytes.sublist(24, 116),
        isNot(before.sublist(24, 116)),
      );
      await expectLater(
        store.unlock('Synthetic old password 1!'),
        throwsA(isA<VaultUnlockException>()),
      );
      final current = await store.unlock('Synthetic new password 1!');
      expect(current.entries.single.attachments.single.bytes, [0, 255, 1]);
      final oldBackup = await VaultCipher.unlock(
        before,
        'Synthetic old password 1!',
      );
      expect(oldBackup.entries.single.toJson(), expectedEntry);
      replacement.lock();
      current.lock();
      oldBackup.lock();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'lock during commit cancels write and import; schema 2 remains readable',
    () async {
      final directory = await Directory.systemTemp.createTemp('sm-lock-test-');
      addTearDown(() => directory.delete(recursive: true));
      final old = await fixture({
        'schemaVersion': 2,
        'name': 'Synthetic legacy',
        'folders': [],
        'entries': [
          {
            'id': 'one',
            'title': 'Synthetic',
            'username': '',
            'password': '',
            'notes': '',
            'folderId': null,
          },
        ],
      });
      final file = File('${directory.path}/old.smv');
      await file.writeAsBytes(old);
      final store = VaultStore(file: file);
      final session = await store.unlock('synthetic legacy password');
      expect(session.entries.single.attachments, isEmpty);
      final interrupted = VaultStore(
        file: file,
        beforeCommit: () async => session.lock(),
      );
      await expectLater(interrupted.save(session, []), throwsStateError);
      expect(await file.readAsBytes(), old);
      final destination = VaultStore(
        file: File('${directory.path}/cancelled.smv'),
      );
      await expectLater(
        destination.importFrom(
          file,
          'synthetic legacy password',
          allowed: () => false,
        ),
        throwsStateError,
      );
      expect(await destination.exists(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'attachment names, per-file limits and duplicate IDs are rejected',
    () async {
      for (final name in [
        '../escape',
        r'a\b',
        'CON',
        'nul.txt',
        'LPT1.log',
        'x:ads',
        'trailing.',
        'trailing ',
        '',
      ]) {
        expect(
          () => VaultAttachment.create(name, []),
          throwsA(isA<VaultFormatException>()),
        );
      }
      expect(
        () => VaultAttachment.create(
          'large.bin',
          Uint8List(VaultCipher.maxAttachmentBytes + 1),
        ),
        throwsA(isA<VaultFormatException>()),
      );
      final session = await VaultCipher.create('Synthetic password 1!');
      final attachment = VaultAttachment.create('test.bin', [1]);
      await expectLater(
        session.encrypt([
          VaultEntry.create(
            title: 'Synthetic',
            attachments: [attachment, attachment],
          ),
        ]),
        throwsA(isA<VaultFormatException>()),
      );
      session.lock();
    },
  );
}
