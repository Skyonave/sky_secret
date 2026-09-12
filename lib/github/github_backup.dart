import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../crypto/crypto.dart';
import 'github_api.dart';
import 'github_credentials.dart';
import 'github_storage.dart';

enum BackupStatus {
  disconnected,
  ready,
  pending,
  working,
  synced,
  conflict,
  failed,
}

class GitHubBackup extends ChangeNotifier {
  final VaultCatalog catalog;
  final GitHubStorage storage;
  final GitHubApi api;
  final Stream<void> _vaultChanges;
  Map<String, dynamic> _state = {
    'version': 2,
    'bindings': <String, dynamic>{},
    'enabled': false,
  };
  bool busy = false, _disposed = false, _storageFault = false, initialized = false;
  BackupStatus status = BackupStatus.disconnected;
  GitHubProblem? problem;
  GitHubRepository? repository;
  List<RemoteVault> remoteVaults = [];
  Set<String> conflicts = {};
  int mergedConflicts = 0;
  bool syncKeyChanged = false;
  bool syncRollback = false;
  Timer? _timer;
  bool _schedule = false;
  StreamSubscription<void>? _changes;
  int _localRevision = 0;
  int _connectionEpoch = 0;
  bool _retryAllowed = false;
  DateTime? _retryAt;

  GitHubBackup({
    required this.catalog,
    required this.storage,
    GitHubApi? api,
    Stream<void>? changes,
  }) : api = api ?? GitHubApi(),
       _vaultChanges = changes ?? VaultStore.changes;

  factory GitHubBackup.local() {
    final catalog = VaultCatalog.local();
    return GitHubBackup(
      catalog: catalog,
      storage: WindowsGitHubStorage(
        File('${catalog.directory.path}/github-state.dpapi'),
      ),
    );
  }

  bool get signedIn => _state['credential'] != null;

  bool get enabled => signedIn;

  bool get usable => initialized && !_storageFault && !_disposed;

  bool get legacyOAuthRemoved => _state['legacyOAuthRemoved'] == true;

  String get repositoryAddress => (_state['repositoryAddress'] as String?) ?? repository?.label ?? '';

  String? get login => _state['login'] as String?;

  int? get repositoryId => _state['repoId'] as int?;

  DateTime? get lastSync => _state['lastSync'] == null ? null : DateTime.parse(_state['lastSync'] as String);

  Map<String, dynamic> get _bindings => object(_state['bindings']);

  bool get connectionNeedsRecovery => _storageFault;

  bool isManual(String? localId) =>
      localId != null && _bindings[localId] != null && object(_bindings[localId])['manual'] == true;

  DateTime? lastVaultSync(String? localId) {
    final value = localId == null ? null : _bindings[localId];
    final date = value == null ? null : object(value)['lastSync'];
    return date is String ? DateTime.tryParse(date) : null;
  }

  bool matchesLastSync(String? localId, VaultSession session) {
    final binding = localId == null ? null : _bindings[localId];
    if (binding == null || object(binding)['revision'] == null) return false;
    try {
      final known = VaultRevision.fromJson(object(binding)['revision']);
      return known.includes(session.revision) &&
          session.revision.includes(known) &&
          known.keyEpoch == session.revision.keyEpoch;
    } on VaultFormatException {
      return false;
    }
  }

  Future<void> resetDamagedConnection() async {
    if (!_storageFault || busy || _disposed) return;
    busy = true;
    _notify();
    try {
      final files = await catalog.list();
      await _persist({
        'version': 2,
        'enabled': false,
        'bindings': <String, dynamic>{
          for (final file in files)
            file.id: <String, dynamic>{
              'remote': _newId(),
              'base': null,
              'manual': true,
            },
        },
      });
      _storageFault = false;
      initialized = true;
      _subscribeChanges();
      problem = null;
      status = BackupStatus.disconnected;
      repository = null;
      remoteVaults = [];
      conflicts = {};
      _timer?.cancel();
    } catch (_) {
      problem = GitHubProblem.storage;
      status = BackupStatus.failed;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> linkExistingVault(
    String localId,
    VaultStore store,
    VaultSession session,
    RemoteVault selected,
  ) => _run(() async {
    syncKeyChanged = false;
    final original = session.persistedBytes;
    final other = localForRemote(selected.id);
    if (other != null && other != localId && (await catalog.list()).any((v) => v.id == other)) {
      throw const GitHubFailure(GitHubProblem.conflict);
    }
    final token = await _token();
    final repo = await api.repository(
      token,
      repositoryId!,
      positiveInt(_state['userId']),
    );
    final remote = (await api.snapshot(token, repo)).vaults[selected.id];
    if (remote == null || remote.blob != selected.blob) {
      throw const GitHubFailure(GitHubProblem.conflict);
    }
    final bytes = await api.blob(token, repo, remote.blob);
    VaultSession? revision;
    try {
      try {
        revision = await session.openRevision(bytes);
      } on VaultUnlockException {
        syncKeyChanged = true;
        throw const GitHubFailure(GitHubProblem.conflict);
      }
      if (!listEquals(original, bytes) &&
          !session.revision.succeeds(revision.revision) &&
          !revision.revision.succeeds(session.revision)) {
        throw const GitHubFailure(GitHubProblem.conflict);
      }
      var base = remote.blob;
      var baseBytes = bytes;
      if (session.revision.includes(revision.revision)) {
      } else if (revision.revision.includes(session.revision)) {
        base = await gitBlobHash(original);
        baseBytes = original;
      } else {
        throw const GitHubFailure(GitHubProblem.conflict);
      }
      if (session.isLocked ||
          !listEquals(original, session.persistedBytes) ||
          !listEquals(original, await store.readEncryptedSnapshot())) {
        throw const GitHubFailure(GitHubProblem.conflict);
      }
      await store.cacheBaseline(base, baseBytes);
      final next = _copy();
      if (other != null && other != localId) {
        object(next['bindings']).remove(other);
      }
      object(next['bindings'])[localId] = <String, dynamic>{
        'remote': remote.id,
        'base': base,
        'manual': true,
      };
      await _persist(next);
      status = BackupStatus.pending;
    } finally {
      if (revision != null) session.closeRevision(revision);
    }
  }, cancelled: () => session.isLocked || _disposed);

  String? localForRemote(String remoteId) {
    for (final entry in _bindings.entries) {
      if (object(entry.value)['remote'] == remoteId) return entry.key;
    }
    return null;
  }

  Future<void> bindSynchronizedImport(
    String localId,
    RemoteVault remote,
  ) async {
    if (!usable || busy) {
      throw const GitHubFailure(GitHubProblem.conflict);
    }
    busy = true;
    _notify();
    try {
      final existing = localForRemote(remote.id);
      if (existing != null && (await catalog.list()).any((v) => v.id == existing)) {
        throw const GitHubFailure(GitHubProblem.conflict);
      }
      backupId(localId);
      final next = _copy();
      if (existing != null) object(next['bindings']).remove(existing);
      object(next['bindings'])[localId] = {
        'remote': backupId(remote.id),
        'base': sha(remote.blob),
        'manual': true,
      };
      await _persist(next);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> cancelSynchronizedImport(String localId) async {
    if (busy || !usable) return;
    busy = true;
    try {
      final next = _copy();
      object(next['bindings']).remove(localId);
      await _persist(next);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> synchronizeVault(
    String localId,
    VaultStore store,
    VaultSession session,
  ) async {
    mergedConflicts = 0;
    syncKeyChanged = false;
    syncRollback = false;
    await _run(() async {
      final original = session.persistedBytes;
      void active() {
        if (session.isLocked || _disposed) {
          throw const GitHubFailure(GitHubProblem.cancelled);
        }
        if (!listEquals(session.persistedBytes, original)) {
          throw const GitHubFailure(GitHubProblem.conflict);
        }
      }

      active();
      final next = _copy();
      final bindings = object(next['bindings']);
      bindings.putIfAbsent(
        localId,
        () => <String, dynamic>{'remote': _newId(), 'base': null},
      );
      object(bindings[localId])['manual'] = true;
      await _persist(next);
      final binding = object(_bindings[localId]);
      final id = backupId(binding['remote']);
      final baseline = binding['base'] as String?;
      final token = await _token();
      final repo = await api.repository(
        token,
        repositoryId!,
        positiveInt(_state['userId']),
      );
      final localHash = await gitBlobHash(original);
      session.writerId = await store.writerIdentity();
      if (baseline == localHash) await store.cacheBaseline(baseline!, original);
      Future<Uint8List> baseBytes() async {
        final cached = await store.readBaseline(baseline!);
        var bytes = cached;
        if (bytes == null) {
          for (final previous in await store.history()) {
            final candidate = await VaultStore(file: previous).readEncryptedSnapshot();
            if (await gitBlobHash(candidate) == baseline) {
              bytes = candidate;
              break;
            }
          }
        }
        bytes ??= await api.blob(token, repo, baseline);
        if (await gitBlobHash(bytes) != baseline) {
          throw const VaultFormatException();
        }
        await store.cacheBaseline(baseline, bytes);
        return bytes;
      }

      Future<VaultSession> openTrustedRevision(Uint8List bytes) async {
        try {
          return await session.openRevision(bytes);
        } on VaultUnlockException {
          syncKeyChanged = true;
          throw const GitHubFailure(GitHubProblem.conflict);
        }
      }

      if (baseline != null && localHash != baseline) {
        VaultSession? checkpoint;
        try {
          final known = binding['revision'] != null
              ? VaultRevision.fromJson(binding['revision'])
              : (checkpoint = await openTrustedRevision(await baseBytes())).revision;
          if (!session.revision.succeeds(known)) {
            syncRollback = true;
            throw const GitHubFailure(GitHubProblem.conflict);
          }
        } finally {
          if (checkpoint != null) session.closeRevision(checkpoint);
        }
      }
      for (var attempt = 0; attempt < 4; attempt++) {
        active();
        final remote = await api.snapshot(token, repo);
        final current = remote.vaults[id];
        VaultSession? remoteSession, baseSession, adopted;
        try {
          var encoded = original;
          var entries = session.entries;
          var folders = session.folders;
          var name = session.name;
          var conflictCount = 0;
          if (current?.blob != localHash && current?.blob != baseline) {
            if (current == null || baseline == null) {
              throw const GitHubFailure(GitHubProblem.conflict);
            }
            remoteSession = await openTrustedRevision(
              await api.blob(token, repo, current.blob),
            );
            baseSession = await openTrustedRevision(await baseBytes());
            if (!remoteSession.revision.succeeds(baseSession.revision) ||
                !session.revision.includes(baseSession.revision)) {
              syncRollback = true;
              throw const GitHubFailure(GitHubProblem.conflict);
            }
            active();
            final merged = await VaultMerge.combine(
              baseSession,
              session,
              remoteSession,
            );
            conflictCount = merged.conflicts;
            entries = merged.entries;
            folders = merged.folders;
            name = merged.name;
            if (await VaultMerge.sameContents(merged, remoteSession) &&
                remoteSession.revision.includes(session.revision) &&
                remoteSession.revision.keyEpoch >= session.revision.keyEpoch) {
              encoded = remoteSession.persistedBytes;
              adopted = remoteSession;
            } else {
              encoded = await session.encrypt(
                entries,
                folders: folders,
                name: name,
                mergeRevision: remoteSession.revision,
              );
              adopted = await session.openRevision(encoded);
            }
          }
          active();
          final hash = await gitBlobHash(encoded);
          if (current?.blob != hash) {
            if (!listEquals(await store.readEncryptedSnapshot(), original)) {
              throw const GitHubFailure(GitHubProblem.conflict);
            }
            await api.upload(token, repo, encoded);
            final commit = await api.commit(token, repo, remote, {id: hash});
            final checked = await api.repository(
              token,
              repo.id,
              positiveInt(_state['userId']),
            );
            if (checked.branch != repo.branch) {
              throw const GitHubFailure(GitHubProblem.repositoryChanged);
            }
            active();
            try {
              await api.publish(token, repo, commit);
            } on GitHubFailure catch (error) {
              if (error.problem == GitHubProblem.conflict) continue;
              rethrow;
            }
          }
          final confirmed = await api.snapshot(token, repo);
          if (confirmed.vaults[id]?.blob != hash) continue;
          active();
          if (!listEquals(original, encoded)) {
            await store.acceptSynchronized(
              session,
              original,
              encoded,
              entries,
              folders,
              name,
              authenticated: adopted,
            );
          } else if (!listEquals(
            await store.readEncryptedSnapshot(),
            original,
          )) {
            throw const GitHubFailure(GitHubProblem.conflict);
          }
          if (session.isLocked) {
            throw const GitHubFailure(GitHubProblem.cancelled);
          }
          await store.cacheBaseline(hash, encoded);
          final acknowledged = _copy();
          object(object(acknowledged['bindings'])[localId])['base'] = hash;
          object(object(acknowledged['bindings'])[localId])['revision'] = session.revision.toJson();
          object(object(acknowledged['bindings'])[localId])['lastSync'] = DateTime.now().toUtc().toIso8601String();
          final pending = acknowledged['pending'];
          if (pending != null) {
            final updates = object(object(pending)['updates']);
            updates.remove(id);
            if (updates.isEmpty) acknowledged.remove('pending');
          }
          acknowledged['lastSync'] = DateTime.now().toUtc().toIso8601String();
          await _persist(acknowledged);
          await store.pruneBaselines({hash, ?baseline});
          mergedConflicts = conflictCount;
          remoteVaults = confirmed.vaults.values.toList();
          conflicts = {};
          status = BackupStatus.synced;
          return;
        } finally {
          if (adopted != null && adopted != remoteSession) {
            session.closeRevision(adopted);
            remoteSession?.closeRevision(adopted);
          }
          if (remoteSession != null) session.closeRevision(remoteSession);
          if (baseSession != null) session.closeRevision(baseSession);
        }
      }
      throw const GitHubFailure(GitHubProblem.conflict);
    }, cancelled: () => session.isLocked || _disposed);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize({bool schedule = true}) async {
    _schedule = schedule;
    try {
      final saved = await storage.read();
      if (saved != null) {
        if ((saved['version'] != 1 && saved['version'] != 2) ||
            saved['bindings'] is! Map<String, dynamic> ||
            saved['enabled'] is! bool) {
          throw const GitHubFailure(GitHubProblem.storage);
        }
        if (saved['userId'] != null) positiveInt(saved['userId']);
        if (saved['repoId'] != null) positiveInt(saved['repoId']);
        if (saved['version'] == 2 && saved['credential'] != null) {
          FineGrainedToken(string(saved['credential']));
          positiveInt(saved['userId']);
          positiveInt(saved['repoId']);
        }
        if (saved['lastSync'] != null) {
          DateTime.parse(string(saved['lastSync']));
        }
        final remoteIds = <String>{};
        for (final entry in object(saved['bindings']).entries) {
          if (entry.key != 'legacy') backupId(entry.key);
          final binding = object(entry.value);
          if (!remoteIds.add(backupId(binding['remote']))) {
            throw const GitHubFailure(GitHubProblem.storage);
          }
          if (binding['base'] != null) sha(binding['base']);
          if (binding['manual'] != null && binding['manual'] is! bool) {
            throw const GitHubFailure(GitHubProblem.storage);
          }
        }
        if (saved['pending'] != null) {
          final pending = object(saved['pending']);
          sha(pending['commit']);
          for (final entry in object(pending['updates']).entries) {
            backupId(entry.key);
            sha(entry.value);
          }
        }
        if (saved['version'] == 1) {
          for (final key in [
            'tokens',
            'clientId',
            'creationTag',
            'creationName',
            'initializing',
          ]) {
            saved.remove(key);
          }
          saved['version'] = 2;
          saved['enabled'] = false;
          saved['legacyOAuthRemoved'] = true;
          await _persist(saved);
        } else {
          _state = saved;
        }
      }
      initialized = true;
      _schedule = schedule;
      status = signedIn ? BackupStatus.ready : BackupStatus.disconnected;
      _subscribeChanges();
      if (schedule) {
        unawaited(_tick());
      }
    } catch (_) {
      initialized = true;
      _storageFault = true;
      problem = GitHubProblem.storage;
      status = BackupStatus.failed;
    }
    _notify();
  }

  void _subscribeChanges() {
    _changes ??= _vaultChanges.listen((_) {
      _localRevision++;
      if (status == BackupStatus.synced || status == BackupStatus.ready) {
        status = signedIn ? BackupStatus.pending : BackupStatus.disconnected;
        _notify();
      }
      _scheduleSync();
    });
  }

  Future<void> _persist(Map<String, dynamic> next) async {
    try {
      await storage.write(next);
    } catch (_) {
      _storageFault = true;
      throw const GitHubFailure(GitHubProblem.storage);
    }
    _state = next;
  }

  Map<String, dynamic> _copy() => object(jsonDecode(jsonEncode(_state)));

  Future<void> _run(
    Future<void> Function() action, {
    bool Function()? cancelled,
  }) async {
    if (busy || !usable) return;
    final revision = _localRevision;
    busy = true;
    problem = null;
    status = BackupStatus.working;
    _notify();
    try {
      await action();
      _retryAllowed = false;
      _retryAt = null;
      if (status == BackupStatus.working) {
        status = signedIn ? BackupStatus.ready : BackupStatus.disconnected;
      }
    } catch (error) {
      final failure = cancelled?.call() == true
          ? const GitHubFailure(GitHubProblem.cancelled)
          : switch (error) {
              GitHubFailure() => error,
              VaultUnlockException() => const GitHubFailure(
                GitHubProblem.authorization,
              ),
              VaultFormatException() => const GitHubFailure(
                GitHubProblem.format,
              ),
              VaultConflictException() => const GitHubFailure(
                GitHubProblem.conflict,
              ),
              _ => const GitHubFailure(GitHubProblem.storage),
            };
      problem = failure.problem;
      status = failure.problem == GitHubProblem.conflict ? BackupStatus.conflict : BackupStatus.failed;
      if (failure.problem == GitHubProblem.cancelled) {
        problem = null;
        status = signedIn ? BackupStatus.ready : BackupStatus.disconnected;
      }
      _retryAllowed =
          failure.problem == GitHubProblem.network ||
          (failure.problem == GitHubProblem.denied && failure.retryAfter != null);
      final retry = failure.retryAfter;
      _retryAt = DateTime.now().add(
        retry != null && retry > const Duration(minutes: 30) ? retry : const Duration(minutes: 30),
      );
    } finally {
      busy = false;
      _notify();
      if (_retryAllowed || revision != _localRevision) {
        _scheduleSync();
      }
    }
  }

  void _scheduleSync() {
    if (!_schedule || !signedIn || !usable) return;
    final remaining = _retryAt?.difference(DateTime.now());
    final delay = remaining != null && remaining > const Duration(seconds: 5) ? remaining : const Duration(seconds: 5);
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (!enabled ||
        !signedIn ||
        !usable ||
        busy ||
        problem == GitHubProblem.authorization ||
        (problem == GitHubProblem.denied && !_retryAllowed) ||
        problem == GitHubProblem.identity ||
        problem == GitHubProblem.conflict ||
        problem == GitHubProblem.repositoryChanged ||
        problem == GitHubProblem.repositorySetup ||
        problem == GitHubProblem.format ||
        problem == GitHubProblem.missing) {
      return;
    }
    if (_retryAt != null && DateTime.now().isBefore(_retryAt!)) {
      _scheduleSync();
      return;
    }
    await sync(onlyIfChanged: true);
  }

  void cancelConnection() {
    _connectionEpoch++;
  }

  Future<void> connectToken(
    String rawToken,
    String address, {
    bool initializeRepository = false,
  }) => _run(() async {
    final token = FineGrainedToken(rawToken).value;
    final target = GitHubRepositoryAddress.parse(address);
    final epoch = ++_connectionEpoch;
    void checkCancelled() {
      if (_disposed || epoch != _connectionEpoch) {
        throw const GitHubFailure(GitHubProblem.cancelled);
      }
    }

    final user = await api.user(token);
    checkCancelled();
    if (_state['userId'] != null && _state['userId'] != user.id) {
      throw const GitHubFailure(GitHubProblem.identity);
    }
    final repo = await api.repositoryByAddress(token, target, user.id);
    checkCancelled();
    final unusedLegacySelection =
        legacyOAuthRemoved && !signedIn && _bindings.isEmpty && _state['pending'] == null && _state['lastSync'] == null;
    if (repositoryId != null && repositoryId != repo.id && !unusedLegacySelection) {
      throw const GitHubFailure(GitHubProblem.repositoryChanged);
    }
    var remote = await api.snapshot(
      token,
      repo,
      initializing: initializeRepository,
    );
    checkCancelled();
    if (initializeRepository) {
      final commit = await api.commit(token, repo, remote, {});
      checkCancelled();
      final checked = await api.repository(token, repo.id, user.id);
      if (checked.branch != repo.branch) {
        throw const GitHubFailure(GitHubProblem.conflict);
      }
      checkCancelled();
      await api.publish(token, checked, commit);
      remote = await api.snapshot(token, checked);
      checkCancelled();
    }
    final previous = _copy();
    await _persist(
      _copy()
        ..['credential'] = token
        ..['userId'] = user.id
        ..['login'] = user.login
        ..['repoId'] = repo.id
        ..['repositoryAddress'] = repo.label
        ..remove('legacyOAuthRemoved')
        ..['enabled'] = true,
    );
    if (_disposed || epoch != _connectionEpoch) {
      await _persist(previous);
      throw const GitHubFailure(GitHubProblem.cancelled);
    }
    repository = repo;
    remoteVaults = remote.vaults.values.toList();
    _retryAt = null;
    _scheduleSync();
  });

  Future<String> _token() async {
    if (!signedIn) throw const GitHubFailure(GitHubProblem.authorization);
    return FineGrainedToken(string(_state['credential'])).value;
  }

  Future<void> discover() => _run(() async {
    final token = await _token();
    final repo = await api.repository(
      token,
      repositoryId!,
      positiveInt(_state['userId']),
    );
    final remote = await api.snapshot(token, repo);
    repository = repo;
    remoteVaults = remote.vaults.values.toList();
    await _persist(_copy()..['repositoryAddress'] = repo.label);
  });

  Future<void> disconnect() => _run(() async {
    await _persist(
      _copy()
        ..remove('credential')
        ..['enabled'] = false,
    );
    status = BackupStatus.disconnected;
    _timer?.cancel();
  });

  Future<void> sync({bool onlyIfChanged = false}) => _run(() async {
    if (onlyIfChanged && !await _hasLocalChanges()) {
      status = await _hasManualChanges() ? BackupStatus.pending : BackupStatus.synced;
      return;
    }
    await _sync();
  });

  Future<bool> _hasManualChanges() async {
    for (final file in await catalog.list()) {
      final binding = _bindings[file.id];
      if (binding != null &&
          object(binding)['manual'] == true &&
          await gitBlobHash(await file.store.readEncryptedSnapshot()) != object(binding)['base']) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _hasLocalChanges() async {
    if (_state['pending'] != null) {
      final updates = object(object(_state['pending'])['updates']);
      if (_bindings.values.any((value) {
        final b = object(value);
        return b['manual'] != true && updates.containsKey(b['remote']);
      })) {
        return true;
      }
    }
    for (final file in await catalog.list()) {
      final binding = _bindings[file.id];
      if (binding != null && object(binding)['manual'] == true) continue;
      if (binding == null || object(binding)['base'] == null) return true;
      final bytes = await file.store.readEncryptedSnapshot();
      if (await gitBlobHash(bytes) != object(binding)['base']) return true;
    }
    return false;
  }

  static String _newId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<void> _sync() async {
    final localRevision = _localRevision;
    if (repositoryId == null) {
      throw const GitHubFailure(GitHubProblem.configuration);
    }
    final token = await _token();
    var repo = await api.repository(
      token,
      repositoryId!,
      positiveInt(_state['userId']),
    );
    repository = repo;
    final remote = await api.snapshot(token, repo);
    remoteVaults = remote.vaults.values.toList();
    conflicts = {};

    final pending = _state['pending'];
    if (pending != null) {
      final updates = object(object(pending)['updates']);
      if (updates.entries.every((e) => remote.vaults[e.key]?.blob == e.value)) {
        final next = _copy();
        for (final value in object(next['bindings']).values) {
          final binding = object(value);
          if (binding['manual'] == true) continue;
          if (updates.containsKey(binding['remote'])) {
            binding['base'] = updates[binding['remote']];
          }
        }
        next.remove('pending');
        await _persist(next);
      } else {
        await _persist(_copy()..remove('pending'));
      }
    }

    final files = await catalog.list();
    final next = _copy();
    for (final file in files) {
      object(next['bindings']).putIfAbsent(file.id, () => {'remote': _newId(), 'base': null});
    }
    await _persist(next);
    final updates = <String, String>{};
    for (final file in files) {
      final binding = object(_bindings[file.id]);
      if (binding['manual'] == true) continue;
      final id = backupId(binding['remote']);
      final currentRemote = remote.vaults[id]?.blob;
      if (currentRemote != binding['base']) {
        conflicts.add(file.id);
        continue;
      }
      final bytes = await file.store.readEncryptedSnapshot();
      final hash = await gitBlobHash(bytes);
      if (hash == binding['base']) continue;
      updates[id] = await api.upload(token, repo, bytes);
    }
    if (conflicts.isNotEmpty) throw const GitHubFailure(GitHubProblem.conflict);
    if (updates.isNotEmpty) {
      final commit = await api.commit(token, repo, remote, updates);
      await _persist(
        _copy()..['pending'] = {'commit': commit, 'updates': updates},
      );
      final checked = await api.repository(
        token,
        repo.id,
        positiveInt(_state['userId']),
      );
      if (checked.branch != repo.branch) {
        throw const GitHubFailure(GitHubProblem.conflict);
      }
      repo = checked;
      await api.publish(token, repo, commit);
      final confirmed = await api.snapshot(token, repo);
      if (!updates.entries.every(
        (e) => confirmed.vaults[e.key]?.blob == e.value,
      )) {
        throw const GitHubFailure(GitHubProblem.conflict);
      }
      final acknowledged = _copy()..remove('pending');
      for (final value in object(acknowledged['bindings']).values) {
        final binding = object(value);
        if (updates.containsKey(binding['remote'])) {
          binding['base'] = updates[binding['remote']];
        }
      }
      await _persist(acknowledged);
      remoteVaults = confirmed.vaults.values.toList();
    }
    await _persist(
      _copy()..['lastSync'] = DateTime.now().toUtc().toIso8601String(),
    );
    status = localRevision == _localRevision && !await _hasManualChanges() ? BackupStatus.synced : BackupStatus.pending;
  }

  Future<void> keepBoth() => _run(() async {
    if (conflicts.isEmpty) throw const GitHubFailure(GitHubProblem.conflict);
    final next = _copy()..remove('pending');
    for (final localId in conflicts) {
      object(next['bindings'])[localId] = {'remote': _newId(), 'base': null};
    }
    await _persist(next);
    conflicts = {};
    await _sync();
  });

  Future<Uint8List?> download(RemoteVault vault) async {
    Uint8List? bytes;
    await _run(() async {
      final token = await _token();
      final repo = await api.repository(
        token,
        repositoryId!,
        positiveInt(_state['userId']),
      );
      final remote = await api.snapshot(token, repo);
      if (remote.vaults[vault.id]?.blob != vault.blob) {
        throw const GitHubFailure(GitHubProblem.conflict);
      }
      bytes = await api.blob(token, repo, vault.blob);
    });
    return bytes;
  }

  @override
  void dispose() {
    _disposed = true;
    _connectionEpoch++;
    _timer?.cancel();
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
