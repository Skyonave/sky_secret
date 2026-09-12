import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../storage/app_data_directory.dart';
import '../storage/windows_dpapi.dart';
import 'vault_cipher.dart';
import 'vault_revision.dart';

class VaultConflictException implements Exception {
  const VaultConflictException();
}

class VaultStore {
  static final _changes = StreamController<void>.broadcast(sync: true);
  final File file;
  final Future<void> Function()? beforeCommit;
  final Future<void> Function()? beforeSnapshotCleanup;
  bool _writing = false;
  bool snapshotCleanupPending = false;

  static Stream<void> get changes => _changes.stream;

  VaultStore({
    required this.file,
    this.beforeCommit,
    this.beforeSnapshotCleanup,
  });

  factory VaultStore.local() {
    return VaultStore(
      file: File(
        '${appDataDirectory().path}'
        '${Platform.pathSeparator}vault.smv',
      ),
    );
  }

  Future<bool> exists() async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return false;
    if (type != FileSystemEntityType.file) {
      throw const FileSystemException('Vault path is not a regular file');
    }
    return true;
  }

  Future<Uint8List> _read() async {
    if (!await exists()) throw const FileSystemException('Vault is missing');
    final handle = await file.open();
    try {
      if (await handle.length() > VaultCipher.maxFileBytes) {
        throw const VaultFormatException();
      }
      final bytes = await handle.read(VaultCipher.maxFileBytes + 1);
      if (bytes.length > VaultCipher.maxFileBytes) {
        throw const VaultFormatException();
      }
      return bytes;
    } finally {
      await handle.close();
    }
  }

  Future<VaultSession> create(String password, {String? name}) async {
    final session = await VaultCipher.create(password, name: name);
    try {
      await _commit(session.persistedBytes, null);
      return session;
    } catch (_) {
      session.lock();
      rethrow;
    }
  }

  Future<VaultSession> unlock(String password) async {
    final session = await VaultCipher.unlock(await _read(), password);
    try {
      if (await FileSystemEntity.type(_rotationMarker.path, followLinks: false) == FileSystemEntityType.notFound) {
        snapshotCleanupPending = false;
        return session;
      }
      final lock = await File('${file.path}.lock').open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive);
        if (!_same(await _read(), session.persistedBytes)) throw const VaultConflictException();
        await _resumeSnapshotCleanup(session.persistedBytes);
      } finally {
        await lock.close();
      }
      return session;
    } catch (_) {
      session.lock();
      rethrow;
    }
  }

  Future<Uint8List> readEncryptedSnapshot() => _read();

  Future<VaultSession> importEncryptedSnapshot(
    Uint8List bytes,
    String password, {
    bool Function()? allowed,
  }) async {
    final session = await VaultCipher.unlock(bytes, password);
    try {
      await _commit(session.persistedBytes, null, allowed: allowed);
      return session;
    } catch (_) {
      session.lock();
      rethrow;
    }
  }

  Future<VaultSession> importFrom(
    File source,
    String password, {
    bool Function()? allowed,
  }) async {
    final session = await VaultStore(file: source).unlock(password);
    try {
      await _commit(session.persistedBytes, null, allowed: allowed);
      return session;
    } catch (_) {
      session.lock();
      rethrow;
    }
  }

  Future<void> exportTo(
    VaultSession session,
    File destination, {
    bool Function()? allowed,
  }) async {
    if (session.isLocked) throw StateError('Vault is locked');
    await VaultStore(file: destination)._commit(
      session.persistedBytes,
      null,
      allowed: () => !session.isLocked && (allowed?.call() ?? true),
      lockDestination: false,
    );
  }

  Future<void> delete({bool Function()? allowed}) async {
    if (_writing) throw const VaultConflictException();
    _writing = true;
    RandomAccessFile? lock;
    try {
      if (!await exists()) throw const VaultConflictException();
      lock = await File('${file.path}.lock').open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      if (!await exists()) throw const VaultConflictException();
      await beforeCommit?.call();
      if (!(allowed?.call() ?? true)) {
        throw StateError('Operation was cancelled');
      }
      await _archive(await _read());
      if (!(allowed?.call() ?? true)) {
        throw StateError('Operation was cancelled');
      }
      await file.delete();
      _changes.add(null);
      await _trimHistory();
    } finally {
      try {
        await lock?.close();
      } finally {
        _writing = false;
      }
    }
  }

  Future<VaultSession> changePassword(
    VaultSession session,
    String current,
    String password,
  ) async {
    final verified = await VaultCipher.unlock(session.persistedBytes, current);
    verified.lock();
    session.writerId = await writerIdentity();
    final replacement = await session.changePassword(password);
    try {
      await _commit(
        replacement.persistedBytes,
        session.persistedBytes,
        allowed: () => !session.isLocked,
        archivePrevious: false,
        purgeSnapshots: true,
      );
      session.lock();
      return replacement;
    } catch (_) {
      replacement.lock();
      rethrow;
    }
  }

  static Future<void> extract(
    VaultSession session,
    VaultAttachment attachment,
    File destination,
  ) async {
    if (session.isLocked || !session.entries.any((e) => e.attachments.contains(attachment))) {
      throw StateError('Attachment is unavailable');
    }
    final bytes = attachment.bytes;
    try {
      await VaultStore(file: destination)._commit(
        bytes,
        null,
        allowed: () => !session.isLocked,
        lockDestination: false,
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> save(
    VaultSession session,
    List<VaultEntry> entries, {
    List<VaultFolder>? folders,
    String? name,
  }) async {
    final snapshot = session.prepareEntries(entries);
    final groups = List<VaultFolder>.of(folders ?? session.folders);
    final title = name ?? session.name;
    final previous = session.persistedBytes;
    session.writerId = await writerIdentity();
    final encoded = await session.encrypt(
      snapshot,
      folders: groups,
      name: title,
    );
    if (session.isLocked) throw StateError('Vault is locked');
    await _commit(encoded, previous, allowed: () => !session.isLocked);
    if (!session.isLocked) {
      session.acceptPersisted(encoded, snapshot, groups, title);
    }
  }

  Future<void> acceptSynchronized(
    VaultSession session,
    Uint8List previous,
    Uint8List encoded,
    List<VaultEntry> entries,
    List<VaultFolder> folders,
    String? name, {
    VaultSession? authenticated,
  }) async {
    if (session.isLocked || !_same(session.persistedBytes, previous)) {
      throw const VaultConflictException();
    }
    if (authenticated != null) {
      session.validateAdoption(authenticated);
      if (!_same(encoded, authenticated.persistedBytes)) {
        throw const VaultConflictException();
      }
    }
    await _commit(
      encoded,
      previous,
      allowed: () => !session.isLocked && !(authenticated?.isLocked ?? false),
      archivePrevious: authenticated == null || authenticated.revision.keyEpoch == session.revision.keyEpoch,
      purgeSnapshots: authenticated != null && authenticated.revision.keyEpoch > session.revision.keyEpoch,
    );
    if (!session.isLocked) {
      if (authenticated != null) {
        session.adoptRevision(authenticated);
      } else {
        session.acceptPersisted(encoded, entries, folders, name);
      }
    }
  }

  Future<void> _commit(
    Uint8List encoded,
    Uint8List? previous, {
    bool Function()? allowed,
    bool lockDestination = true,
    bool archivePrevious = true,
    bool purgeSnapshots = false,
  }) async {
    assert(lockDestination || previous == null);
    if (_writing) throw const VaultConflictException();
    _writing = true;
    RandomAccessFile? lock;
    File? staged;
    var committed = false;
    var rotationPrepared = false;
    try {
      await file.parent.create(recursive: true);
      if (lockDestination || !Platform.isWindows) {
        lock = await File('${file.path}.lock').open(mode: FileMode.append);
        await lock.lock(FileLock.exclusive);
      }
      final present = await exists();
      if (previous == null ? present : !present) {
        throw const VaultConflictException();
      }
      if (previous != null && !_same(await _read(), previous)) {
        throw const VaultConflictException();
      }
      if (previous != null && lockDestination && (archivePrevious || purgeSnapshots)) {
        await _resumeSnapshotCleanup(previous);
        if (purgeSnapshots && snapshotCleanupPending) {
          throw const FileSystemException('Previous snapshot cleanup is incomplete');
        }
      }
      final stagingDirectory = await file.parent.createTemp('vault-staging-');
      staged = File(
        '${stagingDirectory.path}${Platform.pathSeparator}ciphertext',
      );
      await staged.writeAsBytes(encoded, flush: true);
      await beforeCommit?.call();
      if (!(allowed?.call() ?? true)) {
        throw StateError('Operation was cancelled');
      }
      if (previous != null && lockDestination && archivePrevious) {
        await _archive(previous);
      }
      if (!(allowed?.call() ?? true)) {
        throw StateError('Operation was cancelled');
      }
      if (purgeSnapshots) {
        await VaultStore(file: _rotationMarker)._commit(
          Uint8List.fromList(encoded.sublist(0, 116)),
          null,
          lockDestination: false,
        );
        rotationPrepared = true;
      }
      if (!(allowed?.call() ?? true)) {
        throw StateError('Operation was cancelled');
      }
      if (Platform.isWindows) {
        using((arena) {
          final result = MoveFileEx(
            PCWSTR(staged!.path.toNativeUtf16(allocator: arena)),
            PCWSTR(file.path.toNativeUtf16(allocator: arena)),
            MOVEFILE_WRITE_THROUGH | (previous == null ? 0 : MOVEFILE_REPLACE_EXISTING),
          );
          if (!result.value) {
            throw const FileSystemException('Could not commit vault');
          }
        });
      } else {
        await staged.rename(file.path);
      }
      committed = true;
      if (purgeSnapshots) await _resumeSnapshotCleanup(encoded);
      if (lockDestination && (archivePrevious || purgeSnapshots)) {
        _changes.add(null);
        if (previous != null && archivePrevious) await _trimHistory();
      }
    } finally {
      try {
        if (staged != null) {
          if (await staged.exists()) await staged.delete();
          await staged.parent.delete();
        }
      } on FileSystemException catch (_) {}
      if (rotationPrepared && !committed) {
        try {
          await _rotationMarker.delete();
        } on FileSystemException catch (_) {}
      }
      try {
        await lock?.close();
      } finally {
        _writing = false;
      }
    }
  }

  Future<String> writerIdentity({int attempt = 0}) async {
    final identity = VaultStore(file: File('${file.path}.writer'));
    String? id;
    final previous = await identity.exists() ? await identity._read() : null;
    if (previous != null) {
      try {
        final plain = protectDeviceData(previous, decrypt: true);
        try {
          id = utf8.decode(plain);
        } finally {
          plain.fillRange(0, plain.length, 0);
        }
      } on DeviceProtectionException catch (_) {}
    }
    if (id == null) {
      id = VaultRevision.randomId();
      final encoded = protectDeviceData(utf8.encode(id));
      try {
        await identity._commit(
          encoded,
          previous,
          lockDestination: true,
          archivePrevious: false,
        );
      } on VaultConflictException {
        if (attempt >= 3) rethrow;
        return writerIdentity(attempt: attempt + 1);
      }
    }
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw const VaultFormatException();
    }
    final digest = await Sha256().hash(
      utf8.encode('$id/${file.absolute.path.toLowerCase()}'),
    );
    return digest.bytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Directory get historyDirectory => Directory('${file.path}.history');

  File get _rotationMarker => File('${file.path}.rotation');

  Future<void> _resumeSnapshotCleanup(Uint8List current) async {
    snapshotCleanupPending = true;
    try {
      final markerType = await FileSystemEntity.type(_rotationMarker.path, followLinks: false);
      if (markerType == FileSystemEntityType.notFound) {
        snapshotCleanupPending = false;
        return;
      }
      if (markerType != FileSystemEntityType.file) throw const VaultFormatException();
      final handle = await _rotationMarker.open();
      late Uint8List envelope;
      try {
        if (await handle.length() != 116) throw const VaultFormatException();
        envelope = await handle.read(117);
      } finally {
        await handle.close();
      }
      if (current.length < 116 || !_same(envelope, current.sublist(0, 116))) {
        await _rotationMarker.delete();
        snapshotCleanupPending = false;
        return;
      }
      await beforeSnapshotCleanup?.call();
      await _removeSnapshots(historyDirectory, RegExp(r'^[0-9a-f]{64}\.smv$'));
      await _removeSnapshots(Directory('${file.path}.sync'), RegExp(r'^[0-9a-f]{40}\.smv$'));
      await _rotationMarker.delete();
      snapshotCleanupPending = false;
    } on FileSystemException catch (_) {
    } on VaultFormatException catch (_) {}
  }

  static Future<void> _removeSnapshots(Directory directory, RegExp names) async {
    final type = await FileSystemEntity.type(directory.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory) throw const VaultFormatException();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !names.hasMatch(entity.uri.pathSegments.last)) throw const VaultFormatException();
      await entity.delete();
    }
  }

  Future<void> _archive(Uint8List bytes) async {
    await _checkDirectory(historyDirectory);
    final digest = (await _snapshotDigest(bytes)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final snapshot = VaultStore(
      file: File('${historyDirectory.path}/$digest.smv'),
    );
    if (await snapshot.exists()) {
      if (!_same(await snapshot._read(), bytes)) {
        throw const VaultConflictException();
      }
      await snapshot.file.setLastModified(DateTime.now());
      return;
    }
    await snapshot._commit(bytes, null, lockDestination: false);
  }

  Future<List<File>> history() async {
    final type = await FileSystemEntity.type(
      historyDirectory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return [];
    if (type != FileSystemEntityType.directory) {
      throw const VaultFormatException();
    }
    final result = <File>[];
    await for (final entity in historyDirectory.list(followLinks: false)) {
      if (entity is File && RegExp(r'^[0-9a-f]{64}\.smv$').hasMatch(entity.uri.pathSegments.last)) {
        result.add(entity);
      }
    }
    final dates = <String, DateTime>{};
    for (final f in result) {
      dates[f.path] = await f.lastModified();
    }
    result.sort((a, b) => dates[b.path]!.compareTo(dates[a.path]!));
    return result;
  }

  Future<void> _trimHistory() async {
    try {
      var count = 0, total = 0;
      for (final snapshot in await history()) {
        final size = await snapshot.length();
        count++;
        total += size;
        if (count > 20 || total > 256 * 1024 * 1024) await snapshot.delete();
      }
    } on VaultFormatException catch (_) {
    } on FileSystemException catch (_) {}
  }

  Future<void> cacheBaseline(String hash, Uint8List bytes) async {
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(hash)) {
      throw const VaultFormatException();
    }
    final lock = await File('${file.path}.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      final current = await _read();
      await _resumeSnapshotCleanup(current);
      if (!VaultCipher.sameKeyEnvelope(current, bytes)) return;
      await _checkDirectory(Directory('${file.path}.sync'));
      final cache = VaultStore(file: File('${file.path}.sync/$hash.smv'));
      if (await cache.exists()) {
        if (!_same(await cache._read(), bytes)) throw const VaultConflictException();
      } else {
        await cache._commit(bytes, null, lockDestination: false);
      }
    } finally {
      await lock.close();
    }
  }

  Future<Uint8List?> readBaseline(String hash) async {
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(hash)) {
      throw const VaultFormatException();
    }
    final cache = VaultStore(file: File('${file.path}.sync/$hash.smv'));
    return await cache.exists() ? cache._read() : null;
  }

  static Future<void> _checkDirectory(Directory directory) async {
    var type = await FileSystemEntity.type(directory.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await directory.create(recursive: true);
      type = await FileSystemEntity.type(directory.path, followLinks: false);
    }
    if (type != FileSystemEntityType.directory) {
      throw const VaultFormatException();
    }
  }

  Future<void> pruneBaselines(Set<String> retain) async {
    try {
      final directory = Directory('${file.path}.sync');
      await _checkDirectory(directory);
      final files = <File>[];
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && RegExp(r'^[0-9a-f]{40}\.smv$').hasMatch(entity.uri.pathSegments.last)) {
          files.add(entity);
        }
      }
      final dates = <String, DateTime>{};
      for (final f in files) {
        dates[f.path] = await f.lastModified();
      }
      files.sort((a, b) => dates[b.path]!.compareTo(dates[a.path]!));
      var count = 0;
      for (final f in files) {
        if (retain.contains(f.uri.pathSegments.last.substring(0, 40))) continue;
        if (++count > 2) await f.delete();
      }
    } on VaultFormatException catch (_) {
    } on FileSystemException catch (_) {}
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

Future<Hash> _snapshotDigest(Uint8List bytes) => Isolate.run(() => Sha256().hash(bytes));
