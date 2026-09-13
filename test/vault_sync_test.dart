import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/crypto/crypto.dart';
import 'package:skysecret/core/sync/github/github_api.dart';
import 'package:skysecret/core/sync/github/github_backup.dart';

import 'github_test.dart' show FakeGitHub, MemoryStorage, seed, syntheticPassword, syntheticToken;

class RacingGitHub extends FakeGitHub {
  final commits = <String, ({String parent, Map<String, String> updates})>{};
  Future<void> Function()? beforePublish;
  bool rejectAlways = false;
  @override
  Future<String> commit(
    String token,
    GitHubRepository repo,
    RemoteSnapshot base,
    Map<String, String> updates,
  ) async {
    final id = (commits.length + 16).toRadixString(16).padLeft(40, '0');
    commits[id] = (parent: base.commit, updates: Map.of(updates));
    return id;
  }

  @override
  Future<void> publish(
    String token,
    GitHubRepository repo,
    String commit,
  ) async {
    publishes++;
    final callback = beforePublish;
    beforePublish = null;
    await callback?.call();
    final candidate = commits[commit]!;
    if (rejectAlways || candidate.parent != head) {
      throw const GitHubFailure(GitHubProblem.conflict);
    }
    for (final update in candidate.updates.entries) {
      remote[update.key] = RemoteVault(
        update.key,
        update.value,
        blobs[update.value]!.length,
      );
    }
    head = commit;
    if (loseResponse) {
      loseResponse = false;
      throw const GitHubFailure(GitHubProblem.network);
    }
  }
}

VaultEntry record(String id, String password, {String? folderId}) => VaultEntry(
  id: id,
  title: id,
  username: '',
  password: password,
  notes: '',
  folderId: folderId,
);

void main() {
  late Directory root;
  late VaultCatalog a, b;
  late VaultSession sa, sb;
  late GitHubBackup ba, bb;
  late RacingGitHub api;
  late MemoryStorage ma, mb;
  late VaultReference rb;

  Future<void> syncA() => ba.synchronizeVault('legacy', a.legacy.store, sa);
  Future<void> syncB() => bb.synchronizeVault(rb.id, rb.store, sb);
  Future<void> assertConverged(Set<String> passwords) async {
    await syncA();
    await syncB();
    expect(ba.problem, isNull);
    expect(bb.problem, isNull);
    expect(sa.entries.map((e) => e.password).toSet(), passwords);
    expect(sb.entries.map((e) => e.password).toSet(), passwords);
    expect(sa.persistedBytes, sb.persistedBytes);
    final publishes = api.publishes;
    await syncA();
    await syncB();
    expect(api.publishes, publishes, reason: 'unchanged sync is idempotent');
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('skysecret-sync-unit-');
    a = VaultCatalog(directory: Directory('${root.path}/a'));
    b = VaultCatalog(directory: Directory('${root.path}/b'));
    api = RacingGitHub();
    ma = MemoryStorage(seed());
    mb = MemoryStorage(seed());
    ba = GitHubBackup(catalog: a, storage: ma, api: api);
    bb = GitHubBackup(catalog: b, storage: mb, api: api);
    await ba.initialize(schedule: false);
    await bb.initialize(schedule: false);
    sa = await a.legacy.store.create(syntheticPassword);
    await a.legacy.store.save(sa, [
      record('one', 'base'),
      record('two', 'second'),
    ]);
    await syncA();
    expect(ba.problem, isNull);
    rb = b.newVault();
    final remote = api.remote.values.single;
    await bb.bindSynchronizedImport(rb.id, remote);
    sb = await rb.store.importEncryptedSnapshot(
      api.blobs[remote.blob]!,
      syntheticPassword,
    );
  });

  tearDown(() async {
    sa.lock();
    sb.lock();
    ba.dispose();
    bb.dispose();
    await root.delete(recursive: true);
  });

  test('favorites, trash, restoration and permanent removal converge across devices', () async {
    await a.legacy.store.save(sa, [sa.entries.first.inTrash(123), sa.entries.last]);
    await rb.store.save(sb, [sb.entries.first.withFavorite(true), sb.entries.last]);
    await syncA();
    await syncB();
    await syncA();
    expect(ba.problem, isNull);
    expect(bb.problem, isNull);
    final deleted = sa.entries.firstWhere((entry) => entry.id == 'one');
    expect(deleted.isDeleted, isTrue);
    expect(deleted.isFavorite, isTrue);
    expect(sb.entries.firstWhere((entry) => entry.id == 'one').isDeleted, isTrue);
    final restored = VaultCollection(entries: sb.entries, folders: sb.folders)..restore('one');
    await rb.store.save(sb, restored.entries);
    await syncB();
    await syncA();
    expect(sa.entries.firstWhere((entry) => entry.id == 'one').isDeleted, isFalse);
    final trash = VaultCollection(entries: sa.entries, folders: sa.folders)..delete('one', 456);
    await a.legacy.store.save(sa, trash.entries);
    await syncA();
    await syncB();
    final purged = VaultCollection(entries: sa.entries, folders: sa.folders)..purge('one');
    await a.legacy.store.save(sa, purged.entries);
    await syncA();
    await syncB();
    await syncA();
    expect(sa.entries.map((entry) => entry.id), ['two']);
    expect(sb.entries.map((entry) => entry.id), ['two']);
  });

  test(
    'two devices merge different edits and additions, then converge',
    () async {
      await a.legacy.store.save(sa, [
        record('one', 'from-A'),
        sa.entries[1],
        record('a', 'added-A'),
      ]);
      await rb.store.save(sb, [
        sb.entries[0],
        record('two', 'from-B'),
        record('b', 'added-B'),
      ]);
      await syncA();
      await syncB();
      await assertConverged({'from-A', 'from-B', 'added-A', 'added-B'});
      expect(
        api.remote.length,
        1,
        reason: 'restored device shares the same identity',
      );
    },
  );

  test(
    'different values of one record preserve both and retry without duplicates',
    () async {
      await a.legacy.store.save(sa, [record('one', 'A'), sa.entries[1]]);
      await rb.store.save(sb, [record('one', 'B'), sb.entries[1]]);
      await syncA();
      api.loseResponse = true;
      await syncB();
      expect(bb.problem, GitHubProblem.network);
      expect(sb.entries.length, 2);
      await syncB();
      await assertConverged({'A', 'B', 'second'});
      expect(sa.entries.length, 3);
    },
  );

  test(
    'a clean deletion propagates and delete versus edit retains the edit',
    () async {
      await a.legacy.store.save(sa, [sa.entries[1]]);
      await syncA();
      await syncB();
      expect(sb.entries.map((e) => e.id), ['two']);
      await a.legacy.store.save(sa, []);
      await rb.store.save(sb, [record('two', 'edited-after-delete')]);
      await syncA();
      await syncB();
      expect(bb.mergedConflicts, 1);
      await assertConverged({'edited-after-delete'});
    },
  );

  test(
    'intervening write to the same vault retries against latest branch',
    () async {
      await a.legacy.store.save(sa, [record('one', 'A'), sa.entries[1]]);
      await rb.store.save(sb, [sb.entries[0], record('two', 'B')]);
      api.beforePublish = syncB;
      final before = api.publishes;
      await syncA();
      expect(ba.problem, isNull);
      expect(api.publishes - before, 3);
      await assertConverged({'A', 'B'});
    },
  );

  test(
    'bounded contention leaves local bytes and merge baseline intact',
    () async {
      await a.legacy.store.save(sa, [record('one', 'A')]);
      final original = sa.persistedBytes;
      final baseline = (ma.value!['bindings'] as Map)['legacy']['base'];
      api.rejectAlways = true;
      final publishes = api.publishes;
      await syncA();
      expect(ba.problem, GitHubProblem.conflict);
      expect(api.publishes - publishes, 4);
      expect(await a.legacy.store.readEncryptedSnapshot(), original);
      expect((ma.value!['bindings'] as Map)['legacy']['base'], baseline);
    },
  );

  test(
    'lock during upload cancels publication and does not reopen the vault',
    () async {
      await a.legacy.store.save(sa, [record('one', 'A')]);
      final original = sa.persistedBytes;
      final publishes = api.publishes;
      api.onUpload = () async => sa.lock();
      await syncA();
      expect(sa.isLocked, isTrue);
      expect(api.publishes, publishes);
      expect(await a.legacy.store.readEncryptedSnapshot(), original);
    },
  );

  test(
    'a stale local writer cannot be replaced by the synchronized snapshot',
    () async {
      await a.legacy.store.save(sa, [record('one', 'A'), sa.entries[1]]);
      await rb.store.save(sb, [sb.entries[0], record('two', 'B')]);
      await syncB();
      final other = await a.legacy.store.unlock(syntheticPassword);
      await a.legacy.store.save(other, [record('one', 'newer-local')]);
      final bytes = other.persistedBytes;
      other.lock();
      await syncA();
      expect(ba.problem, GitHubProblem.conflict);
      expect(await a.legacy.store.readEncryptedSnapshot(), bytes);
    },
  );

  test('password rotation conflict never overwrites either version', () async {
    sa = await a.legacy.store.changePassword(
      sa,
      syntheticPassword,
      'New synthetic 456!',
    );
    await syncA();
    expect(ba.problem, isNull);
    await rb.store.save(sb, [record('one', 'B')]);
    final original = sb.persistedBytes;
    final remote = api.remote.values.single.blob;
    await syncB();
    expect(bb.syncKeyChanged, isTrue);
    expect(bb.problem, GitHubProblem.conflict);
    expect(await rb.store.readEncryptedSnapshot(), original);
    expect(api.remote.values.single.blob, remote);
  });

  test('manual vault changes cause no background network requests', () async {
    await a.legacy.store.save(sa, [record('one', 'offline-edit')]);
    final reads = api.reads, uploads = api.uploads;
    await ba.sync(onlyIfChanged: true);
    expect(api.reads, reads);
    expect(api.uploads, uploads);
    expect(ba.status, BackupStatus.pending);
  });

  test(
    'file conflicts retain both contents and unique attachment identifiers',
    () async {
      VaultEntry file(int value) => VaultEntry.file(
        VaultAttachment(id: 'attachment', name: 'example.txt', bytes: [value]),
        id: 'file',
      );
      await a.legacy.store.save(sa, [file(0)]);
      await syncA();
      await syncB();
      await a.legacy.store.save(sa, [file(1)]);
      await rb.store.save(sb, [file(2)]);
      await syncA();
      await syncB();
      await syncA();
      expect(sa.entries.length, 2);
      expect(
        sa.entries.expand((e) => e.attachments).map((a) => a.id).toSet().length,
        2,
      );
      expect(sa.entries.map((e) => e.attachments.single.bytes.single).toSet(), {
        1,
        2,
      });
      final reopened = await a.legacy.store.unlock(syntheticPassword);
      expect(reopened.entries.length, 2);
      reopened.lock();
    },
  );

  test(
    'baseline storage failure after local commit recovers on restart',
    () async {
      await a.legacy.store.save(sa, [record('one', 'A'), sa.entries[1]]);
      await rb.store.save(sb, [sb.entries[0], record('two', 'B')]);
      await syncB();
      ma.failAt = ma.writes + 2;
      await syncA();
      expect(ba.problem, GitHubProblem.storage);
      ba.dispose();
      ma.failAt = null;
      ba = GitHubBackup(catalog: a, storage: ma, api: api);
      await ba.initialize(schedule: false);
      await assertConverged({'A', 'B'});
    },
  );

  test('failed local commit after remote publish safely retries', () async {
    await a.legacy.store.save(sa, [record('one', 'A'), sa.entries[1]]);
    await rb.store.save(sb, [record('one', 'B'), sb.entries[1]]);
    await syncB();
    final original = sa.persistedBytes;
    final failing = VaultStore(
      file: a.legacy.file,
      beforeCommit: () async => throw StateError('synthetic disk failure'),
    );
    await ba.synchronizeVault('legacy', failing, sa);
    expect(ba.problem, GitHubProblem.storage);
    expect(await a.legacy.store.readEncryptedSnapshot(), original);
    await assertConverged({'A', 'B', 'second'});
    expect(sa.entries.length, 3);
  });

  test(
    'simultaneous rename of folders and vault converges after a lost response',
    () async {
      await a.legacy.store.save(
        sa,
        [record('one', 'base', folderId: 'f')],
        folders: [const VaultFolder(id: 'f', name: 'Original')],
        name: 'Original',
      );
      await syncA();
      await syncB();
      await a.legacy.store.save(
        sa,
        sa.entries,
        folders: [const VaultFolder(id: 'f', name: 'Folder A')],
        name: 'Name A',
      );
      await rb.store.save(
        sb,
        sb.entries,
        folders: [const VaultFolder(id: 'f', name: 'Folder B')],
        name: 'Name B',
      );
      await syncA();
      api.loseResponse = true;
      await syncB();
      await syncB();
      await syncA();
      expect(ba.problem, isNull);
      expect(bb.problem, isNull);
      expect(sa.name, 'Name A / Name B');
      expect(sa.folders.map((f) => f.name).toSet(), {'Folder A', 'Folder B'});
      expect(sa.persistedBytes, sb.persistedBytes);
      final publishes = api.publishes;
      await syncB();
      expect(api.publishes, publishes);
    },
  );

  test(
    'concurrent creation of another vault is preserved on branch retry',
    () async {
      await a.legacy.store.save(sa, [record('one', 'A')]);
      const extra = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
      final blob = api.remote.values.single.blob;
      api.beforePublish = () async {
        api.head = 'ffffffffffffffffffffffffffffffffffffffff';
        api.remote[extra] = RemoteVault(extra, blob, api.blobs[blob]!.length);
      };
      await syncA();
      expect(ba.problem, isNull);
      expect(api.remote[extra]!.blob, blob);
      expect(api.remote.length, 2);
    },
  );

  test(
    'authenticated revision rejects tampering and is revoked with its parent',
    () async {
      final revision = await sa.openRevision(sa.persistedBytes);
      final secret = revision.entries.first;
      final bytes = sa.persistedBytes;
      bytes[bytes.length - 1] ^= 1;
      await expectLater(
        sa.openRevision(bytes),
        throwsA(isA<VaultUnlockException>()),
      );
      sa.lock();
      expect(revision.isLocked, isTrue);
      expect(() => secret.password, throwsStateError);
    },
  );

  test('record deletion remains deleted after later offline device synchronization', () async {
    await a.legacy.store.save(sa, [sa.entries[1]]);
    await syncA();
    await rb.store.save(sb, [sb.entries[0], record('two', 'offline-B')]);
    await syncB();
    await assertConverged({'offline-B'});
    expect(sa.entries.single.id, 'two');
  });
  test(
    'authenticated replay is rejected without losing newer records',
    () async {
      final old = api.remote.values.single;
      await a.legacy.store.save(sa, [
        ...sa.entries,
        record('new', 'must-survive'),
      ]);
      await syncA();
      final before = sa.persistedBytes;
      final publishes = api.publishes;
      api.remote[old.id] = old;
      await syncA();
      expect(ba.syncRollback, isTrue);
      expect(ba.problem, GitHubProblem.conflict);
      expect(sa.persistedBytes, before);
      expect(await a.legacy.store.readEncryptedSnapshot(), before);
      expect(api.publishes, publishes);
    },
  );

  test(
    'unrelated older branch with more edits is not considered newer',
    () async {
      for (var i = 0; i < 8; i++) {
        await rb.store.save(sb, [record('one', 'offline-$i'), sb.entries[1]]);
      }
      await a.legacy.store.save(sa, [
        ...sa.entries,
        record('new', 'known-new'),
      ]);
      await syncA();
      final before = sa.persistedBytes;
      final old = api.remote.values.single;
      final bytes = sb.persistedBytes;
      final hash = await gitBlobHash(bytes);
      api.blobs[hash] = bytes;
      api.remote[old.id] = RemoteVault(old.id, hash, bytes.length);
      await syncA();
      expect(ba.syncRollback, isTrue);
      expect(sa.persistedBytes, before);
    },
  );

  test('remote password rotation stops synchronization and preserves both vaults', () async {
    const nextPassword = 'Synthetic rotated password 456!';
    sa = await a.legacy.store.changePassword(sa, syntheticPassword, nextPassword);
    await syncA();
    expect(ba.problem, isNull);

    final localBefore = sb.persistedBytes;
    final remoteBefore = api.remote.values.single.blob;
    final uploads = api.uploads;
    await syncB();
    expect(bb.syncKeyChanged, isTrue);
    expect(bb.problem, GitHubProblem.conflict);
    expect(sb.persistedBytes, localBefore);
    expect(await rb.store.readEncryptedSnapshot(), localBefore);
    expect(api.remote.values.single.blob, remoteBefore);
    expect(api.uploads, uploads);

    final reopened = await rb.store.unlock(syntheticPassword);
    reopened.lock();
    final separate = b.newVault();
    final restored = await separate.store.importEncryptedSnapshot(api.blobs[remoteBefore]!, nextPassword);
    expect(restored.entries.map((e) => e.password).toSet(), {'base', 'second'});
    restored.lock();
    expect(await rb.store.readEncryptedSnapshot(), localBefore);
  });

  test('old-key attacker cannot receive secrets created after local password rotation', () async {
    const nextPassword = 'Synthetic replacement trusted phrase';
    final oldBytes = sa.persistedBytes;
    final remoteId = api.remote.values.single.id;
    sa = await a.legacy.store.changePassword(sa, syntheticPassword, nextPassword);
    await a.legacy.store.save(sa, [...sa.entries, record('new-secret', 'SECRET_AFTER_ROTATION')]);

    final old = await VaultCipher.unlock(oldBytes, syntheticPassword);
    final attackerEpoch1 = await old.changePassword(syntheticPassword);
    final attackerEpoch2 = await attackerEpoch1.changePassword(syntheticPassword);
    try {
      expect(attackerEpoch2.revision.keyEpoch, 2);
      expect(sa.revision.keyEpoch, 1);
      final malicious = attackerEpoch2.persistedBytes;
      final hash = await gitBlobHash(malicious);
      api.blobs[hash] = malicious;
      api.remote[remoteId] = RemoteVault(remoteId, hash, malicious.length);
      final before = sa.persistedBytes;
      final uploads = api.uploads;
      final publishes = api.publishes;
      await syncA();
      expect(ba.syncKeyChanged, isTrue);
      expect(ba.problem, GitHubProblem.conflict);
      expect(api.uploads, uploads);
      expect(api.publishes, publishes);
      expect(api.remote[remoteId]!.blob, hash);
      expect(sa.persistedBytes, before);
      expect(await a.legacy.store.readEncryptedSnapshot(), before);
      final reopened = await a.legacy.store.unlock(nextPassword);
      expect(reopened.entries.last.password, 'SECRET_AFTER_ROTATION');
      reopened.lock();
      await expectLater(a.legacy.store.unlock(syntheticPassword), throwsA(isA<VaultUnlockException>()));

      final openedWithOldPassword = await sa.openWithPassword(malicious, syntheticPassword);
      try {
        expect(() => VaultMerge.combine(old, sa, openedWithOldPassword), throwsA(isA<VaultUnlockException>()));
      } finally {
        sa.closeRevision(openedWithOldPassword);
      }
    } finally {
      old.lock();
      attackerEpoch1.lock();
      attackerEpoch2.lock();
    }
  });

  test('same-epoch different keys cannot merge or be relinked', () async {
    const localPassword = 'Synthetic local replacement phrase';
    const remotePassword = 'Synthetic remote replacement phrase';
    sa = await a.legacy.store.changePassword(sa, syntheticPassword, localPassword);
    sb = await rb.store.changePassword(sb, syntheticPassword, remotePassword);
    await syncA();
    final before = sb.persistedBytes;
    final uploads = api.uploads;
    final binding = Map<String, dynamic>.from((mb.value!['bindings'] as Map)[rb.id] as Map);
    await syncB();
    expect(bb.problem, GitHubProblem.conflict);
    expect(bb.syncKeyChanged, isTrue);
    await bb.linkExistingVault(rb.id, rb.store, sb, api.remote.values.single);
    expect(bb.problem, GitHubProblem.conflict);
    expect(bb.syncKeyChanged, isTrue);
    expect((mb.value!['bindings'] as Map)[rb.id], binding);
    expect(await rb.store.readEncryptedSnapshot(), before);
    expect(api.uploads, uploads);
  });

  test('cached merge baseline survives a missing Git blob', () async {
    await syncB();
    final base = api.remote.values.single.blob;
    await a.legacy.store.save(sa, [record('one', 'A'), sa.entries[1]]);
    await rb.store.save(sb, [sb.entries[0], record('two', 'B')]);
    await syncA();
    api.blobs.remove(base);
    await syncB();
    expect(bb.problem, isNull);
    await assertConverged({'A', 'B'});
  });
  test(
    'a locally restored stale file cannot overwrite a newer remote checkpoint',
    () async {
      final old = sa.persistedBytes;
      await a.legacy.store.save(sa, [
        ...sa.entries,
        record('new', 'keep-remote'),
      ]);
      await syncA();
      final remote = api.remote.values.single;
      sa.lock();
      await a.legacy.file.writeAsBytes(old, flush: true);
      sa = await a.legacy.store.unlock(syntheticPassword);
      await syncA();
      expect(ba.syncRollback, isTrue);
      expect(api.remote.values.single.blob, remote.blob);
    },
  );

  test(
    'conflict markers survive reopening and explicit choice propagates',
    () async {
      await a.legacy.store.save(sa, [record('one', 'A'), sa.entries[1]]);
      await rb.store.save(sb, [record('one', 'B'), sb.entries[1]]);
      await syncA();
      await syncB();
      await syncA();
      final reopened = await a.legacy.store.unlock(syntheticPassword);
      expect(
        reopened.entries.where((e) => e.conflictOf == 'one'),
        hasLength(2),
      );
      reopened.lock();
      final chosen = sa.entries.firstWhere((e) => e.password == 'B');
      await a.legacy.store.save(sa, [
        for (final e in sa.entries)
          if (e.id == chosen.id) e.withConflict(null) else if (e.conflictOf != chosen.conflictOf) e,
      ]);
      await syncA();
      await assertConverged({'B', 'second'});
      expect(sb.entries.every((e) => e.conflictOf == null), isTrue);
    },
  );

  test('lost binding can be reconstructed without publishing or replacing local edits', () async {
    await rb.store.save(sb, [record('one', 'offline-B'), sb.entries[1]]);
    final before = sb.persistedBytes;
    bb.dispose();
    mb = MemoryStorage(seed());
    bb = GitHubBackup(catalog: b, storage: mb, api: api);
    await bb.initialize(schedule: false);
    final published = api.publishes;
    await bb.linkExistingVault(rb.id, rb.store, sb, api.remote.values.single);
    expect(bb.problem, isNull);
    expect(sb.persistedBytes, before);
    expect(api.publishes, published);
    await syncB();
    await assertConverged({'offline-B', 'second'});
  });

  test('damaged journal recovery keeps vaults manual and leaves their files intact', () async {
    final before = sb.persistedBytes;
    bb.dispose();
    mb = MemoryStorage({'version': 999});
    bb = GitHubBackup(catalog: b, storage: mb, api: api);
    await bb.initialize(schedule: false);
    expect(bb.connectionNeedsRecovery, isTrue);
    final reads = api.reads, publishes = api.publishes;
    await bb.resetDamagedConnection();
    expect(bb.usable, isTrue);
    expect(bb.signedIn, isFalse);
    expect(bb.isManual(rb.id), isTrue);
    expect(await rb.store.readEncryptedSnapshot(), before);
    expect(api.reads, reads);
    expect(api.publishes, publishes);
    await bb.connectToken(syntheticToken, 'https://github.com/fixture/renamed');
    expect(bb.problem, isNull);
    bb.status = BackupStatus.synced;
    await rb.store.save(sb, [...sb.entries, record('recovered', 'pending')]);
    expect(bb.status, BackupStatus.pending);
    expect(bb.isManual(rb.id), isTrue);
  });

  test('three offline devices converge after independent edits and conflicting deletes', () async {
    final c = VaultCatalog(directory: Directory('${root.path}/c'));
    final rc = c.newVault();
    final bc = GitHubBackup(
      catalog: c,
      storage: MemoryStorage(seed()),
      api: api,
    );
    await bc.initialize(schedule: false);
    final remote = api.remote.values.single;
    await bc.bindSynchronizedImport(rc.id, remote);
    final sc = await rc.store.importEncryptedSnapshot(
      api.blobs[remote.blob]!,
      syntheticPassword,
    );
    try {
      await a.legacy.store.save(sa, [record('one', 'A'), sa.entries[1]]);
      await rb.store.save(sb, [sb.entries[0], record('two', 'B')]);
      await rc.store.save(sc, [record('c', 'C')]);
      await syncA();
      await syncB();
      await bc.synchronizeVault(rc.id, rc.store, sc);
      expect(bc.problem, isNull);
      await assertConverged({'A', 'B', 'C'});
      await bc.synchronizeVault(rc.id, rc.store, sc);
      expect(sc.persistedBytes, sa.persistedBytes);
    } finally {
      sc.lock();
      bc.dispose();
    }
  });
  test('synchronized adoption rejects mismatched ciphertext and unrelated keys before commit', () async {
    final before = sa.persistedBytes;
    final candidateBytes = await sa.encrypt([
      ...sa.entries,
      record('new', 'candidate'),
    ]);
    final candidate = await sa.openRevision(candidateBytes);
    final unrelated = await VaultCipher.create(syntheticPassword);
    try {
      await expectLater(
        a.legacy.store.acceptSynchronized(
          sa,
          before,
          before,
          candidate.entries,
          candidate.folders,
          candidate.name,
          authenticated: candidate,
        ),
        throwsA(isA<VaultConflictException>()),
      );
      await expectLater(
        a.legacy.store.acceptSynchronized(
          sa,
          before,
          unrelated.persistedBytes,
          unrelated.entries,
          unrelated.folders,
          unrelated.name,
          authenticated: unrelated,
        ),
        throwsA(isA<VaultFormatException>()),
      );
      expect(await a.legacy.store.readEncryptedSnapshot(), before);
      expect(sa.persistedBytes, before);
    } finally {
      sa.closeRevision(candidate);
      unrelated.lock();
    }
  });
}
