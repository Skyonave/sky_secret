import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/crypto/crypto.dart';

void main() {
  const oldPassword = 'synthetic old rotation phrase';
  const newPassword = 'synthetic replacement rotation phrase';
  late Directory directory;
  late VaultStore store;
  late VaultSession session;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sm-rotation-test-');
    store = VaultStore(file: File('${directory.path}/vault.smv'));
    session = await store.create(oldPassword);
    await store.save(session, [VaultEntry.create(title: 'Synthetic retained record')]);
    await store.cacheBaseline('a' * 40, session.persistedBytes);
  });
  tearDown(() async {
    session.lock();
    await directory.delete(recursive: true);
  });

  test('cleanup failure preserves committed password and retries after restart', () async {
    final failing = VaultStore(
      file: store.file,
      beforeSnapshotCleanup: () async {
        throw const FileSystemException('Synthetic deletion failure');
      },
    );
    session = await failing.changePassword(session, oldPassword, newPassword);
    expect(failing.snapshotCleanupPending, isTrue);
    expect(await store.history(), isNotEmpty);
    expect(await store.readBaseline('a' * 40), isNotNull);
    expect(await File('${store.file.path}.rotation').length(), 116);
    await expectLater(store.unlock(oldPassword), throwsA(isA<VaultUnlockException>()));
    final reopened = await store.unlock(newPassword);
    expect(reopened.entries.single.title, 'Synthetic retained record');
    reopened.lock();
    expect(store.snapshotCleanupPending, isFalse);
    expect(await store.history(), isEmpty);
    expect(await store.readBaseline('a' * 40), isNull);
    expect(await File('${store.file.path}.rotation').exists(), isFalse);
  });

  test('failed replacement preserves original vault and recovery history', () async {
    final before = session.persistedBytes;
    final failing = VaultStore(
      file: store.file,
      beforeCommit: () async {
        throw const FileSystemException('Synthetic staging failure');
      },
    );
    await expectLater(failing.changePassword(session, oldPassword, newPassword), throwsA(isA<FileSystemException>()));
    expect(session.isLocked, isFalse);
    expect(await store.readEncryptedSnapshot(), before);
    expect(await store.history(), hasLength(1));
    expect(await store.readBaseline('a' * 40), before);
    expect(await File('${store.file.path}.rotation').exists(), isFalse);
  });

  test('stale intent keeps old history and cannot apply uncommitted replacement', () async {
    final replacement = await session.changePassword(newPassword);
    await File('${store.file.path}.rotation').writeAsBytes(replacement.persistedBytes.sublist(0, 116), flush: true);
    replacement.lock();
    final opened = await store.unlock(oldPassword);
    opened.lock();
    expect(await store.history(), hasLength(1));
    expect(await store.readBaseline('a' * 40), isNotNull);
    expect(await File('${store.file.path}.rotation').exists(), isFalse);
  });

  test('unknown files survive cleanup and leave a warning until obstruction is removed', () async {
    final unknown = File('${store.historyDirectory.path}/keep.txt');
    await unknown.writeAsString('Synthetic unrelated content');
    session = await store.changePassword(session, oldPassword, newPassword);
    expect(store.snapshotCleanupPending, isTrue);
    expect(await unknown.readAsString(), 'Synthetic unrelated content');
    await unknown.delete();
    final reopened = await store.unlock(newPassword);
    reopened.lock();
    expect(store.snapshotCleanupPending, isFalse);
    expect(await store.history(), isEmpty);
    expect(await store.readBaseline('a' * 40), isNull);
  });

  test('adopting a synchronized key epoch removes local old-key snapshots', () async {
    final previous = session.persistedBytes;
    final replacement = await session.changePassword(newPassword);
    await store.acceptSynchronized(
      session,
      previous,
      replacement.persistedBytes,
      replacement.entries,
      replacement.folders,
      replacement.name,
      authenticated: replacement,
    );
    replacement.lock();
    expect(await store.history(), isEmpty);
    expect(await store.readBaseline('a' * 40), isNull);
    await store.cacheBaseline('b' * 40, previous);
    expect(await store.readBaseline('b' * 40), isNull);
    await store.cacheBaseline('c' * 40, session.persistedBytes);
    expect(await store.readBaseline('c' * 40), session.persistedBytes);
    final reopened = await store.unlock(newPassword);
    reopened.lock();
  });
}
