import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/crypto/crypto.dart';
import 'package:skysecret/github/github_api.dart';
import 'package:skysecret/github/github_credentials.dart';
import 'package:skysecret/github/github_backup.dart';
import 'package:skysecret/github/github_storage.dart';

const h0 = '0000000000000000000000000000000000000000';
const h1 = '1111111111111111111111111111111111111111';
const h2 = '2222222222222222222222222222222222222222';
const id1 = '11111111111111111111111111111111';
const syntheticPassword = 'Synthetic fixture 123!';

Map<String, dynamic> repoJson({
  int id = 7,
  String name = 'renamed',
  bool private = true,
  int owner = 42,
  String? description,
}) => {
  'id': id,
  'owner': {'id': owner, 'login': 'renamed-user'},
  'name': name,
  'default_branch': 'backup/main',
  'private': private,
  'fork': false,
  'archived': false,
  'permissions': {'push': true},
  'description': description,
};
const syntheticToken = 'github_pat_SYNTHETIC_UNIT_TOKEN_1234567890';
Map<String, dynamic> seed() => {
  'version': 2,
  'bindings': <String, dynamic>{},
  'enabled': true,
  'userId': 42,
  'login': 'fixture',
  'repoId': 7,
  'credential': syntheticToken,
};
Matcher fails(GitHubProblem problem) =>
    throwsA(isA<GitHubFailure>().having((e) => e.problem, 'problem', problem));

class CapturedTimer implements Timer {
  CapturedTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }
}

class MemoryStorage implements GitHubStorage {
  MemoryStorage(this.value);
  Map<String, dynamic>? value;
  int writes = 0;
  int? failAt;
  @override
  Future<Map<String, dynamic>?> read() async =>
      value == null ? null : object(jsonDecode(jsonEncode(value)));
  @override
  Future<void> write(Map<String, dynamic> data) async {
    writes++;
    if (writes == failAt) throw const GitHubFailure(GitHubProblem.storage);
    value = object(jsonDecode(jsonEncode(data)));
  }
}

class FakeGitHub extends GitHubApi {
  GitHubRepository repo = GitHubRepository.fromJson(repoJson());
  final remote = <String, RemoteVault>{};
  final blobs = <String, Uint8List>{};
  Map<String, String> staged = {};
  String head = h0;
  int uploads = 0, publishes = 0, reads = 0;
  bool offline = false;
  Future<void> Function()? onUpload;
  int identity = 42;
  bool loseResponse = false, race = false, deny = false;
  @override
  Future<GitHubUser> user(String token) async =>
      GitHubUser.fromJson({'id': identity, 'login': 'fixture'});
  @override
  Future<GitHubRepository> repository(String token, int id, int userId) async {
    reads++;
    if (offline) throw const GitHubFailure(GitHubProblem.network);
    if (deny) throw const GitHubFailure(GitHubProblem.missing);
    repo.validate(userId);
    return repo;
  }

  @override
  Future<GitHubRepository> repositoryByAddress(
    String token,
    GitHubRepositoryAddress address,
    int userId,
  ) => repository(token, repo.id, userId);

  @override
  Future<RemoteSnapshot> snapshot(
    String token,
    GitHubRepository repo, {
    bool initializing = false,
  }) async => RemoteSnapshot(head, h1, Map.of(remote));
  @override
  Future<String> upload(
    String token,
    GitHubRepository repo,
    Uint8List bytes,
  ) async {
    uploads++;
    await onUpload?.call();
    final hash = await gitBlobHash(bytes);
    blobs[hash] = Uint8List.fromList(bytes);
    return hash;
  }

  @override
  Future<String> commit(
    String token,
    GitHubRepository repo,
    RemoteSnapshot base,
    Map<String, String> updates,
  ) async {
    expect(base.commit, head);
    staged = Map.of(updates);
    return h2;
  }

  @override
  Future<void> publish(
    String token,
    GitHubRepository repo,
    String commit,
  ) async {
    publishes++;
    if (race) {
      for (final id in staged.keys) {
        remote[id] = RemoteVault(id, h1, 1);
      }
      throw const GitHubFailure(GitHubProblem.conflict);
    }
    for (final update in staged.entries) {
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

  @override
  Future<Uint8List> blob(
    String token,
    GitHubRepository repo,
    String hash, {
    int limit = GitHubApi.maxVaultBytes,
  }) async => Uint8List.fromList(blobs[hash]!);
}

void main() {
  test(
    'only fine-grained syntax and GitHub repository addresses are accepted',
    () {
      expect(FineGrainedToken(' $syntheticToken ').value, syntheticToken);
      for (final invalid in [
        'ghp_CLASSIC_TOKEN',
        'gho_OAUTH_TOKEN',
        '',
        'github_pat_short',
        '$syntheticToken\nINJECTION',
      ]) {
        expect(() => FineGrainedToken(invalid), throwsA(isA<GitHubFailure>()));
      }
      expect(
        GitHubRepositoryAddress.parse('https://github.com/owner/repo.git')
            .label,
        'owner/repo',
      );
      for (final invalid in [
        'https://evil.example/o/r',
        'https://github.com',
        'https://github.com/',
        'https://github.com@evil.example/o/r',
        'https://github.com:443/o/r',
        'o/r/extra',
        'o/..',
        'https://github.com/o/r?x=1',
      ]) {
        expect(
          () => GitHubRepositoryAddress.parse(invalid),
          throwsA(isA<GitHubFailure>()),
        );
      }
    },
  );

  group('GitHub REST unit protocol', () {
    test('429 Retry-After prevents immediate manual retry', () async {
      var requests = 0;
      final api = GitHubApi(
        transport: (_, _, _, _, _) async {
          requests++;
          return const GitHubResponse(
            429,
            {'message': 'SYNTHETIC_PRIVATE_RESPONSE'},
            {'retry-after': '120'},
          );
        },
      );
      await expectLater(
        api.user('SYNTHETIC_ACCESS'),
        fails(GitHubProblem.denied),
      );
      await expectLater(
        api.user('SYNTHETIC_ACCESS'),
        fails(GitHubProblem.denied),
      );
      expect(requests, 1);
      expect(
        const GitHubFailure(GitHubProblem.denied).toString(),
        isNot(contains('SYNTHETIC_PRIVATE_RESPONSE')),
      );
    });

    test(
      'connection looks up exactly the supplied repository on api.github.com',
      () async {
        final api = GitHubApi(
          transport: (method, uri, headers, body, _) async {
            expect(method, 'GET');
            expect(uri.toString(), 'https://api.github.com/repos/owner/backup');
            expect(headers['Authorization'], 'Bearer $syntheticToken');
            return GitHubResponse(200, repoJson());
          },
        );
        expect(
          (await api.repositoryByAddress(
            syntheticToken,
            GitHubRepositoryAddress.parse('owner/backup'),
            42,
          )).id,
          7,
        );
      },
    );

    test(
      'public, transferred, forked, archived and read-only repos refuse writes',
      () {
        for (final json in [
          repoJson(private: false),
          repoJson(owner: 99),
          {...repoJson(), 'fork': true},
          {...repoJson(), 'archived': true},
          {
            ...repoJson(),
            'permissions': {'push': false},
          },
        ]) {
          expect(
            () => GitHubRepository.fromJson(json).validate(42),
            throwsA(isA<GitHubFailure>()),
          );
        }
      },
    );

    test('publishes only fast-forward and encodes branch', () async {
      final api = GitHubApi(
        transport: (method, uri, headers, body, _) async {
          expect(headers['X-GitHub-Api-Version'], GitHubApi.apiVersion);
          if (method == 'PATCH') {
            expect(object(body), {'sha': h2, 'force': false});
            expect(uri.toString(), contains('heads/backup%2Fmain'));
            return const GitHubResponse(200, {});
          }
          throw StateError('Unexpected request');
        },
      );
      await api.publish(
        'SYNTHETIC_ACCESS',
        GitHubRepository.fromJson(repoJson()),
        h2,
      );
    });

    test(
      'download validates hash and size, marker version cannot be adopted',
      () async {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final hash = await gitBlobHash(bytes);
        final api = GitHubApi(
          transport: (_, _, _, _, _) async => GitHubResponse(200, {
            'encoding': 'base64',
            'size': 3,
            'content': base64.encode(bytes),
          }),
        );
        expect(
          await api.blob(
            'SYNTHETIC_ACCESS',
            GitHubRepository.fromJson(repoJson()),
            hash,
          ),
          bytes,
        );
        await expectLater(
          api.blob(
            'SYNTHETIC_ACCESS',
            GitHubRepository.fromJson(repoJson()),
            h0,
          ),
          fails(GitHubProblem.format),
        );
        await expectLater(
          api.blob(
            'SYNTHETIC_ACCESS',
            GitHubRepository.fromJson(repoJson()),
            hash,
            limit: 2,
          ),
          fails(GitHubProblem.format),
        );
        expect(
          () => GitHubApi.validateMarker(
            utf8.encode('{"appId":"secret-manager-vault","version":2}'),
          ),
          throwsA(isA<GitHubFailure>()),
        );
      },
    );
  });

  group('backup coordinator unit failures', () {
    late Directory directory;
    late VaultCatalog catalog;
    late MemoryStorage storage;
    late FakeGitHub api;
    late GitHubBackup backup;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('github-unit-');
      catalog = VaultCatalog(directory: directory);
      storage = MemoryStorage(seed());
      api = FakeGitHub();
      backup = GitHubBackup(catalog: catalog, storage: storage, api: api);
      await backup.initialize(schedule: false);
    });
    tearDown(() async {
      backup.dispose();
      await directory.delete(recursive: true);
    });
    Future<void> local([List<int> bytes = const [1, 2, 3]]) =>
        catalog.legacy.file.writeAsBytes(bytes, flush: true);

    Future<void> idle() async {
      for (var i = 0; i < 500 && backup.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(backup.busy, false);
    }

    test(
      'unchanged ciphertext makes no GitHub requests; new data is uploaded',
      () async {
        await backup.sync(onlyIfChanged: true);
        expect(api.reads, 0);
        await local();
        await backup.sync(onlyIfChanged: true);
        final reads = api.reads;
        await backup.sync(onlyIfChanged: true);
        expect(api.reads, reads);
        await local([4, 5]);
        await backup.sync(onlyIfChanged: true);
        expect(api.publishes, 2);
        await catalog.legacy.file.delete();
        final afterUpdate = api.reads;
        await backup.sync(onlyIfChanged: true);
        expect(api.reads, afterUpdate);
        expect(api.remote.length, 1);
      },
    );

    test('save events debounce; offline retry waits 30 minutes and survives restart', () async {
      final timers = <CapturedTimer>[];
      final changes = StreamController<void>.broadcast(sync: true);
      await runZoned(
        () async {
          backup.dispose();
          storage.value!['enabled'] =
              false;
          backup = GitHubBackup(
            catalog: catalog,
            storage: storage,
            api: api,
            changes: changes.stream,
          );
          await backup.initialize();
          await idle();
          expect(api.reads, 0);
          expect(timers, isEmpty);
          await local();
          changes.add(null);
          changes.add(null);
          expect(timers.where((timer) => timer.isActive).length, 1);
          expect(timers.last.delay, const Duration(seconds: 5));
          timers.last.fire();
          await idle();
          expect(api.publishes, 1);
          expect(timers.where((timer) => timer.isActive), isEmpty);
          changes.add(null);
          final reads = api.reads;
          timers.last.fire();
          await idle();
          expect(api.reads, reads);
          api.offline = true;
          await local([9, 8, 7]);
          changes.add(null);
          timers.last.fire();
          await idle();
          expect(backup.problem, GitHubProblem.network);
          expect(timers.last.delay.inSeconds, inInclusiveRange(1798, 1800));
          changes.add(null);
          expect(timers.last.delay.inSeconds, inInclusiveRange(1798, 1800));
          expect(await catalog.legacy.file.readAsBytes(), [9, 8, 7]);
          backup.dispose();
          expect(timers.where((timer) => timer.isActive), isEmpty);
          api.offline = false;
          backup = GitHubBackup(catalog: catalog, storage: storage, api: api);
          await backup.initialize();
          await idle();
          expect(api.publishes, 2);
          expect(backup.status, BackupStatus.synced);
          expect(timers.where((timer) => timer.isActive), isEmpty);
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration < const Duration(seconds: 5)) {
              return parent.createTimer(zone, duration, callback);
            }
            final timer = CapturedTimer(duration, zone.bindCallback(callback));
            timers.add(timer);
            return timer;
          },
        ),
      );
      await changes.close();
    });

    test(
      'a save during upload schedules the next snapshot without losing it',
      () async {
        final changes = StreamController<void>.broadcast(sync: true);
        final timers = <CapturedTimer>[];
        await runZoned(
          () async {
            backup.dispose();
            storage.value = null;
            backup = GitHubBackup(
              catalog: catalog,
              storage: storage,
              api: api,
              changes: changes.stream,
            );
            await backup.initialize();
            await local();
            await backup.connectToken(syntheticToken, 'fixture/backup');
            expect(timers.last.delay, const Duration(seconds: 5));
            api.onUpload = () async {
              api.onUpload = null;
              await local([6, 7, 8]);
              changes.add(null);
            };
            timers.last.fire();
            await idle();
            expect(backup.status, BackupStatus.pending);
            expect(timers.where((timer) => timer.isActive).length, 1);
            timers.last.fire();
            await idle();
            expect(api.publishes, 2);
            expect(backup.status, BackupStatus.synced);
            expect(api.blobs[api.remote.values.single.blob], [6, 7, 8]);
            expect(timers.where((timer) => timer.isActive), isEmpty);
          },
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              if (duration < const Duration(seconds: 5)) {
                return parent.createTimer(zone, duration, callback);
              }
              final timer = CapturedTimer(
                duration,
                zone.bindCallback(callback),
              );
              timers.add(timer);
              return timer;
            },
          ),
        );
        await changes.close();
      },
    );

    test('startup scans committed files; lost remote acknowledgement is reconciled', () async {
      await local();
      api.loseResponse = true;
      await backup.sync();
      expect(backup.problem, GitHubProblem.network);
      expect(storage.value!['pending'], isNotNull);
      expect(api.publishes, 1);
      backup.dispose();
      backup = GitHubBackup(catalog: catalog, storage: storage, api: api);
      await backup.initialize(schedule: false);
      await backup.sync();
      expect(backup.status, BackupStatus.synced);
      expect(storage.value!['pending'], isNull);
      expect(api.publishes, 1);
      expect(api.uploads, 1);
      await local([4, 5, 6]);
      await backup.sync();
      expect(api.publishes, 2);
    });

    test('remote conflict preserves both; explicit fork leaves remote source intact', () async {
      await local();
      await backup.sync();
      final original = api.remote.keys.single;
      api.remote[original] = RemoteVault(original, h1, 1);
      await local([7, 8, 9]);
      await backup.sync();
      expect(backup.status, BackupStatus.conflict);
      expect(api.publishes, 1);
      expect(await catalog.legacy.file.readAsBytes(), [7, 8, 9]);
      await backup.keepBoth();
      expect(api.remote.length, 2);
      expect(api.remote[original]!.blob, h1);
      expect(backup.status, BackupStatus.synced);
    });

    test('race at ref update never acknowledges failed backup', () async {
      await local();
      api.race = true;
      await backup.sync();
      expect(backup.status, BackupStatus.conflict);
      expect(
        object(object(storage.value!['bindings'])['legacy'])['base'],
        isNull,
      );
      expect(storage.value!['lastSync'], isNull);
    });

    test('journal disk failure stops before remote publication', () async {
      await local();
      storage.failAt = storage.writes + 2;
      await backup.sync();
      expect(backup.problem, GitHubProblem.storage);
      expect(api.publishes, 0);
      expect(backup.usable, false);
      expect(await catalog.legacy.file.readAsBytes(), [1, 2, 3]);
    });

    test(
      'missing repository stops, never creates an empty replacement',
      () async {
        await local();
        api.deny = true;
        await backup.sync();
        expect(backup.problem, GitHubProblem.missing);
        expect(api.uploads, 0);
      },
    );

    test('deleting local vault does not delete remote copy', () async {
      await local();
      await backup.sync();
      await catalog.legacy.file.delete();
      await backup.sync();
      expect(api.remote.length, 1);
      expect(api.publishes, 1);
    });

    test('connect saves a checked personal token, enables auto backup, and preserves baselines', () async {
      await local();
      await backup.sync();
      final bindings = jsonEncode(storage.value!['bindings']);
      await backup.connectToken(syntheticToken, 'fixture/backup');
      expect(backup.problem, isNull);
      expect(backup.signedIn, true);
      expect(backup.enabled, true);
      expect(storage.value!['credential'], syntheticToken);
      expect(jsonEncode(storage.value!['bindings']), bindings);
    });

    test(
      'replacement token identity mismatch preserves credentials and data',
      () async {
        final before = jsonEncode(storage.value);
        api.identity = 99;
        await backup.connectToken(syntheticToken, 'fixture/backup');
        expect(backup.problem, GitHubProblem.identity);
        expect(jsonEncode(storage.value), before);
        expect(api.uploads, 0);
        expect(api.publishes, 0);
      },
    );

    test('replacement repository mismatch cannot redirect backups', () async {
      final before = jsonEncode(storage.value);
      api.repo = GitHubRepository.fromJson(repoJson(id: 88));
      await backup.connectToken(syntheticToken, 'fixture/other');
      expect(backup.problem, GitHubProblem.repositoryChanged);
      expect(jsonEncode(storage.value), before);
      expect(api.publishes, 0);
    });

    Future<void> unusedLegacy([
      Map<String, dynamic> overrides = const {},
    ]) async {
      backup.dispose();
      storage.value = seed()
        ..remove('credential')
        ..['legacyOAuthRemoved'] = true
        ..['enabled'] = false
        ..addAll(overrides);
      backup = GitHubBackup(catalog: catalog, storage: storage, api: api);
      await backup.initialize(schedule: false);
      api.repo = GitHubRepository.fromJson(repoJson(id: 88));
    }

    test(
      'unused OAuth selection does not block first PAT repository',
      () async {
        await unusedLegacy();
        await local();
        final before = await catalog.legacy.file.readAsBytes();
        await backup.connectToken(
          syntheticToken,
          'https://github.com/fixture/new',
        );
        expect(backup.problem, isNull);
        expect(backup.repositoryId, 88);
        expect(backup.enabled, true);
        expect(storage.value!['legacyOAuthRemoved'], isNull);
        expect(await catalog.legacy.file.readAsBytes(), before);
        expect(api.uploads, 0);
        expect(api.publishes, 0);
      },
    );

    test(
      'legacy backups or pending/history prevent repository reassignment',
      () async {
        for (final overrides in <Map<String, dynamic>>[
          {
            'bindings': {
              'legacy': {'remote': id1, 'base': h1},
            },
          },
          {
            'pending': {
              'commit': h0,
              'updates': {id1: h1},
            },
          },
          {'lastSync': '2026-09-11T00:00:00.000Z'},
        ]) {
          await unusedLegacy(overrides);
          final before = jsonEncode(storage.value);
          await backup.connectToken(syntheticToken, 'fixture/new');
          expect(backup.problem, GitHubProblem.repositoryChanged);
          expect(jsonEncode(storage.value), before);
        }
        expect(api.uploads, 0);
        expect(api.publishes, 0);
      },
    );

    test(
      'failed or wrong-owner connection preserves unused OAuth selection',
      () async {
        await unusedLegacy();
        final before = jsonEncode(storage.value);
        api.deny = true;
        await backup.connectToken(syntheticToken, 'fixture/new');
        expect(backup.problem, GitHubProblem.missing);
        expect(jsonEncode(storage.value), before);
        api.deny = false;
        api.identity = 99;
        await backup.connectToken(syntheticToken, 'fixture/new');
        expect(backup.problem, GitHubProblem.identity);
        expect(jsonEncode(storage.value), before);
        expect(api.publishes, 0);
      },
    );

    test('migration removes OAuth before any request and preserves recovery journal', () async {
      backup.dispose();
      final initial = seed()
        ..['version'] = 1
        ..remove('credential')
        ..['tokens'] = {
          'access': 'SYNTHETIC_LEGACY',
          'refresh': 'SYNTHETIC_LEGACY_REFRESH',
        }
        ..['clientId'] = 'SYNTHETIC_CLIENT'
        ..['bindings'] = {
          'legacy': {'remote': id1, 'base': h1},
        }
        ..['pending'] = {
          'commit': h2,
          'updates': {id1: h2},
        };
      storage = MemoryStorage(initial);
      var requests = 0;
      backup = GitHubBackup(
        catalog: catalog,
        storage: storage,
        api: GitHubApi(
          transport: (_, _, _, _, _) async {
            requests++;
            throw StateError('Migration must be offline');
          },
        ),
      );
      await backup.initialize();
      expect(requests, 0);
      expect(backup.signedIn, false);
      expect(backup.enabled, false);
      expect(backup.legacyOAuthRemoved, true);
      expect(storage.value!['version'], 2);
      expect(storage.value!.containsKey('tokens'), false);
      expect(storage.value!.containsKey('clientId'), false);
      expect(storage.value!['pending'], initial['pending']);
      expect(storage.value!['bindings'], initial['bindings']);
    });

    test(
      'migration write failure stops network and preserves original journal',
      () async {
        backup.dispose();
        final initial = seed()
          ..['version'] = 1
          ..remove('credential')
          ..['tokens'] = {'access': 'SYNTHETIC_LEGACY'};
        storage = MemoryStorage(initial)..failAt = 1;
        backup = GitHubBackup(catalog: catalog, storage: storage, api: api);
        await backup.initialize();
        expect(backup.usable, false);
        expect(backup.problem, GitHubProblem.storage);
        expect(storage.value!['version'], 1);
        expect(api.uploads, 0);
      },
    );

    test('encrypted round trip restores independently; wrong password creates nothing', () async {
      final session = await catalog.legacy.store.create(
        syntheticPassword,
        name: 'SYNTHETIC_TITLE',
      );
      await catalog.legacy.store.save(session, [
        VaultEntry.create(
          title: 'SYNTHETIC_ENTRY',
          password: 'SYNTHETIC_SECRET',
          username: 'SYNTHETIC_USER',
          notes: 'SYNTHETIC_NOTE',
        ),
      ]);
      session.lock();
      final original = await catalog.legacy.file.readAsBytes();
      await backup.sync();
      expect(backup.status, BackupStatus.synced);
      final ciphertext = await backup.download(backup.remoteVaults.single);
      expect(ciphertext, original);
      expect(latin1.decode(ciphertext!), isNot(contains('SYNTHETIC_SECRET')));
      final destination = catalog.newVault();
      await expectLater(
        destination.store.importEncryptedSnapshot(
          ciphertext,
          'SYNTHETIC_WRONG',
        ),
        throwsA(isA<VaultUnlockException>()),
      );
      expect(await destination.store.exists(), false);
      final restored = await destination.store.importEncryptedSnapshot(
        ciphertext,
        syntheticPassword,
      );
      expect(restored.entries.single.password, 'SYNTHETIC_SECRET');
      restored.lock();
      expect(await catalog.legacy.file.readAsBytes(), original);
      await expectLater(
        destination.store.importEncryptedSnapshot(
          ciphertext,
          syntheticPassword,
        ),
        throwsA(isA<VaultConflictException>()),
      );
    });
  });

  test(
    'remote tree rejects symlinks, traversal, oversized and truncated objects',
    () async {
      final markerBytes = utf8.encode(GitHubApi.marker);
      final markerHash = await gitBlobHash(markerBytes);
      List<Map<String, dynamic>> entries = [];
      var truncated = false;
      final api = GitHubApi(
        transport: (_, uri, _, _, _) async {
          if (uri.path.contains('/git/ref/')) {
            return const GitHubResponse(200, {
              'object': {'sha': h0},
            });
          }
          if (uri.path.endsWith('/git/commits/$h0')) {
            return const GitHubResponse(200, {
              'tree': {'sha': h1},
            });
          }
          if (uri.path.endsWith('/git/trees/$h1')) {
            return GitHubResponse(200, {
              'truncated': false,
              'tree': [
                {
                  'path': 'vault.json',
                  'sha': markerHash,
                  'type': 'blob',
                  'mode': '100644',
                },
                {'path': 'vaults', 'sha': h2, 'type': 'tree', 'mode': '040000'},
              ],
            });
          }
          if (uri.path.endsWith('/git/trees/$h2')) {
            return GitHubResponse(200, {
              'truncated': truncated,
              'tree': entries,
            });
          }
          return GitHubResponse(200, {
            'encoding': 'base64',
            'size': markerBytes.length,
            'content': base64.encode(markerBytes),
          });
        },
      );
      final repo = GitHubRepository.fromJson(repoJson());
      final valid = {
        'path': '$id1.smv',
        'sha': h0,
        'type': 'blob',
        'mode': '100644',
        'size': 10,
      };
      entries = [valid];
      expect(
        (await api.snapshot('SYNTHETIC_ACCESS', repo)).vaults[id1]!.size,
        10,
      );
      for (final entry in [
        {...valid, 'path': '../$id1.smv'},
        {...valid, 'mode': '120000'},
        {...valid, 'size': GitHubApi.maxVaultBytes + 1},
        {...valid, 'type': 'tree'},
      ]) {
        entries = [entry];
        await expectLater(
          api.snapshot('SYNTHETIC_ACCESS', repo),
          fails(GitHubProblem.format),
        );
      }
      entries = [valid];
      truncated = true;
      await expectLater(
        api.snapshot('SYNTHETIC_ACCESS', repo),
        fails(GitHubProblem.format),
      );
    },
  );

  test('unknown populated repository cannot be initialized', () async {
    final api = GitHubApi(
      transport: (_, uri, _, _, _) async {
        if (uri.path.contains('/git/ref/')) {
          return const GitHubResponse(200, {
            'object': {'sha': h0},
          });
        }
        if (uri.path.contains('/git/commits/')) {
          return const GitHubResponse(200, {
            'tree': {'sha': h1},
          });
        }
        return const GitHubResponse(200, {
          'truncated': false,
          'tree': [
            {
              'path': 'valuable-data',
              'sha': h2,
              'type': 'blob',
              'mode': '100644',
            },
          ],
        });
      },
    );
    await expectLater(
      api.snapshot(
        'SYNTHETIC_ACCESS',
        GitHubRepository.fromJson(repoJson()),
        initializing: true,
      ),
      fails(GitHubProblem.repositorySetup),
    );
  });

  test('cancel during token verification discards late response and never connects', () async {
    final pending = Completer<GitHubResponse>();
    final directory = await Directory.systemTemp.createTemp(
      'github-auth-cancel-unit-',
    );
    final storage = MemoryStorage(null);
    final api = GitHubApi(transport: (_, _, _, _, _) => pending.future);
    final backup = GitHubBackup(
      catalog: VaultCatalog(directory: directory),
      storage: storage,
      api: api,
    );
    try {
      await backup.initialize(schedule: false);
      final operation = backup.connectToken(syntheticToken, 'fixture/backup');
      backup.cancelConnection();
      pending.complete(
        const GitHubResponse(200, {'id': 42, 'login': 'fixture'}),
      );
      await operation;
      expect(backup.signedIn, false);
      expect(storage.writes, 0);
    } finally {
      backup.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('unreadable journal is not silently reset or overwritten', () async {
    final directory = await Directory.systemTemp.createTemp(
      'github-state-unit-',
    );
    final storage = MemoryStorage({'version': 999});
    final api = FakeGitHub();
    final backup = GitHubBackup(
      catalog: VaultCatalog(directory: directory),
      storage: storage,
      api: api,
    );
    try {
      await backup.initialize(schedule: false);
      await backup.sync();
      await backup.connectToken(syntheticToken, 'fixture/backup');
      expect(backup.problem, GitHubProblem.storage);
      expect(storage.writes, 0);
      expect(api.uploads, 0);
    } finally {
      backup.dispose();
      await directory.delete(recursive: true);
    }
  });

  test(
    'local save immediately marks previously confirmed backup pending',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'github-pending-unit-',
      );
      final catalog = VaultCatalog(directory: directory);
      final backup = GitHubBackup(
        catalog: catalog,
        storage: MemoryStorage(seed()),
        api: FakeGitHub(),
      );
      try {
        await backup.initialize(schedule: false);
        final session = await catalog.legacy.store.create(syntheticPassword);
        await backup.sync();
        expect(backup.status, BackupStatus.synced);
        await catalog.legacy.store.save(session, [], name: 'SYNTHETIC_CHANGED');
        expect(backup.status, BackupStatus.pending);
        session.lock();
      } finally {
        backup.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test('Windows DPAPI atomic state roundtrip and tamper rejection', () async {
    final directory = await Directory.systemTemp.createTemp(
      'github-dpapi-unit-',
    );
    try {
      final file = File('${directory.path}/state.dpapi');
      final storage = WindowsGitHubStorage(file);
      expect(await storage.read(), isNull);
      await storage.write(seed());
      expect(
        latin1.decode(await file.readAsBytes()),
        isNot(contains('SYNTHETIC_ACCESS')),
      );
      expect((await storage.read())!['userId'], 42);
      await storage.write(seed()..['login'] = 'updated');
      expect((await storage.read())!['login'], 'updated');
      final bytes = await file.readAsBytes();
      bytes[bytes.length - 1] ^= 1;
      await file.writeAsBytes(bytes);
      await expectLater(storage.read(), fails(GitHubProblem.storage));
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test('credential removal leaves no archived token journal', () async {
    final directory = await Directory.systemTemp.createTemp(
      'skysecret-journal-unit-',
    );
    try {
      final storage = WindowsGitHubStorage(
        File('${directory.path}/state.dpapi'),
      );
      await storage.write(seed());
      await storage.write(seed()..remove('credential'));
      expect((await storage.read())!.containsKey('credential'), isFalse);
      expect(
        (await directory.list().toList()).map((e) => e.uri.pathSegments.last),
        ['state.dpapi'],
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
